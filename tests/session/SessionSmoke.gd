# res://tests/session/SessionSmoke.gd
# Smoke test del spike de sesión: carga el hub, entra a la partida, vuelve.
extends Node


func _ready() -> void:
	await get_tree().process_frame

	if not InputMap.has_action("world_interact"):
		push_error("[SessionSmoke] Falta la acción 'world_interact' en el InputMap")
		get_tree().quit(1)
		return

	var session_scene: PackedScene = load("res://Maps/Session.tscn")
	if session_scene == null:
		push_error("[SessionSmoke] No se pudo cargar Session.tscn")
		get_tree().quit(1)
		return

	var session := session_scene.instantiate()
	add_child(session)
	await get_tree().process_frame

	var map_container: Node = session.get_node("MatchArea/MapContainer")
	var avatar: Node2D = session._local_avatar
	var hub_board: Node2D = session.get_node("HubArea/HubBoard")
	var prompt: Label = session.get_node("UI/PromptLabel")
	var board_panel: Control = session.get_node("UI/BoardPanel")
	if avatar == null:
		push_error("[SessionSmoke] No se creó el avatar local del hub")
		get_tree().quit(1)
		return
	var hub_pos := avatar.global_position

	# Acercarse al tablero y comprobar que aparece el prompt de interacción.
	avatar.global_position = hub_board.global_position + Vector2(0, 100)
	for i in 6:
		await get_tree().physics_frame
	if not prompt.visible or not prompt.text.contains("TABLERO"):
		push_error("[SessionSmoke] No apareció el prompt del tablero")
		get_tree().quit(1)
		return

	# Simular E (world_interact) y comprobar que se abre el panel.
	var interact_event := InputEventAction.new()
	interact_event.action = "world_interact"
	interact_event.pressed = true
	avatar._unhandled_input(interact_event)
	await get_tree().process_frame
	if not board_panel.visible:
		push_error("[SessionSmoke] El tablero no abrió su panel")
		get_tree().quit(1)
		return

	# Selección de mapa desde el tablero (host local del test).
	LobbyManager.is_host = true
	LobbyManager.room_host_peer = 1
	board_panel.map_selected.emit("1")
	await get_tree().process_frame
	if LobbyManager.selected_map != "1":
		push_error("[SessionSmoke] El tablero no cambió el mapa de la sala")
		get_tree().quit(1)
		return
	var map_label: Label = board_panel.get_node("Center/Panel/Margin/VBox/MapRow/MapLabel")
	if not map_label.text.contains("Card Castle"):
		push_error("[SessionSmoke] El label del mapa no se actualizó: " + map_label.text)
		get_tree().quit(1)
		return

	board_panel.close_panel()
	await get_tree().process_frame
	if board_panel.visible:
		push_error("[SessionSmoke] El panel del tablero no se cerró")
		get_tree().quit(1)
		return

	await session._enter_match()
	await get_tree().process_frame
	await get_tree().process_frame

	if map_container.get_child_count() == 0:
		push_error("[SessionSmoke] El mapa de partida no se cargó")
		get_tree().quit(1)
		return

	if avatar.global_position.distance_to(hub_pos) < 1000.0:
		push_error("[SessionSmoke] El avatar no se teletransportó al MatchArea")
		get_tree().quit(1)
		return

	print("[SessionSmoke] Partida cargada. Avatar en ", avatar.global_position)

	session._return_to_hub()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	if avatar.global_position.distance_to(hub_pos) > 1.0:
		push_error("[SessionSmoke] El avatar no volvió al spawn del hub")
		get_tree().quit(1)
		return

	if map_container.get_child_count() != 0:
		push_error("[SessionSmoke] El mapa de partida no se liberó")
		get_tree().quit(1)
		return

	print("[SessionSmoke] OK: hub -> partida -> hub")
	get_tree().quit(0)
