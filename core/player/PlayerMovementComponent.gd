class_name PlayerMovementComponent
extends Node

var player: CharacterBody2D = null
var speed: float = 200
var _is_sprinting: bool = false
var _last_aim_sync_time: int = 0

const WALK_SPEED_THRESHOLD: float = 650.0
const IDLE_MOVE_THRESHOLD: float = 0.1

## Interpolacion de remotos hacia `net_position`.
const INTERP_SNAP_DISTANCE: float = 200.0
const INTERP_SPEED: float = 15.0

## Reconciliacion (Fase 2).
const RECONCILE_THRESHOLD: float = 10.0
const MAX_INPUT_HISTORY: int = 120
const RECONCILE_SEND_INTERVAL: float = 0.05

var _client_input_seq: int = 0
var _input_history: Array = []
var _reconcile_accum: float = 0.0


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


## El dueño del nodo simula localmente (prediccion/visual) y ADEMAS el servidor
## simula autoritativamente usando el input recibido por red (_submit_input).
## El dueño no recibe su propia posicion autoritativa, asi no hay rubber-banding.
## Los demas peers ven la posicion del servidor.
func _physics_process(delta: float) -> void:
	if not player: return
	if not player.multiplayer.multiplayer_peer: return

	if player.is_multiplayer_authority():
		_owner_process(delta)
	elif player.multiplayer.is_server():
		_server_process(delta)
	else:
		_remote_process(delta)


## Remotos: interpolan hacia la posicion autoritativa que manda el servidor.
func _remote_process(delta: float) -> void:
	var target: Vector2 = player.net_position
	if player.global_position.distance_to(target) > INTERP_SNAP_DISTANCE:
		player.global_position = target
	else:
		player.global_position = player.global_position.lerp(
				target, clampf(delta * INTERP_SPEED, 0.0, 1.0))


## 0 = idle, 1 = walk, 2 = run (a partir de la velocidad actual).
func _compute_move_state() -> int:
	var vel_len: float = player.velocity.length()
	if vel_len <= IDLE_MOVE_THRESHOLD:
		return 0
	return 2 if vel_len > WALK_SPEED_THRESHOLD else 1


## Simulacion del dueño: input local en vivo + animacion/facing (se replican con
## SynchronizerAnim). Es la que da respuesta inmediata al jugador local.
func _owner_process(_delta: float) -> void:
	var blocked := false
	if player.interaction.is_spectator or player.health_state == "dead":
		blocked = true
	elif player.has_method("is_pause_menu_open") and player.is_pause_menu_open():
		blocked = true

	if blocked:
		player.velocity = Vector2.ZERO
		_force_stop_sprint()
		_record_and_send_input(Vector2.ZERO, false)
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

	var used_move := Vector2.ZERO
	var used_sprint := false

	if player.state == Player.AnimState.IDLE:
		var input_dir: Vector2 = _get_move_vector()

		var want_sprint = Input.is_action_pressed("run") and input_dir.length() > IDLE_MOVE_THRESHOLD
		var stam_svc = GameServiceLocator.stamina
		var status_svc = GameServiceLocator.status_effect
		var pid = player.get_multiplayer_authority()
		var sprint_blocked = status_svc and (status_svc.is_sprint_disabled(pid) or status_svc.is_rooted(pid) or status_svc.is_stunned(pid))
		var can_sprint = want_sprint and stam_svc and stam_svc.has_stamina(pid) and not sprint_blocked

		_apply_sprinting(can_sprint)

		var sprint_mult = 1.5 if can_sprint else 1.0
		player.velocity = input_dir * speed * sprint_mult
		player.move_and_slide()

		if player.multiplayer.is_server():
			player.move_state = _compute_move_state()

		used_move = input_dir
		used_sprint = can_sprint

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
		_force_stop_sprint()

	if player.health_state == "alive":
		if player.state == Player.AnimState.ABILITY:
			player.animated_sprite.speed_scale = 1.0
		else:
			var vel_len = player.velocity.length()
			var is_moving = vel_len > IDLE_MOVE_THRESHOLD
			player.animated_sprite.speed_scale = clamp(vel_len / speed, 0.5, 2.0) if is_moving and speed > 0 else 1.0

	_record_and_send_input(used_move, used_sprint)


## Guarda el input aplicado (con la posicion resultante) y lo manda al servidor.
## El historial permite el replay al recibir el estado autoritativo (reconcile).
func _record_and_send_input(move: Vector2, sprint: bool) -> void:
	_client_input_seq += 1
	_input_history.append({
		"seq": _client_input_seq,
		"move": move,
		"sprint": sprint,
		"pos": player.global_position,
	})
	while _input_history.size() > MAX_INPUT_HISTORY:
		_input_history.pop_front()
	# El host ya es autoritativo localmente: no hace falta devolverse el input.
	if not player.multiplayer.is_server():
		player.rpc_id(1, "_submit_input", _client_input_seq, move, sprint)


## Reconciliacion: compara la prediccion local con el estado del servidor para el
## ultimo input confirmado. Si hay divergencia, snap + replay de los pendientes.
func reconcile(server_pos: Vector2, ack_seq: int) -> void:
	var idx := -1
	for i in range(_input_history.size()):
		if _input_history[i]["seq"] == ack_seq:
			idx = i
			break
	if idx == -1:
		return  # todavia no tenemos ese input en el historial

	var predicted: Vector2 = _input_history[idx]["pos"]
	var error := predicted.distance_to(server_pos)
	var pending: Array = _input_history.slice(idx + 1)
	_input_history = pending

	if error <= RECONCILE_THRESHOLD:
		return

	player.global_position = server_pos
	for entry in pending:
		_simulate(entry["move"], entry["sprint"])
		entry["pos"] = player.global_position


func _simulate(move: Vector2, sprint: bool) -> void:
	var input_dir := move
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	var mult := 1.5 if sprint else 1.0
	player.velocity = input_dir * speed * mult
	player.move_and_slide()


## Simulacion autoritativa del servidor. No toca animacion/facing (los maneja el
## dueño); solo resuelve fisica y estamina a partir del input recibido.
func _server_process(_delta: float) -> void:
	if player.interaction.is_spectator:
		_force_stop_sprint()
		player.velocity = Vector2.ZERO
		return

	if player.health_state == "dead":
		_force_stop_sprint()
		player.velocity = Vector2.ZERO
		return

	if player.has_method("is_pause_menu_open") and player.is_pause_menu_open():
		player.velocity = Vector2.ZERO
		_force_stop_sprint()
		return

	if player.state == Player.AnimState.EMOTE:
		if player.net_move_input.length() > IDLE_MOVE_THRESHOLD:
			player.cancel_emote()
			player.state = Player.AnimState.IDLE

	if player.state == Player.AnimState.IDLE:
		var input_dir: Vector2 = player.net_move_input
		# Anti speed-hack: el cliente solo aporta direccion, nunca magnitud.
		if input_dir.length() > 1.0:
			input_dir = input_dir.normalized()
		var want_sprint: bool = player.net_sprint and input_dir.length() > IDLE_MOVE_THRESHOLD
		var stam_svc = GameServiceLocator.stamina
		var status_svc = GameServiceLocator.status_effect
		var pid = player.get_multiplayer_authority()
		var sprint_blocked = status_svc and (status_svc.is_sprint_disabled(pid) or status_svc.is_rooted(pid) or status_svc.is_stunned(pid))
		var can_sprint = want_sprint and stam_svc and stam_svc.has_stamina(pid) and not sprint_blocked

		_apply_sprinting(can_sprint)

		var sprint_mult = 1.5 if can_sprint else 1.0
		player.velocity = input_dir * speed * sprint_mult
		player.move_and_slide()
		player.move_state = _compute_move_state()
	else:
		player.velocity = Vector2.ZERO
		_force_stop_sprint()
	# Manda el estado autoritativo al dueño (throttleado) para que reconcilie.
	_reconcile_accum += get_physics_process_delta_time()
	if _reconcile_accum >= RECONCILE_SEND_INTERVAL:
		_reconcile_accum = 0.0
		var owner_peer := player.get_multiplayer_authority()
		player.rpc_id(owner_peer, "_reconcile_state", player.global_position, player.net_last_input_seq)


func _apply_sprinting(value: bool) -> void:
	if value == _is_sprinting:
		return
	_is_sprinting = value
	# El servidor es quien resuelve la estamina a partir del input autoritativo
	# (net_sprint). Los clientes ya no piden sprint por RPC para evitar doble fuente.
	if player.multiplayer.is_server():
		GameServiceLocator.stamina.set_sprinting(player.get_multiplayer_authority(), value)


func _force_stop_sprint() -> void:
	_apply_sprinting(false)


func update_facing_and_flip(dir: Vector2) -> void:
	if abs(dir.x) > IDLE_MOVE_THRESHOLD:
		var new_right: bool = dir.x > 0
		var changed: bool = player.facing_right != new_right
		player.facing_right = new_right
		player.animated_sprite.flip_h = not new_right
		player.facing = Vector2.RIGHT if new_right else Vector2.LEFT
		# El dueño avisa el cambio de facing al servidor para que lo replique.
		if changed and not player.multiplayer.is_server():
			player.rpc_id(1, "_submit_facing", new_right)


func _get_move_vector() -> Vector2:
	if player and player.input_component:
		return player.input_component.get_move_vector()
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")
