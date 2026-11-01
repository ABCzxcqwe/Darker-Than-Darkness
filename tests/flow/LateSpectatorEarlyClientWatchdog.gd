# res://tests/flow/LateSpectatorEarlyClientWatchdog.gd
# Elige personaje cuando el host abre la selección y luego se queda conectado
# sin intervenir (la partida la mantiene viva el host).
extends Node

const IDLE_TIMEOUT := 70.0


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	if not await _wait_until(func() -> bool:
		return LobbyManager.players.size() >= 2 and _scene_name() == "Session", 20.0):
		_fail("no llegó al hub")
		return
	print("[EarlyClient] en el hub")

	if not await _wait_until(func() -> bool:
		return LobbyManager.current_phase == LobbyManager.GamePhase.CHARACTER_SELECT, 25.0):
		_fail("no entró a CHARACTER_SELECT")
		return

	var my_id := multiplayer.get_unique_id()
	var role := String(LobbyManager.players.get(my_id, {}).get("assigned_role", "survivor"))
	var fallback := CharacterRegistry.get_fallback(role)
	if fallback == null:
		_fail("sin fallback para el rol '%s'" % role)
		return
	LobbyManager.select_character_in_screen(fallback.id)
	print("[EarlyClient] personaje seleccionado")

	# Quedarse conectado mientras el host mantiene la partida.
	# Además empuja inputs con seq muy alto para que el servidor mueva a este
	# jugador (nodo de un cliente remoto), y así comprobar si su posición se
	# replica a un espectador tardío.
	var elapsed := 0.0
	var log_accum := 0.0
	var seq := 1000000
	var dir := Vector2.RIGHT
	var flip := 0.0
	while elapsed < IDLE_TIMEOUT:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		elapsed += dt
		log_accum += dt
		flip += dt
		if flip >= 2.0:
			flip = 0.0
			dir = -dir
		var mine := _my_node()
		if mine:
			seq += 1
			mine.rpc_id(1, "_submit_input", seq, dir, false)
		if log_accum >= 2.0:
			log_accum = 0.0
			var p := _host_node()
			if p:
				print("[EarlyClient] t=%.1f host net=%s" % [elapsed, str(p.net_position)])
			if mine:
				print("[EarlyClient] t=%.1f yo net=%s pos=%s" % [
					elapsed, str(mine.net_position), str(mine.global_position)
				])
	print("[EarlyClient] fin")
	get_tree().quit(0)


func _my_node() -> Node:
	var world := _world()
	if world == null:
		return null
	return world.get_node_or_null(str(multiplayer.get_unique_id()))


func _world() -> Node:
	if MatchCoordinator.current_game_manager == null \
			or not is_instance_valid(MatchCoordinator.current_game_manager):
		return null
	if not MatchCoordinator.current_game_manager.has_method("get_world_instance"):
		return null
	return MatchCoordinator.current_game_manager.get_world_instance()


func _host_node() -> Node:
	var world := _world()
	if world == null:
		return null
	return world.get_node_or_null("1")


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
	push_error("[EarlyClient] FAIL: " + message)
	get_tree().quit(1)
