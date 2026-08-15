extends CharacterBody2D

# ── Asignados por HitboxService antes de add_child() ──────────────────
var attacker_id:  int     = -1
var attacker_node: Node   = null
var damage:       int     = 0
var attack_type:  String  = "normal"
var hit_limit:    int     = 0
var team_filter:  String  = "enemy"
var lifetime:     float   = 30.0
var speed:        float   = 900.0
var aim_mode:     String  = "fixed"
var detect_walls: bool    = true
var impact_lifetime: float = 0.0
var hitbox_max_range: float = 1200.0

# ── Mecánica de la lanza ─────────────────────────────────────────────
var origin: Vector2 = Vector2.ZERO          # estómago del Rey (replicado)
const RETRACT_SPEED: float = 2200.0         # retracción del asta (px/s)
const HOOK_PULL_SPEED: float = 2400.0       # Rei jalado hacia la pared enganchada (px/s)
const RETURN_SPEED: float = 3000.0          # retorno al Rey al alcanzar el límite de rango (px/s)
const ARRIVE_DIST: float   = 40.0           # dist. para considerar "recogido"
const TILE_SIZE: float     = 96.0           # tamaño del segmento lanza.png

const LANZA_TEX := preload("uid://ksj6jcxhc5yk")       # lanza.png
const LANZA_CABEZA_TEX := preload("uid://c0s1t2np4oujg") # lanza_cabeza.png

enum Phase { EXTEND, GRAB, HOOK, RETURN, DONE }

var _phase: int = Phase.EXTEND
var _direction: Vector2 = Vector2.RIGHT
var _travel: float = 0.0

# Referencias del caster (solo servidor — no se replican)
var _ability: RefCounted = null
var _caster: Node = null
var _grabbed: Node = null
var _grabbed_peer: int = -1
var _resolved: bool = false

var on_hit_callback: Callable
var on_end_callback: Callable


func setup_lanza(ability: RefCounted, caster: Node, dir: Vector2) -> void:
	_ability = ability
	_caster = caster
	set_direction(dir)


func set_direction(dir: Vector2) -> void:
	_direction = dir.normalized()
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT


func _ready() -> void:
	if not multiplayer.is_server():
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		return
	set_multiplayer_authority(1)
	var detector = $HurtboxDetector
	detector.collision_mask = collision_mask
	detector.area_entered.connect(_on_area_entered)
	set_deferred("collision_mask", collision_mask | 1)  # layer 1 = mundo (paredes)


func _process(_delta: float) -> void:
	queue_redraw()


# ── Fase EXTEND: la cabeza avanza y el asta se estira ────────────────
func _physics_process(delta: float) -> void:
	if _resolved or _phase == Phase.DONE:
		return
	if not multiplayer.is_server():
		return

	match _phase:
		Phase.EXTEND:
			_extend_phase(delta)
		Phase.GRAB:
			_grab_phase(delta)
		Phase.HOOK:
			_hook_phase(delta)
		Phase.RETURN:
			_return_phase(delta)


func _extend_phase(delta: float) -> void:
	if speed <= 0.0:
		_resolve(false)
		return

	var dir := _direction
	var step := speed * delta

	# Limitar por rango máximo.
	_travel += step
	if hitbox_max_range > 0.0 and _travel >= hitbox_max_range:
		_to_return()
		return

	if detect_walls:
		var collision := move_and_collide(dir * step)
		if collision:
			var collider := collision.get_collider()
			if collider is StaticBody2D or collider is TileMapLayer:
				# La cabeza queda fijada en el punto de impacto → HOOK.
				global_position = collision.get_position()
				_to_hook()
				return


func _to_hook() -> void:
	_phase = Phase.HOOK
	if is_instance_valid(_caster):
		_pause_sync(_caster)


# ── Fase RETURN: la cabeza regresa al Rey al agotar el rango ─────────
func _to_return() -> void:
	_phase = Phase.RETURN


func _return_phase(delta: float) -> void:
	if _resolved:
		return

	var king_pos: Vector2 = _caster.global_position if is_instance_valid(_caster) else origin
	global_position = global_position.move_toward(king_pos, RETURN_SPEED * delta)

	if global_position.distance_to(king_pos) < ARRIVE_DIST:
		_resolve(false)


# ── Detección de superviviente ───────────────────────────────────────
func _on_area_entered(area: Area2D) -> void:
	if _resolved or _phase != Phase.EXTEND:
		return
	if not multiplayer.is_server():
		return
	if not area.is_in_group("hurtbox"):
		return
	var target: Node = area.get_parent()
	if not target or not target.is_in_group("players"):
		return
	var target_id: int = target.get_multiplayer_authority()
	if target_id == attacker_id:
		return
	if not _passes_team_filter(target):
		return

	_grabbed = target
	_grabbed_peer = target_id
	_phase = Phase.GRAB

	AudioManager.play_sfx_networked.rpc(SfxId.GRAB, global_position.x, global_position.y)

	var combat = GameServiceLocator.combat_mediator
	if combat and is_instance_valid(target):
		combat.apply_damage(_caster, target, damage, attack_type)
		combat.apply_root(target, 30.0)
	_pause_sync(target)


# ── Fase GRAB: la cabeza retrae y jala al superviviente hacia el Rey ──
func _grab_phase(delta: float) -> void:
	if _resolved:
		return

	var king_pos: Vector2 = _caster.global_position if is_instance_valid(_caster) else origin

	# La cabeza retrae hacia el Rey.
	global_position = global_position.move_toward(king_pos, RETRACT_SPEED * delta)

	# El superviviente viaja pegado a la punta de la lanza (llegarán juntos al Rey).
	if is_instance_valid(_grabbed):
		_grabbed.global_position = global_position
		_grabbed.rpc("_sync_server_position", global_position)

	if global_position.distance_to(king_pos) < ARRIVE_DIST:
		_resolve(true)


# ── Fase HOOK: el Rey es jalado hacia la cabeza fijada ───────────────
func _hook_phase(delta: float) -> void:
	if _resolved:
		return

	if not is_instance_valid(_caster):
		_resolve(false)
		return

	var king := _caster
	var np: Vector2 = king.global_position.move_toward(global_position, HOOK_PULL_SPEED * delta)
	king.global_position = np
	origin = np
	king.rpc("_sync_server_position", np)

	if np.distance_to(global_position) < ARRIVE_DIST:
		_resolve(true)


# ── Resolución ───────────────────────────────────────────────────────
func _resolve(success: bool) -> void:
	if _resolved:
		return
	_resolved = true
	_phase = Phase.DONE
	set_physics_process(false)

	var combat = GameServiceLocator.combat_mediator

	if is_instance_valid(_grabbed):
		if combat:
			combat.remove_root(_grabbed)
		_resume_sync(_grabbed)

	if is_instance_valid(_caster):
		_resume_sync(_caster)

	if is_instance_valid(_ability) and _ability.has_method("resolve"):
		_ability.resolve(success)

	if on_end_callback.is_valid():
		on_end_callback.call(0)

	queue_free()


# ── Helpers de red ──────────────────────────────────────────────────
func _pause_sync(node: Node) -> void:
	var sync = node.get_node_or_null("Synchronizer")
	if sync:
		sync.set_process(false)
		sync.set_physics_process(false)


func _resume_sync(node: Node) -> void:
	var sync = node.get_node_or_null("Synchronizer")
	if sync:
		sync.set_process(true)
		sync.set_physics_process(true)


func _passes_team_filter(target: Node) -> bool:
	var attacker_team := _get_attacker_team()
	var target_team: String = target.character_data.team if target.character_data else ""
	if team_filter == "enemy":
		return target_team != attacker_team
	if team_filter == "ally":
		return target_team == attacker_team
	return true


func _get_attacker_team() -> String:
	if attacker_node and attacker_node.character_data:
		return attacker_node.character_data.team
	return ""


# ── Render del asta (todos los peers) ────────────────────────────────
func _draw() -> void:
	var o := origin - global_position            # posición local del estómago
	var dist := o.length()
	if dist < 8.0:
		return
	var dir := -o.normalized()                   # de estómago → cabeza (dir del mouse)

	var seg_w: float = LANZA_TEX.get_width()
	var seg_h: float = LANZA_TEX.get_height()
	var head_size: Vector2 = LANZA_CABEZA_TEX.get_size()

	# Rotar el contexto para que el eje +X apunte hacia la punta (mouse).
	draw_set_transform(Vector2.ZERO, dir.angle(), Vector2.ONE)

	# Asta: rectángulos repetidos en línea recta hacia la cabeza.
	# Un pequeño solape garantiza tramos largos sin huecos.
	var step: float = seg_w * 0.9
	var x: float = dist - seg_w * 0.5
	while x > 0.0:
		draw_texture_rect(LANZA_TEX,
			Rect2(-x - seg_w * 0.5, -seg_h * 0.5, seg_w, seg_h), false)
		x -= step

	# Cabeza centrada en la punta, orientada con la misma dirección.
	draw_texture_rect(LANZA_CABEZA_TEX,
		Rect2(-head_size.x * 0.5, -head_size.y * 0.5, head_size.x, head_size.y), false)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
