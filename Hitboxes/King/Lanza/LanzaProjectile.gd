extends CharacterBody2D

# Proyectil de la Lanza de King. La misma escena se usa para la versión
# clásica (Lanza.gd) y para la versión AIM (LanzaAim.gd). La versión AIM
# usa resolve_with_reason()/cancel_with_reason() para distinguir fallo,
# hook, agarre y cancelación.

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
const RETRACT_SPEED: float = 2200.0
const HOOK_PULL_SPEED: float = 2400.0
const RETURN_SPEED: float = 3000.0
const ARRIVE_DIST: float   = 40.0
const TILE_SIZE: float     = 96.0

const LANZA_CABEZA_TEX := preload("uid://c0s1t2np4oujg")
const HOOK_WALL_SHAPE_SIZE := Vector2(70, 70)

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
var _cancel_reason: String = ""

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
	_ensure_wall_collision()
	var detector = $HurtboxDetector
	detector.collision_mask = collision_mask
	detector.area_entered.connect(_on_area_entered)
	set_deferred("collision_mask", collision_mask | 1)
	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_timeout)


func _on_lifetime_timeout() -> void:
	if _resolved or _phase == Phase.DONE:
		return
	if _phase == Phase.EXTEND or _phase == Phase.RETURN:
		_cancel_reason = "miss_lifetime"
		_phase = Phase.RETURN


func _ensure_wall_collision() -> void:
	if has_node("BodyShape"):
		return
	var shape_node := CollisionShape2D.new()
	shape_node.name = "BodyShape"
	var rect := RectangleShape2D.new()
	rect.size = HOOK_WALL_SHAPE_SIZE
	shape_node.shape = rect
	add_child(shape_node)


func _process(_delta: float) -> void:
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _resolved or _phase == Phase.DONE:
		return
	if not multiplayer.is_server():
		return

	if _caster_is_stunned():
		if _supports_reasons():
			cancel_with_reason("stun")
		else:
			_resolve(false)
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


func _supports_reasons() -> bool:
	return is_instance_valid(_ability) and _ability.has_method("resolve_with_reason")


func _caster_is_stunned() -> bool:
	var status = GameServiceLocator.status_effect
	if status and status.has_method("is_stunned"):
		return status.is_stunned(attacker_id)
	if is_instance_valid(_caster):
		return _caster.active_effects.has("stun")
	return false


func _extend_phase(delta: float) -> void:
	if speed <= 0.0:
		_fail("miss")
		return

	var dir := _direction
	var step := speed * delta

	_travel += step
	if hitbox_max_range > 0.0 and _travel >= hitbox_max_range:
		_to_return()
		return

	if detect_walls:
		var collision := move_and_collide(dir * step)
		if collision:
			var collider := collision.get_collider()
			if collider is StaticBody2D or collider is TileMapLayer:
				global_position = collision.get_position()
				_to_hook()
				return


func _to_hook() -> void:
	_phase = Phase.HOOK


func _to_return() -> void:
	_phase = Phase.RETURN


func _return_phase(delta: float) -> void:
	if _resolved:
		return

	var king_pos: Vector2 = _caster.global_position if is_instance_valid(_caster) else origin
	global_position = global_position.move_toward(king_pos, RETURN_SPEED * delta)

	if global_position.distance_to(king_pos) < ARRIVE_DIST:
		if _cancel_reason != "":
			_resolve_with_reason(_cancel_reason)
		else:
			_fail("miss_return")


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
	var target_id: int = PlayerLifecycleManager.get_owner_peer_id(target)
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

	if is_instance_valid(_ability) and _ability.has_method("on_lance_grab"):
		_ability.on_lance_grab()


func _grab_phase(delta: float) -> void:
	if _resolved:
		return

	var king_pos: Vector2 = _caster.global_position if is_instance_valid(_caster) else origin

	global_position = global_position.move_toward(king_pos, RETRACT_SPEED * delta)

	if is_instance_valid(_grabbed):
		_grabbed.global_position = global_position
		_grabbed.rpc("_sync_server_position", global_position)

	if global_position.distance_to(king_pos) < ARRIVE_DIST:
		if _supports_reasons():
			_resolve_with_reason("grab")
		else:
			_resolve(true)


func _hook_phase(delta: float) -> void:
	if _resolved:
		return

	if not is_instance_valid(_caster):
		_fail("miss")
		return

	var king := _caster
	var np: Vector2 = king.global_position.move_toward(global_position, HOOK_PULL_SPEED * delta)
	king.global_position = np
	origin = np
	king.rpc("_sync_server_position", np)

	if np.distance_to(global_position) < ARRIVE_DIST:
		if _supports_reasons():
			_resolve_with_reason("hook")
		else:
			_resolve(true)


# ── Cancelación (solo LanzaAim) ──────────────────────────────────────

## Si está agarrando, suelta en el acto; si está en recorrido/hook, retrae
## el asta y resuelve al volver a King.
func cancel_with_reason(reason: String) -> void:
	if _resolved or _phase == Phase.DONE:
		return
	if not _supports_reasons():
		return

	var phase_tag := "travel"
	if _phase == Phase.GRAB:
		phase_tag = "grab"
	elif _phase == Phase.HOOK:
		phase_tag = "hook"

	var final_reason: String = "%s_%s" % [reason, phase_tag]

	if _phase == Phase.GRAB:
		_resolve_with_reason(final_reason)
		return

	_cancel_reason = final_reason
	_phase = Phase.RETURN


# ── Resolución ───────────────────────────────────────────────────────

## Compatibilidad con la Lanza clásica.
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

	if is_instance_valid(_ability) and _ability.has_method("resolve"):
		_ability.resolve(success)

	if on_end_callback.is_valid():
		on_end_callback.call(0)

	queue_free()


## Resolución con motivo para LanzaAim.
func _resolve_with_reason(reason: String) -> void:
	if _resolved:
		return
	_resolved = true
	_phase = Phase.DONE
	set_physics_process(false)

	var combat = GameServiceLocator.combat_mediator
	if is_instance_valid(_grabbed):
		if combat:
			combat.remove_root(_grabbed)

	if is_instance_valid(_ability) and _ability.has_method("resolve_with_reason"):
		_ability.resolve_with_reason(reason)
	elif is_instance_valid(_ability) and _ability.has_method("resolve"):
		_ability.resolve(reason.contains("grab") or reason.contains("hook"))

	if on_end_callback.is_valid():
		on_end_callback.call(0)

	queue_free()


func _fail(reason: String) -> void:
	if _supports_reasons():
		_resolve_with_reason(reason)
	else:
		_resolve(false)


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


# ── Render de la cabeza (el asta vive en LanzaShaftVisual) ───────────
func _draw() -> void:
	var o := origin - global_position
	var dist := o.length()
	if dist < 8.0:
		return
	var dir := -o.normalized()

	var head_size: Vector2 = LANZA_CABEZA_TEX.get_size()

	draw_set_transform(Vector2.ZERO, dir.angle(), Vector2.ONE)
	draw_texture_rect(LANZA_CABEZA_TEX,
		Rect2(-head_size.x * 0.5, -head_size.y * 0.5, head_size.x, head_size.y), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
