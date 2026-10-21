extends Node2D
## FleetwayLaser — rayo continuo de Fleetway Supersonic.
##
## Sigue el patrón de LanzaProjectile de King:
##   - El servidor es la autoridad y mantiene el origen pegado al caster.
##   - El rayo nace en los ojos y su punta termina en el punto apuntado
##     (cursor del mouse o dirección del mando), recortado por paredes y rango.
##   - La punta se extiende rápidamente desde el origen al disparar y luego
##     persigue el apuntado durante toda la canalización.
##   - Un Area2D ("HurtboxDetector") recorre toda la longitud y avisa a la
##     habilidad mediante on_hit_callback, que aplica burn.
##
## Se instancia mediante HitboxService con type="projectile" para que el
## MultiplayerSpawner de World/Projectiles replique la escena automáticamente.

const BODY_TEXTURE := preload("res://Characters/Fleetway/Lazer_point.png")
const TIP_TEXTURE := preload("res://Characters/Fleetway/Lazer_finale.png")

# Escala 4x respecto al arte original.
const BODY_HEIGHT: float = 16.0
const HIT_HEIGHT: float = 24.0
const BODY_SEGMENT_WIDTH: float = 120.0
const TEXTURE_SEGMENT_WIDTH: float = 30.0
const TEXTURE_SEGMENT_HEIGHT: float = 4.0
const TEXTURE_SCALE: float = 4.0
const TIP_DRAW_SIZE: float = 72.0

# Ojos de Fleetway dentro del frame 48x48 (centro del frame = 24,24).
# Se multiplica por CharacterData.sprite_scale y se espeja según facing.
# (Sustituido por eye_offset_px / eye_world_offset, ajustables en el inspector.)

const WALL_MARGIN: float = 2.0
const DEFAULT_RANGE: float = 1200.0
const DEFAULT_AIM_DISTANCE: float = 1200.0
const EXTEND_SPEED: float = 8000.0
const RETRACT_SPEED: float = 20000.0

# ── Compatibilidad con HitboxService ──────────────────────────────────
var attacker_id: int = -1
var attacker_node: Node = null
var damage: int = 0
var attack_type: String = "burn"
var hit_limit: int = 0
var team_filter: String = "enemy"
var lifetime: float = 4.0
var speed: float = 0.0
var aim_mode: String = "fixed"
var detect_walls: bool = true
var impact_lifetime: float = 0.0
var hitbox_max_range: float = DEFAULT_RANGE
var on_hit_callback: Callable
var on_end_callback: Callable

# ── Origen del rayo (ajustable desde el inspector) ────────────────────
## Centro del ojo dentro del frame de arte 48x48 (centro del frame = 24,24).
## Pose "lazer": el ojo está en ≈ (31, 23). Se multiplica por sprite_scale.
@export var eye_offset_px: Vector2 = Vector2(7.0, -1.0)
## Ajuste fino en píxeles de mundo; NO se multiplica por sprite_scale.
## +X = hacia delante, +Y = abajo.
@export var eye_world_offset: Vector2 = Vector2.ZERO

# ── Referencia fuerte a la habilidad (linaje de vida) ────────────────
## Patrón LanzaProjectile/TopoSpear: el hitbox guarda la instancia de la
## habilidad para que el RefCounted no se libere al terminar activate().
var _ability: RefCounted = null
var _caster: Node = null

# ── Estado ────────────────────────────────────────────────────────────
var beam_length: float = 0.0:
	set(value):
		beam_length = value
		if is_inside_tree():
			queue_redraw()

var _direction: Vector2 = Vector2.RIGHT
var _elapsed: float = 0.0
var _stopped: bool = false
var _server_initialized: bool = false
## Objetivos golpeados al menos una vez (para el contador de on_end).
var _burned_targets: Dictionary = {}
## peer_id -> timestamp (ms) del próximo burn permitido. Permite reaplicar
## mientras el objetivo siga dentro del rayo (stacks en StatusEffectService).
var _burn_next_ms: Dictionary = {}
## Intervalo entre reaplicaciones de burn. Lo asigna LaserBurn vía setup_laser.
var burn_reapply_interval: float = 1.0

@onready var _detector: Area2D = get_node_or_null("HurtboxDetector")
@onready var _collision_shape: CollisionShape2D = get_node_or_null("HurtboxDetector/DetectShape")


func _ready() -> void:
	# En clientes el rayo es solo visual: no tiene attacker_node ni callbacks
	# (no se replican). Además, una réplica puede ejecutar _ready antes de que
	# el MultiplayerSynchronizer aplique position/beam_length, así que no hay
	# que asumir que "is_server()" basta para inicializar lógica de daño.
	var has_caster: bool = is_instance_valid(attacker_node)
	var has_caster_id: bool = attacker_id > 0
	var has_callbacks: bool = on_hit_callback.is_valid() or on_end_callback.is_valid()
	var server_logic: bool = multiplayer.is_server() and (has_caster or has_caster_id or has_callbacks)

	if not server_logic:
		_setup_visual_only()
		return

	_initialize_server_logic()


func _initialize_server_logic() -> void:
	if _server_initialized or _stopped or is_queued_for_deletion():
		return
	if not _recover_caster():
		push_warning("[FleetwayLaser] Sin attacker_node/attacker_id válidos; rayo cancelado.")
		_finish("caster_lost")
		return

	_server_initialized = true
	set_multiplayer_authority(1)
	_ensure_collision_shape()
	if _detector:
		_detector.monitoring = true
		_detector.monitorable = false
		if not _detector.area_entered.is_connected(_on_area_entered):
			_detector.area_entered.connect(_on_area_entered)
	set_physics_process(true)
	_update_from_caster(0.0)


## Llamado por LaserBurn tras crear el rayo, para asegurar que el caster quede
## asignado aunque la escena haya entrado al árbol antes de configurarse.
func server_initialize() -> void:
	if multiplayer.is_server():
		_initialize_server_logic()


func _setup_visual_only() -> void:
	if _detector:
		_detector.monitoring = false
		_detector.monitorable = false
	set_physics_process(false)
	queue_redraw()


func set_direction(dir: Vector2) -> void:
	if dir.length_squared() > 0.0:
		_direction = dir.normalized()
		rotation = _direction.angle()


## Llamado por LaserBurn tras crear el rayo. Guarda una referencia FUERTE a la
## habilidad (imprescindible: es un RefCounted y el Router no la retiene) y al
## caster, siguiendo el contrato de los hitboxes custom del proyecto.
func setup_laser(ability: RefCounted, caster: Node, dir: Vector2,
		reapply_interval: float = 1.0) -> void:
	_ability = ability
	_caster = caster
	burn_reapply_interval = maxf(reapply_interval, 0.0)
	if dir.length_squared() > 0.0:
		_direction = dir.normalized()


## Corta el rayo inmediatamente (fin de canalización, cancelación o muerte).
func stop_beam(_reason: String = "end") -> void:
	if _stopped:
		return
	_stopped = true
	set_physics_process(false)
	queue_free()


func _physics_process(delta: float) -> void:
	if _stopped:
		return

	_elapsed += delta
	if lifetime > 0.0 and _elapsed >= lifetime:
		_finish("timeout")
		return

	if not _recover_caster():
		_finish("caster_lost")
		return

	_update_from_caster(delta)
	_refresh_burn_targets()


func _recover_caster() -> bool:
	if is_instance_valid(attacker_node):
		return true
	if is_instance_valid(_caster):
		attacker_node = _caster
		return true
	if attacker_id > 0:
		var player = PlayerRegistry.get_player(attacker_id)
		if is_instance_valid(player):
			attacker_node = player
			print("[FleetwayLaser] attacker_node recuperado desde PlayerRegistry | peer: ", attacker_id)
			return true
	return false


func _update_from_caster(delta: float) -> void:
	var origin: Vector2 = _get_eye_origin()
	global_position = origin

	var aim: Dictionary = _resolve_aim(origin)
	var aim_dir: Vector2 = aim.get("direction", _direction)
	if aim_dir.length_squared() > 0.0:
		_direction = aim_dir
	rotation = _direction.angle()

	var target_length: float = float(aim.get("length", 0.0))
	if target_length > beam_length:
		beam_length = move_toward(beam_length, target_length, EXTEND_SPEED * delta)
	else:
		# Al acercar el cursor el rayo se recoge rápido para no pasarse del punto.
		beam_length = move_toward(beam_length, target_length, RETRACT_SPEED * delta)

	_update_collision_shape(beam_length)


func _resolve_aim(origin: Vector2) -> Dictionary:
	if not is_instance_valid(attacker_node):
		return {"direction": _direction, "length": 0.0}

	var max_range: float = hitbox_max_range if hitbox_max_range > 0.0 else DEFAULT_RANGE
	var aim_dir: Vector2 = _get_aim_direction()
	var aim_distance: float = minf(_get_aim_distance(), max_range)

	# Punto apuntado real (cursor/mando) y vector desde los ojos hasta él.
	# El rango se mide desde el centro del jugador para que, si el cursor está
	# dentro de rango, la punta caiga exactamente sobre el mouse.
	var player_pos: Vector2 = attacker_node.global_position
	var aim_point: Vector2 = player_pos + aim_dir * aim_distance
	var to_target: Vector2 = aim_point - origin
	if to_target.length_squared() < 0.25:
		to_target = aim_dir * max_range

	var direction: Vector2 = to_target.normalized()
	var wanted_length: float = to_target.length()
	var final_length: float = minf(wanted_length, _cast_length(origin, direction, wanted_length))
	return {"direction": direction, "length": final_length}


func _get_aim_direction() -> Vector2:
	if is_instance_valid(attacker_node):
		var latest = attacker_node.get("_latest_aim_dir")
		if latest is Vector2 and latest.length_squared() > 0.0:
			return latest.normalized()
		var facing = attacker_node.get("facing_right")
		if facing is bool:
			return Vector2.RIGHT if facing else Vector2.LEFT
	return _direction


func _get_aim_distance() -> float:
	if not is_instance_valid(attacker_node):
		return DEFAULT_AIM_DISTANCE
	var value = attacker_node.get("_latest_aim_distance")
	if value is float:
		return maxf(value, 0.0)
	if value is int:
		return maxf(float(value), 0.0)
	return DEFAULT_AIM_DISTANCE


## Origen visual: los ojos del sprite, escalados por CharacterData.sprite_scale.
func _get_eye_origin() -> Vector2:
	if not is_instance_valid(attacker_node):
		return global_position
	var player_pos: Vector2 = attacker_node.global_position
	# Escala real del sprite (incluye sprite_scale aplicado por Player).
	var sprite_scale: float = 1.0
	var sprite := attacker_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite and sprite.scale.x != 0.0:
		sprite_scale = absf(sprite.scale.x)
	elif attacker_node.character_data:
		var scale_value = attacker_node.character_data.get("sprite_scale")
		if scale_value is float and scale_value > 0.0:
			sprite_scale = scale_value

	var facing_right: bool = true
	var facing_value = attacker_node.get("facing_right")
	if facing_value is bool:
		facing_right = facing_value

	var offset: Vector2 = eye_offset_px * sprite_scale + eye_world_offset
	if not facing_right:
		offset.x = -offset.x
	return player_pos + offset


func _cast_length(origin: Vector2, direction: Vector2, max_range: float) -> float:
	if not detect_walls:
		return max_range

	var query := PhysicsRayQueryParameters2D.create(
			origin, origin + direction * max_range, 1)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var result: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return max_range

	var hit_pos: Vector2 = result.get("position", origin)
	return clampf(origin.distance_to(hit_pos) - WALL_MARGIN, 0.0, max_range)


func _ensure_collision_shape() -> void:
	if not _collision_shape:
		return
	var rect := RectangleShape2D.new()
	rect.size = Vector2(maxf(beam_length, 1.0), HIT_HEIGHT)
	_collision_shape.shape = rect


func _update_collision_shape(length: float) -> void:
	if not _collision_shape:
		return
	var rect := _collision_shape.shape as RectangleShape2D
	if not rect:
		_ensure_collision_shape()
		rect = _collision_shape.shape as RectangleShape2D
	if not rect:
		return
	rect.size = Vector2(maxf(length, 1.0), HIT_HEIGHT)
	_collision_shape.position = Vector2(length * 0.5, 0.0)


func _on_area_entered(area: Area2D) -> void:
	if _stopped or not multiplayer.is_server():
		return
	if not area.is_in_group(GroupNames.HURTBOX):
		return

	var target: Node = area.get_parent()
	if not target or not target.is_in_group(GroupNames.PLAYERS):
		return

	var target_id: int = target.get_multiplayer_authority()
	if target_id == attacker_id:
		return
	if not _passes_team_filter(target):
		return
	# Sin reaplicación: un solo burn por objetivo y rayo.
	if burn_reapply_interval <= 0.0 and _burned_targets.has(target_id):
		return
	_try_apply_burn(target, target_id)


## Reaplica burn a los objetivos que sigan dentro del rayo. StatusEffectService
## acumula stacks y refresca la duración; aquí solo se controla la cadencia.
func _refresh_burn_targets() -> void:
	if _stopped or not multiplayer.is_server():
		return
	if burn_reapply_interval <= 0.0 or not _detector:
		return

	for area in _detector.get_overlapping_areas():
		if not area.is_in_group(GroupNames.HURTBOX):
			continue
		var target: Node = area.get_parent()
		if not target or not target.is_in_group(GroupNames.PLAYERS):
			continue
		var target_id: int = target.get_multiplayer_authority()
		if target_id == attacker_id:
			continue
		if not _passes_team_filter(target):
			continue
		_try_apply_burn(target, target_id)


## Aplica burn si ha pasado burn_reapply_interval desde la última vez.
## Devuelve true si se aplicó.
func _try_apply_burn(target: Node, target_id: int) -> bool:
	var now := Time.get_ticks_msec()
	if now < int(_burn_next_ms.get(target_id, 0)):
		return false
	_burn_next_ms[target_id] = now + int(burn_reapply_interval * 1000.0)
	_burned_targets[target_id] = true
	if on_hit_callback.is_valid():
		on_hit_callback.call(target)
	return true


func _passes_team_filter(target: Node) -> bool:
	if team_filter == "all":
		return true
	var attacker_team: String = ""
	if is_instance_valid(attacker_node) and attacker_node.character_data:
		attacker_team = attacker_node.character_data.team
	var target_team: String = target.character_data.team if target.character_data else ""
	if team_filter == "enemy":
		return target_team != attacker_team
	if team_filter == "ally":
		return target_team == attacker_team
	return true


func _finish(reason: String) -> void:
	if _stopped:
		return
	_stopped = true
	set_physics_process(false)
	if on_end_callback.is_valid():
		on_end_callback.call(_burned_targets.size(), reason)
	queue_free()


func _draw() -> void:
	if beam_length <= 1.0:
		return

	var x: float = 0.0
	while x + BODY_SEGMENT_WIDTH <= beam_length + 0.01:
		draw_texture_rect(
				BODY_TEXTURE,
				Rect2(x, -BODY_HEIGHT * 0.5, BODY_SEGMENT_WIDTH, BODY_HEIGHT),
				false)
		x += BODY_SEGMENT_WIDTH

	# Último tramo parcial: se recorta la textura manteniendo la escala 4x.
	var remaining: float = beam_length - x
	if remaining > 0.5:
		var source_width: float = minf(remaining / TEXTURE_SCALE, TEXTURE_SEGMENT_WIDTH)
		draw_texture_rect_region(
				BODY_TEXTURE,
				Rect2(x, -BODY_HEIGHT * 0.5, remaining, BODY_HEIGHT),
				Rect2(0.0, 0.0, source_width, TEXTURE_SEGMENT_HEIGHT),
				Color.WHITE,
				false,
				false)

	# Punta en el punto apuntado (el rect termina exactamente en beam_length).
	var tip_half: float = TIP_DRAW_SIZE * 0.5
	draw_texture_rect(
			TIP_TEXTURE,
			Rect2(beam_length - TIP_DRAW_SIZE, -tip_half, TIP_DRAW_SIZE, TIP_DRAW_SIZE),
			false)
