# res://tests/flow/FlowHostWatchdog.gd
extends Node


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	if not await _wait_until(func() -> bool:
		return LobbyManager.players.size() >= 2, 12.0):
		_fail("el cliente no se conectó")
		return

	if not await _wait_until(func() -> bool:
		return _scene_name() == "Session", 5.0):
		_fail("el host no está en Session")
		return
	print("[FlowHost] 2 jugadores en el hub")

	# Dar tiempo a que el cliente cargue su Session y vea el hub antes de iniciar.
	await get_tree().create_timer(2.0).timeout

	LobbyManager.host_start_character_selection()
	if not await _wait_until(func() -> bool:
		return LobbyManager.current_phase == LobbyManager.GamePhase.CHARACTER_SELECT, 5.0):
		_fail("no entró a CHARACTER_SELECT")
		return
	if not await _wait_until(func() -> bool:
		return _scene_name() == "Session" and current_scene_has_character_overlay(), 5.0):
		_fail("no se abrió el overlay de CharacterSelect")
		return

	var my_id := multiplayer.get_unique_id()
	var role := String(LobbyManager.players.get(my_id, {}).get("assigned_role", "survivor"))
	var fallback := CharacterRegistry.get_fallback(role)
	if fallback == null:
		_fail("sin fallback para el rol '%s'" % role)
		return
	LobbyManager.select_character_in_screen(fallback.id)

	if not await _wait_until(Callable(self, "_all_selected"), 6.0):
		_fail("no llegaron todas las selecciones")
		return

	MatchCoordinator.stop_character_select_timer()
	MatchCoordinator.host_launch_game()
	if not await _wait_until(func() -> bool:
		return LobbyManager.current_phase == LobbyManager.GamePhase.PLAYING, 12.0):
		_fail("la partida no arrancó")
		return
	if not await _wait_until(func() -> bool:
		return GameServiceLocator.game_state != null and GameServiceLocator.game_state.is_in_game(), 12.0):
		_fail("GameStateService no entró en juego")
		return
	print("[FlowHost] partida en curso")

	await get_tree().create_timer(1.0).timeout
	var gs = GameServiceLocator.game_state
	if gs:
		gs.transition_to_ended("killer_elimination")
	if not await _wait_until(func() -> bool:
		return LobbyManager.current_phase == LobbyManager.GamePhase.ENDED, 10.0):
		_fail("la partida no terminó")
		return
	print("[FlowHost] partida terminada")

	if not await _wait_until(func() -> bool:
		return LobbyManager.current_phase == LobbyManager.GamePhase.LOBBY and _scene_name() == "Session", 12.0):
		_fail("no volvió al hub")
		return

	var session := get_tree().current_scene
	var actors := session.get_node_or_null("Actors")
	var avatars := actors.get_child_count() if actors else 0
	print("[FlowHost] hub final players=%d avatars=%d" % [LobbyManager.players.size(), avatars])
	if LobbyManager.players.size() < 2 or avatars < 2:
		_fail("el hub no recreó a los 2 jugadores")
		return

	print("[FlowHost] OK")
	# Dar margen al cliente para observar el LOBBY antes de cerrar el servidor.
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)


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


func current_scene_has_character_overlay() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	return scene.find_child("CharacterSelectOverlay", true, false) != null


func _wait_until(condition: Callable, timeout: float) -> bool:
	var elapsed := 0.0
	while not condition.call():
		if elapsed >= timeout:
			return false
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return true


func _fail(message: String) -> void:
	push_error("[FlowHost] " + message)
	get_tree().quit(1)
