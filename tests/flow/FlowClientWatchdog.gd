# res://tests/flow/FlowClientWatchdog.gd
extends Node


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	if not await _wait_until(func() -> bool:
		return LobbyManager.players.size() >= 2 and _scene_name() == "Session", 12.0):
		_fail("no llegó al hub con 2 jugadores")
		return
	print("[FlowClient] 2 jugadores en el hub")

	if not await _wait_until(func() -> bool:
		return LobbyManager.current_phase == LobbyManager.GamePhase.CHARACTER_SELECT \
			and _scene_name() == "Session" and current_scene_has_character_overlay(), 12.0):
		_fail("no entró al overlay de CharacterSelect")
		return

	var my_id := multiplayer.get_unique_id()
	var role := String(LobbyManager.players.get(my_id, {}).get("assigned_role", "survivor"))
	var fallback := CharacterRegistry.get_fallback(role)
	if fallback == null:
		_fail("sin fallback para el rol '%s'" % role)
		return
	LobbyManager.select_character_in_screen(fallback.id)
	print("[FlowClient] personaje seleccionado")

	if not await _wait_until(func() -> bool:
		return LobbyManager.current_phase == LobbyManager.GamePhase.PLAYING \
			and GameServiceLocator.game_state != null \
			and GameServiceLocator.game_state.is_in_game(), 18.0):
		_fail("la partida no arrancó")
		return
	print("[FlowClient] partida en curso")

	if not await _wait_until(func() -> bool:
		return LobbyManager.current_phase == LobbyManager.GamePhase.ENDED, 15.0):
		_fail("la partida no terminó")
		return
	print("[FlowClient] partida terminada")

	await get_tree().create_timer(0.5).timeout
	MatchCoordinator.request_return_to_lobby()

	if not await _wait_until(func() -> bool:
		return LobbyManager.current_phase == LobbyManager.GamePhase.LOBBY and _scene_name() == "Session", 12.0):
		_fail("no volvió al hub")
		return

	var session := get_tree().current_scene
	var actors := session.get_node_or_null("Actors")
	var avatars := actors.get_child_count() if actors else 0
	print("[FlowClient] hub final players=%d avatars=%d" % [LobbyManager.players.size(), avatars])
	if LobbyManager.players.size() < 2 or avatars < 2:
		_fail("el hub no recreó a los 2 jugadores")
		return

	print("[FlowClient] OK")
	get_tree().quit(0)


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
	push_error("[FlowClient] " + message)
	get_tree().quit(1)
