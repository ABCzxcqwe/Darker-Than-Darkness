# res://tests/flow/LateSpectatorHostWatchdog.gd
# Arranca la partida y la mantiene viva moviendo al host para que el
# Synchronizer de posición tenga delta continuo que replicar.
extends Node

## Cuánto se mantiene la partida en curso (el espectador tardío se conecta
## ~12 s después de que arranque este proceso).
const MATCH_SECONDS := 50.0
const MOVE_SPEED := 140.0


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	if not await _wait_until(func() -> bool:
		return LobbyManager.players.size() >= 2, 20.0):
		_fail("el cliente temprano no se conectó")
		return
	if not await _wait_until(func() -> bool:
		return _scene_name() == "Session", 8.0):
		_fail("el host no está en Session")
		return
	print("[LateHost] 2 jugadores en el hub")

	await get_tree().create_timer(1.5).timeout
	LobbyManager.host_start_character_selection()
	if not await _wait_until(func() -> bool:
		return LobbyManager.current_phase == LobbyManager.GamePhase.CHARACTER_SELECT, 8.0):
		_fail("no entró a CHARACTER_SELECT")
		return

	# Esperar al espectador tardío: se conecta DURANTE la selección de personaje,
	# es decir, antes de que exista el World en el servidor.
	print("[LateHost] esperando espectador pre-partida...")
	if not await _wait_until(func() -> bool:
		return LobbyManager.players.size() >= 3, 25.0):
		_fail("el espectador tardío no se conectó durante CHARACTER_SELECT")
		return
	print("[LateHost] espectador conectado: players=", LobbyManager.players.size())

	var my_id := multiplayer.get_unique_id()
	var role := String(LobbyManager.players.get(my_id, {}).get("assigned_role", "survivor"))
	var fallback := CharacterRegistry.get_fallback(role)
	if fallback == null:
		_fail("sin fallback para el rol '%s'" % role)
		return
	LobbyManager.select_character_in_screen(fallback.id)

	if not await _wait_until(_all_selected, 10.0):
		_fail("no llegaron todas las selecciones")
		return

	MatchCoordinator.stop_character_select_timer()
	MatchCoordinator.host_launch_game()
	if not await _wait_until(func() -> bool:
		return LobbyManager.current_phase == LobbyManager.GamePhase.PLAYING, 20.0):
		_fail("la partida no arrancó")
		return
	print("[LateHost] partida en curso")

	# Mantener la partida y mover al host. El movimiento se hace sobre
	# global_position a propósito: así el único canal que puede replicarlo es el
	# Synchronizer de posición (no hay RPC de teleport de por medio).
	var elapsed := 0.0
	var dir := Vector2.RIGHT
	var flip := 0.0
	var log_accum := 0.0
	while elapsed < MATCH_SECONDS:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		elapsed += dt
		flip += dt
		log_accum += dt
		if flip >= 2.0:
			flip = 0.0
			dir = -dir
		var p := _host_player()
		if p and is_instance_valid(p):
			p.global_position += dir * MOVE_SPEED * dt
			if log_accum >= 2.0:
				log_accum = 0.0
				print("[LateHost] t=%.1f pos=%s net=%s" % [
					elapsed, str(p.global_position), str(p.net_position)
				])
		elif log_accum >= 2.0:
			log_accum = 0.0
			print("[LateHost] t=%.1f SIN NODO DE HOST" % elapsed)

	print("[LateHost] fin")
	get_tree().quit(0)


func _host_player() -> Node:
	if MatchCoordinator.current_game_manager == null \
			or not is_instance_valid(MatchCoordinator.current_game_manager):
		return null
	if not MatchCoordinator.current_game_manager.has_method("get_world_instance"):
		return null
	var world: Node = MatchCoordinator.current_game_manager.get_world_instance()
	if world == null:
		return null
	return world.get_node_or_null(str(multiplayer.get_unique_id()))


func _all_selected() -> bool:
	for pid in LobbyManager.players:
		if LobbyManager.is_spectator(pid):
			continue
		if int(LobbyManager.players[pid].get("character_id", -1)) == -1:
			return false
	return true


func _scene_name() -> String:
	var scene := get_tree().current_scene
	return scene.name if scene else ""


func _wait_until(condition: Callable, timeout: float) -> bool:
	var elapsed := 0.0
	while not condition.call():
		if elapsed >= timeout:
			return false
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return true


func _fail(message: String) -> void:
	push_error("[LateHost] FAIL: " + message)
	get_tree().quit(1)
