class_name PlayerMovementComponent
extends Node

var player: CharacterBody2D = null
var speed: float = 200
var _is_sprinting: bool = false
var _last_aim_sync_time: int = 0

const WALK_SPEED_THRESHOLD: float = 650.0
const IDLE_MOVE_THRESHOLD: float = 0.1


func initialize(body: CharacterBody2D) -> void:
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


func _physics_process(_delta: float) -> void:
	if not player: return
	if not player.multiplayer.multiplayer_peer: return
	if not player.is_multiplayer_authority(): return

	if player.interaction.is_spectator:
		return

	if player.health_state == "dead": return

	# Menú de pausa abierto: el jugador queda parado (el mundo sigue).
	if player.has_method("is_pause_menu_open") and player.is_pause_menu_open():
		player.velocity = Vector2.ZERO
		return

	# ── Si está emotando y se mueve, cancelar emote ──
	if player.state == Player.AnimState.EMOTE:
		var emote_move: Vector2 = _get_move_vector()
		if emote_move.length() > IDLE_MOVE_THRESHOLD:
			player.cancel_emote()
			# Permitir que este frame procese el movimiento
			player.state = Player.AnimState.IDLE

	if player.state == Player.AnimState.IDLE or player.active_effects.has("free_look"):
		var aim_dir: Vector2 = player.input_component.get_aim_direction(player.global_position)
		update_facing_and_flip(aim_dir)
		if player.active_effects.has("free_look"):
			var now = Time.get_ticks_msec()
			if now - _last_aim_sync_time > 100:
				_last_aim_sync_time = now
				if player.multiplayer.is_server():
					player._sync_aim_dir(aim_dir)
				else:
					player.rpc_id(1, "_sync_aim_dir", aim_dir)

	if player.state == Player.AnimState.IDLE:
		var input_dir: Vector2 = _get_move_vector()

		var want_sprint = Input.is_action_pressed("run") and input_dir.length() > IDLE_MOVE_THRESHOLD
		var stam_svc = GameServiceLocator.stamina
		var can_sprint = want_sprint and stam_svc.has_stamina(player.get_multiplayer_authority())

		if can_sprint != _is_sprinting:
			_is_sprinting = can_sprint
			if player.multiplayer.is_server():
				GameServiceLocator.stamina.set_sprinting(player.get_multiplayer_authority(), can_sprint)
			else:
				player.rpc_id(1, "_request_sprint", can_sprint)

		var sprint_mult = 1.5 if can_sprint else 1.0
		player.velocity = input_dir * speed * sprint_mult
		player.move_and_slide()

		if player.health_state == "alive":
			var vel_len = player.velocity.length()
			var is_moving = vel_len > IDLE_MOVE_THRESHOLD
			var is_running = vel_len > WALK_SPEED_THRESHOLD
			var use_hurt = player.animation_component.should_use_hurt_sprite()
			var anim_name = player.animation_component.select_movement_anim(is_moving, is_running, use_hurt)
			if player.last_animation != anim_name:
				player.animated_sprite.play(anim_name)
				player.last_animation = anim_name
	else:
		player.velocity = Vector2.ZERO

	if player.health_state == "alive":
		if player.state == Player.AnimState.ABILITY:
			player.animated_sprite.speed_scale = 1.0
		else:
			var vel_len = player.velocity.length()
			var is_moving = vel_len > IDLE_MOVE_THRESHOLD
			player.animated_sprite.speed_scale = clamp(vel_len / speed, 0.5, 2.0) if is_moving and speed > 0 else 1.0


func update_facing_and_flip(dir: Vector2) -> void:
	if abs(dir.x) > IDLE_MOVE_THRESHOLD:
		player.facing_right = dir.x > 0
		player.animated_sprite.flip_h = not player.facing_right
		player.facing = Vector2.RIGHT if player.facing_right else Vector2.LEFT


func _get_move_vector() -> Vector2:
	if player and player.input_component:
		return player.input_component.get_move_vector()
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")
