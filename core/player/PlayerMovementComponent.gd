class_name PlayerMovementComponent
extends Node
## Movimiento autoritativo del jugador con rollback de netfox.
##
## netfox simula `_rollback_tick` en servidor y clientes. El Player pertenece al
## servidor (peer 1) y el input lo aporta el nodo NetInput del dueño.
##
## La animación, el apuntado y el facing NO se simulan en rollback: se resuelven
## en `_process` (dueño) o en `Player._apply_networked_anim` (remotos).

const WALK_SPEED_THRESHOLD: float = 650.0
const IDLE_MOVE_THRESHOLD: float = 0.1
const AIM_SYNC_INTERVAL_MS: int = 100
const AIM_SYNC_INTERVAL_FASE2_MS: int = 33

var player: Player = null
var speed: float = 200
var _is_sprinting := false
var _last_aim_sync_time: int = 0


func initialize(body: Player) -> void:
	player = body


func is_sprinting() -> bool:
	return _is_sprinting


func set_speed(value: float) -> void:
	speed = value


func stop_movement() -> void:
	if player:
		player.velocity = Vector2.ZERO


func restore_speed_from_data() -> void:
	if player and player.character_data:
		speed = player.character_data.speed


# ── Simulación rollback ────────────────────────────────────────────────

func _rollback_tick(_delta: float, _tick: int, is_fresh: bool) -> void:
	if player == null or player.owner_peer_id <= 0:
		return
	if not player.multiplayer.multiplayer_peer:
		return

	# Posición forzada por habilidades (teleport, agarre de King): se aplica
	# dentro del tick para que netfox la grabe; sin esto el rollback reaplica
	# el estado viejo durante la resimulación.
	if player._apply_forced_position_tick(_tick):
		return

	var move := Vector2.ZERO
	var want_sprint := false
	var net := player.net_input
	if net != null:
		move = net.move
		want_sprint = net.sprint
	else:
		move = player.net_move_input
		want_sprint = player.net_sprint

	# Espejo para el resto del gameplay/UI que todavía lee estas propiedades.
	player.net_move_input = move
	player.net_sprint = want_sprint

	# Facing determinista: el input de apuntado viaja por netfox, así el
	# servidor puede reproducirlo durante una resimulación.
	if net != null and absf(net.aim_dir.x) > IDLE_MOVE_THRESHOLD:
		player.facing_right = net.aim_dir.x > 0.0
		player.facing = Vector2.RIGHT if player.facing_right else Vector2.LEFT

	# Dirección cardinal del último movimiento: se replica como estado para que
	# los clientes remotos elijan la animación direccional correcta.
	if move.length() > IDLE_MOVE_THRESHOLD:
		player.last_move_dir = _cardinal_direction(move)

	if player.multiplayer.is_server():
		_update_server_mobility()

	if _is_blocked():
		player.velocity = Vector2.ZERO
		player.move_state = 0
		player.move_facing_down = false
		_is_sprinting = false
		if player.multiplayer.is_server() and is_fresh:
			_report_sprinting(false)
		return

	if not _can_move_now():
		player.velocity = Vector2.ZERO
		player.move_state = 0
		player.move_facing_down = false
		_is_sprinting = false
		if player.multiplayer.is_server() and is_fresh:
			_report_sprinting(false)
		return

	var dir := move
	if dir.length() > 1.0:
		dir = dir.normalized()

	var sprinting := want_sprint and player.sprint_allowed and dir.length() > IDLE_MOVE_THRESHOLD
	if player.fase2_active:
		sprinting = false
	var mult := 1.5 if sprinting else 1.0
	var fase2_mult: float = player.fase2_move_scale if player.fase2_active else 1.0

	var factor: float = 1.0
	if NetworkTime != null:
		factor = NetworkTime.physics_factor
	player.velocity = dir * speed * mult * fase2_mult * factor
	player.move_and_slide()
	if factor != 0.0:
		player.velocity /= factor

	player.move_state = _compute_move_state()
	player.move_facing_down = _is_down_input(dir)
	_is_sprinting = sprinting

	if player.multiplayer.is_server() and is_fresh:
		_report_sprinting(sprinting)


func _is_blocked() -> bool:
	if player == null:
		return true
	if player.interaction.is_spectator:
		return true
	if player.health_state != "alive":
		return true
	if player.is_local_owner() and player.has_method("is_pause_menu_open") and player.is_pause_menu_open():
		return true
	if player.movement_locked:
		return true
	return false


## El servidor resuelve los flags de movilidad y los publica como estado netfox.
func _update_server_mobility() -> void:
	var pid := player.owner_peer_id
	var allowed := true
	var locked := false

	var stam = GameServiceLocator.stamina
	if stam != null and stam.has_method("has_stamina"):
		allowed = bool(stam.has_stamina(pid))

	var status = GameServiceLocator.status_effect
	if status != null:
		if status.has_method("is_sprint_disabled"):
			allowed = allowed and not bool(status.is_sprint_disabled(pid))
		if status.has_method("is_rooted"):
			locked = locked or bool(status.is_rooted(pid))
		if status.has_method("is_stunned"):
			locked = locked or bool(status.is_stunned(pid))

	if player.fase2_active and player.fase2_move_locked:
		locked = true

	player.sprint_allowed = allowed
	player.movement_locked = locked


func _report_sprinting(sprinting: bool) -> void:
	var stam = GameServiceLocator.stamina
	if stam != null and stam.has_method("set_sprinting"):
		stam.set_sprinting(player.owner_peer_id, sprinting)


# ── Visual del dueño (no rollback) ─────────────────────────────────────

func _process(_delta: float) -> void:
	if player == null or player.owner_peer_id <= 0:
		return
	if not player.multiplayer.multiplayer_peer:
		return
	if not player.is_local_owner():
		return
	if player.interaction.is_spectator or player.health_state != "alive":
		return
	if player.is_pause_menu_open():
		return

	# Cancelar emote al moverse (el estado es local/visual, no rollback).
	if player.state == Player.AnimState.EMOTE:
		var emote_move: Vector2 = _get_move_vector()
		if emote_move.length() > IDLE_MOVE_THRESHOLD:
			player.cancel_emote()
			player.state = Player.AnimState.IDLE

	if player.state == Player.AnimState.IDLE or player.active_effects.has("free_look"):
		var aim_dir: Vector2 = player.input_component.get_aim_direction(player.global_position)
		update_facing_and_flip(aim_dir)
		if player.active_effects.has("free_look"):
			var now := Time.get_ticks_msec()
			var interval := AIM_SYNC_INTERVAL_FASE2_MS if player.fase2_active else AIM_SYNC_INTERVAL_MS
			if now - _last_aim_sync_time > interval:
				_last_aim_sync_time = now
				var aim_point: Vector2 = player.input_component.get_aim_position(
					player.global_position, 1200.0)
				var aim_distance: float = player.global_position.distance_to(aim_point)
				if player.multiplayer.is_server():
					player._sync_aim_dir(aim_dir, aim_distance)
				else:
					player.rpc_id(LobbyManager.server_peer_id, "_sync_aim_dir", aim_dir, aim_distance)

	_update_owner_animation()


func _update_owner_animation() -> void:
	if player.health_state != "alive":
		return
	if player.state == Player.AnimState.ABILITY:
		if player.fase2_active and player.animated_sprite:
			_update_fase2_animation()
		if player.animated_sprite:
			player.animated_sprite.speed_scale = 1.0
		return
	if player.state != Player.AnimState.IDLE:
		return

	var vel_len := player.velocity.length()
	var is_moving := vel_len > IDLE_MOVE_THRESHOLD
	var is_running := vel_len > WALK_SPEED_THRESHOLD
	var move_dir := _get_move_vector()
	var use_hurt := player.animation_component.should_use_hurt_sprite()
	var anim_name := player.animation_component.select_movement_anim(
		is_moving, is_running, use_hurt, move_dir)
	if anim_name != "default" and player.last_animation != anim_name:
		player.animated_sprite.play(anim_name)
		player.last_animation = anim_name
	player.animated_sprite.flip_h = not player.facing_right
	player.animated_sprite.speed_scale = clamp(vel_len / speed, 0.5, 2.0) if is_moving and speed > 0.0 else 1.0


func _update_fase2_animation() -> void:
	var vel_len: float = player.velocity.length()
	var is_moving: bool = vel_len > IDLE_MOVE_THRESHOLD
	var is_running: bool = vel_len > WALK_SPEED_THRESHOLD
	var use_hurt: bool = player.animation_component.should_use_hurt_sprite()
	var move_dir: Vector2 = _get_move_vector()
	var anim_name := ""

	if is_moving:
		anim_name = player.fase2_move_animation
		if anim_name == "" or not _has_animation(anim_name):
			anim_name = player.animation_component.select_movement_anim(is_moving, is_running, use_hurt, move_dir)
	else:
		anim_name = player.fase2_pose_animation
		if anim_name == "" or not _has_animation(anim_name):
			anim_name = player.animation_component.select_movement_anim(false, false, use_hurt, move_dir)

	if anim_name == "" or anim_name == "default" or not _has_animation(anim_name):
		return
	player.animation_component.apply_movement_anim(anim_name, is_moving)


func _has_animation(anim_name: String) -> bool:
	if not player.animated_sprite or not player.animated_sprite.sprite_frames:
		return false
	return player.animated_sprite.sprite_frames.has_animation(anim_name)


# ── Helpers ───────────────────────────────────────────────────────────

func _can_move_now() -> bool:
	if player.state == Player.AnimState.IDLE:
		return true
	if player.fase2_active and player.state == Player.AnimState.ABILITY:
		return not player.fase2_move_locked
	return false


func _compute_move_state() -> int:
	var vel_len: float = player.velocity.length()
	if vel_len <= IDLE_MOVE_THRESHOLD:
		return 0
	return 2 if vel_len > WALK_SPEED_THRESHOLD else 1


func update_facing_and_flip(dir: Vector2) -> void:
	if abs(dir.x) > IDLE_MOVE_THRESHOLD:
		var new_right: bool = dir.x > 0
		player.facing_right = new_right
		player.animated_sprite.flip_h = not new_right
		player.facing = Vector2.RIGHT if new_right else Vector2.LEFT
		# El servidor recalcula el facing desde NetInput:aim_dir en cada tick,
		# así que no hace falta un RPC adicional para replicarlo.


func _cardinal_direction(dir: Vector2) -> Vector2:
	if absf(dir.x) >= absf(dir.y):
		return Vector2.RIGHT if dir.x > 0.0 else Vector2.LEFT
	return Vector2.DOWN if dir.y > 0.0 else Vector2.UP


func _is_down_input(dir: Vector2) -> bool:
	return dir.y > IDLE_MOVE_THRESHOLD and absf(dir.y) >= absf(dir.x)


func _get_move_vector() -> Vector2:
	if player and player.input_component:
		return player.input_component.get_move_vector()
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")
