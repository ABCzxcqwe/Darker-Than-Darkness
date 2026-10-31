# res://core/MatchCoordinator.gd
# Gestiona el ciclo de vida de la partida: inicio, fin, estadísticas y regreso al lobby.
extends Node

var current_game_manager: Node = null
var current_match_char_map: Dictionary = {}
var current_match_map_id := ""
var last_match_results: Dictionary = {}
var _resetting := false
var _match_starting := false
var _returning_to_lobby := false
var _pending_spectate := false
var _character_select_timer: Timer = null
var _start_countdown_timer: Timer = null

signal start_countdown_started(seconds: float)
signal start_countdown_cancelled()

const MAIN_SCENE := preload("uid://c4oma0j4cetoj")
const MATCH_START_COUNTDOWN := 10.0
## Duración server-authoritative de la fase de selección de personaje.
## Ligeramente mayor que el countdown visual (15s) para dar margen a que
## lleguen las selecciones de los clientes antes de rellenar las faltantes.
const CHARACTER_SELECT_DURATION := 16.5


func _ready() -> void:
	NetworkManager.server_disconnected.connect(_on_server_disconnected)


func _on_server_disconnected() -> void:
	reset_to_menu()


func _is_dedicated_server() -> bool:
	var ds := get_node_or_null("/root/DedicatedServer")
	return ds != null and ds.is_dedicated


func start_match_countdown() -> void:
	if not multiplayer.is_server():
		return
	if LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY:
		return
	if is_start_countdown_active():
		return
	if LobbyManager.selected_map == "" or not MapRegistry.has_map(LobbyManager.selected_map):
		return
	if LobbyManager.get_active_participants().size() < 2 and not DevMode.is_enabled():
		return
	if _start_countdown_timer == null:
		_start_countdown_timer = Timer.new()
		_start_countdown_timer.one_shot = true
		_start_countdown_timer.timeout.connect(_on_start_countdown_timeout)
		add_child(_start_countdown_timer)
	_start_countdown_timer.start(MATCH_START_COUNTDOWN)
	rpc("_sync_start_countdown", MATCH_START_COUNTDOWN)


func stop_match_countdown() -> void:
	if not multiplayer.is_server():
		return
	if not is_start_countdown_active():
		return
	_start_countdown_timer.stop()
	rpc("_sync_start_countdown_cancelled")


func is_start_countdown_active() -> bool:
	return _start_countdown_timer != null and not _start_countdown_timer.is_stopped()


func _on_start_countdown_timeout() -> void:
	if not multiplayer.is_server():
		return
	if LobbyManager.get_active_participants().size() < 2 and not DevMode.is_enabled():
		rpc("_sync_start_countdown_cancelled")
		return
	if LobbyManager.get_killer_candidates().is_empty() and LobbyManager.forced_killer_peer == -1:
		rpc("_sync_start_countdown_cancelled")
		return
	LobbyManager.host_start_character_selection()


@rpc("authority", "call_local", "reliable")
func _sync_start_countdown(seconds: float) -> void:
	start_countdown_started.emit(seconds)


@rpc("authority", "call_local", "reliable")
func _sync_start_countdown_cancelled() -> void:
	start_countdown_cancelled.emit()


## Arranca el temporizador que lanza la partida al terminar la selección.
## Vive en el servidor (host), independiente de la UI, para que la partida
## arranque aunque el host sea espectador y su pantalla no muestre countdown.
func start_character_select_timer() -> void:
	if not multiplayer.is_server():
		return
	if _character_select_timer == null:
		_character_select_timer = Timer.new()
		_character_select_timer.one_shot = true
		_character_select_timer.timeout.connect(_on_character_select_timeout)
		add_child(_character_select_timer)
	_character_select_timer.start(CHARACTER_SELECT_DURATION)


func stop_character_select_timer() -> void:
	if _character_select_timer:
		_character_select_timer.stop()


func _on_character_select_timeout() -> void:
	if not multiplayer.is_server():
		return
	if LobbyManager.current_phase != LobbyManager.GamePhase.CHARACTER_SELECT:
		return
	LobbyManager.host_resolve_missing_selections()
	host_launch_game()


func host_launch_game() -> void:
	if not multiplayer.is_server():
		return
	if _match_starting:
		return
	_match_starting = true
	stop_character_select_timer()

	var char_map = {}
	for id in LobbyManager.players:
		if LobbyManager.is_spectator(id) or LobbyManager.is_afk(id):
			continue
		if not LobbyManager.match_participants.is_empty() and not LobbyManager.is_match_participant(id):
			continue

		var role: String = String(LobbyManager.players[id].get("assigned_role", "survivor"))
		var char_id: int = int(LobbyManager.players[id].get("character_id", -1))
		var data: CharacterData = CharacterRegistry.get_character(char_id) if char_id > 0 else null

		var needs_fallback := data == null
		if data and data.dev_only and not LobbyManager.is_dev_peer(id):
			needs_fallback = true
		if data and data.team.to_lower().strip_edges() != role.to_lower().strip_edges():
			needs_fallback = true

		if needs_fallback:
			var fallback := CharacterRegistry.get_fallback(role)
			if fallback == null:
				push_error("[MatchCoordinator] Peer %d sin personaje resoluble y sin fallback para rol '%s'; se omite." % [id, role])
				continue
			push_warning("[MatchCoordinator] Peer %d: ID %d no válido/permitido para rol '%s'; usando '%s' (id %d)." % [
				id, char_id, role, fallback.display_name, fallback.id
			])
			char_id = fallback.id
			LobbyManager.players[id]["character_id"] = char_id

		char_map[id] = char_id

	current_match_char_map = char_map.duplicate()
	current_match_map_id = LobbyManager.selected_map
	rpc("_begin_game", char_map, LobbyManager.selected_map)


@rpc("authority", "call_local", "reliable")
func _begin_game(char_map: Dictionary, map_id: String) -> void:
	print("Comenzando partida con el mapa: ", map_id)
	GameData.selected_map = map_id
	current_match_char_map = char_map.duplicate()
	current_match_map_id = map_id
	LobbyManager.apply_match_presence(char_map)

	var local_id := multiplayer.get_unique_id()
	var is_dedicated := _is_dedicated_server()
	var is_server := multiplayer.is_server()
	var is_participant := char_map.has(local_id)
	var hub := get_tree().get_first_node_in_group("hub_session")

	# Cliente no participante: no carga el mapa todavía. Puede pedirlo al pulsar
	# ESPECTAR (carga bajo demanda).
	if not is_participant and not is_dedicated and not is_server:
		LobbyManager.current_phase = LobbyManager.GamePhase.PLAYING
		if hub and hub.has_method("on_match_started_for_hub"):
			hub.on_match_started_for_hub()
		print("[MatchCoordinator] Peer %d queda en el hub (no participante)." % local_id)
		return

	var local_view_mode := "play" if is_participant else "hub"

	if local_view_mode == "play":
		await SceneTransition.fade_to_black(0.45)
		for node in get_tree().get_nodes_in_group(GroupNames.CHARACTER_SELECT_SCREEN):
			node.queue_free()
		if hub and hub.has_method("enter_match_view"):
			hub.enter_match_view()
	elif hub and hub.has_method("on_match_started_for_hub"):
		# Host/servidor AFK: sigue en el hub, pero el World se simula abajo.
		hub.on_match_started_for_hub()

	current_game_manager = MAIN_SCENE.instantiate()
	add_child(current_game_manager)
	current_game_manager.start_game(char_map, map_id, local_view_mode)
	LobbyManager.current_phase = LobbyManager.GamePhase.PLAYING

	if local_view_mode == "play" and DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await get_tree().create_timer(0.15).timeout
		SceneTransition.fade_from_black(0.65)


## Cambia la vista local del World sin destruirlo. Lo usa Session al volver al
## hub o al reentrar a espectar.
func set_local_view_mode(mode: String) -> void:
	if current_game_manager == null or not is_instance_valid(current_game_manager):
		return
	var world: Node = null
	if current_game_manager.has_method("get_world_instance"):
		world = current_game_manager.get_world_instance()
	if world and world.has_method("set_local_view_mode"):
		world.set_local_view_mode(mode)


func _get_or_create_match_world(mode: String) -> bool:
	if current_game_manager and is_instance_valid(current_game_manager):
		var existing_world: Node = null
		if current_game_manager.has_method("get_world_instance"):
			existing_world = current_game_manager.get_world_instance()
		if existing_world and existing_world.has_method("set_local_view_mode"):
			existing_world.set_local_view_mode(mode)
			return true
		current_game_manager.queue_free()
		current_game_manager = null

	if current_match_char_map.is_empty():
		return false

	var map_id := current_match_map_id
	if map_id == "":
		map_id = GameData.selected_map
	if map_id == "":
		map_id = LobbyManager.selected_map
	if map_id == "":
		return false
	current_match_map_id = map_id
	GameData.selected_map = map_id

	current_game_manager = MAIN_SCENE.instantiate()
	add_child(current_game_manager)
	current_game_manager.start_game(current_match_char_map, map_id, mode)
	return true


## El jugador local (muerto, AFK, late join o no participante) pide espectar.
## Devuelve false si todavía está esperando el snapshot del servidor.
func request_spectate() -> bool:
	if LobbyManager.current_phase != LobbyManager.GamePhase.PLAYING:
		return false
	var has_world := current_game_manager != null and is_instance_valid(current_game_manager) \
		and current_game_manager.has_method("get_world_instance") \
		and current_game_manager.get_world_instance() != null
	if current_match_char_map.is_empty() and not has_world:
		# Algunos clientes (sobre todo late join) pueden no haber recibido
		# todavía el roster de la ronda. Pedirlo antes de construir el World.
		if not _pending_spectate:
			_pending_spectate = true
			print("[MatchCoordinator] Solicitando snapshot de partida para espectar.")
			rpc_id(1, "_request_match_snapshot")
		return false
	if not _get_or_create_match_world("spectate"):
		return false
	var hub := get_tree().get_first_node_in_group("hub_session")
	if hub and hub.has_method("enter_spectator_view"):
		hub.enter_spectator_view()
	set_local_view_mode("spectate")
	return true


@rpc("any_peer", "reliable")
func _request_match_snapshot() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	rpc_id(sender, "_receive_match_snapshot",
		current_match_char_map.duplicate(), current_match_map_id)


@rpc("authority", "reliable")
func _receive_match_snapshot(char_map: Dictionary, map_id: String) -> void:
	current_match_char_map = char_map.duplicate()
	if map_id != "":
		current_match_map_id = map_id
		GameData.selected_map = map_id
	if _pending_spectate:
		_pending_spectate = false
		request_spectate()


@rpc("authority", "reliable")
func _join_late_as_spectator(phase: int, data: Dictionary) -> void:
	print("[MatchCoordinator] Late-join como espectador, fase: ", phase)
	LobbyManager.current_phase = phase
	current_match_char_map = data.get("char_map", {}).duplicate()
	current_match_map_id = String(data.get("map_id", ""))

	for lobby in get_tree().get_nodes_in_group("lobby"):
		lobby.queue_free()

	for node in get_tree().get_nodes_in_group(GroupNames.CHARACTER_SELECT_SCREEN):
		node.queue_free()

	GameData.selected_map = current_match_map_id
	var scene := get_tree().current_scene
	if scene == null or scene.name != "Session":
		SceneTransition.change_scene("res://Maps/Session.tscn", 0.45, 0.1, 0.6)
		return

	var hub = get_tree().get_first_node_in_group("hub_session")
	if phase == LobbyManager.GamePhase.PLAYING:
		if hub and hub.has_method("on_match_started_for_hub"):
			hub.on_match_started_for_hub()
	elif phase == LobbyManager.GamePhase.ENDED:
		if hub and hub.has_method("on_match_ended_for_hub"):
			hub.on_match_ended_for_hub()


func _sync_spectator_audio(_map_id: String) -> void:
	var game_state = GameServiceLocator.game_state
	if game_state and game_state.current_state != 1:
		game_state.current_state = 1
	# La musica la sincroniza el servidor via ClientRelay._rpc_sync_spectator_audio
	# (mapa + personajes + track prioritario/LMS a mitad).


func cleanup_game_manager() -> void:
	if current_game_manager and is_instance_valid(current_game_manager):
		if current_game_manager.has_method("cleanup"):
			current_game_manager.cleanup()
		current_game_manager.queue_free()
		current_game_manager = null
		await get_tree().process_frame
		await get_tree().process_frame


@rpc("authority", "call_local", "reliable")
func _go_to_stats_screen(stats_data: Dictionary) -> void:
	var local_id := multiplayer.get_unique_id()
	var is_participant := LobbyManager.is_match_participant(local_id)
	if LobbyManager.match_participants.is_empty() and LobbyManager.players.has(local_id) \
			and not LobbyManager.is_spectator(local_id) and not LobbyManager.is_afk(local_id):
		is_participant = true
	LobbyManager.current_phase = LobbyManager.GamePhase.ENDED

	# Fix: silencio total en TODOS los peers (stats ya es call_local)
	# Placeholder hasta nueva música de stats — evita que map/terror/chase/LMS queden sonando en clientes
	AudioManager.reset_match_audio()

	if not is_participant:
		# AFK / late join / no participante: sigue en el hub y no ve resultados.
		cleanup_game_manager()
		var hub = get_tree().get_first_node_in_group("hub_session")
		if hub and hub.has_method("on_match_ended_for_hub"):
			hub.on_match_ended_for_hub()
		return

	last_match_results = stats_data
	# Quien va a resultados deja de mostrarse como presente en el hub.
	LobbyManager.set_local_presence("match")
	cleanup_game_manager()

	if not _is_dedicated_server():
		SceneTransition.change_scene("res://ui/GameUI/Scenes/MatchStats.tscn", 0.45, 0.1, 0.6)


## Cualquier jugador puede pedir volver al lobby cuando la partida terminó.
## En la arquitectura actual la vuelta es compartida: el primero que la pide
## devuelve a todos. Cuando exista la sesión/hub, esto pasará a ser un cierre
## local del overlay de resultados.
func request_return_to_lobby() -> void:
	if multiplayer.is_server():
		_server_return_to_lobby()
	else:
		rpc_id(1, "_server_return_to_lobby")


@rpc("any_peer", "reliable")
func _server_return_to_lobby() -> void:
	if not multiplayer.is_server():
		return
	if LobbyManager.current_phase != LobbyManager.GamePhase.ENDED:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if not LobbyManager.players.has(sender):
		return
	if _returning_to_lobby:
		return
	_returning_to_lobby = true
	print("[MatchCoordinator] Peer %d pidió volver al lobby" % sender)
	host_return_to_lobby_reconfigured()


@rpc("any_peer", "call_local", "reliable")
func host_return_to_lobby_reconfigured() -> void:
	if not LobbyManager.is_host:
		return

	LobbyManager.clear_forced_killer_state()
	for pid in LobbyManager.players:
		LobbyManager.players[pid]["character_id"] = -1
		LobbyManager.players[pid]["afk"] = false
		LobbyManager.players[pid]["presence"] = "hub"
		if LobbyManager.players[pid].get("is_spectator", false):
			LobbyManager.players[pid]["assigned_role"] = "survivor"
			LobbyManager.players[pid]["is_spectator"] = false
		else:
			LobbyManager.players[pid]["assigned_role"] = "survivor"
	LobbyManager.match_participants.clear()

	rpc("_back_to_lobby_scene", LobbyManager.players)


@rpc("authority", "call_local", "reliable")
func _back_to_lobby_scene(reseted_players: Dictionary) -> void:
	_match_starting = false
	_returning_to_lobby = false
	stop_character_select_timer()
	LobbyManager.players = reseted_players
	# Asegurar que el flag/bakcup del forzado no quede colgado si _calculate no corrió
	LobbyManager.clear_forced_killer_state()
	LobbyManager.match_participants.clear()
	current_match_char_map.clear()
	current_match_map_id = ""
	LobbyManager.current_phase = LobbyManager.GamePhase.LOBBY
	AudioManager.reset_match_audio()
	# El servidor dedicado también carga el hub: recibe y retransmite el
	# estado de los avatares entre los clientes.
	SceneTransition.change_scene("res://Maps/Session.tscn", 0.5, 0.25, 0.7)


func reset_to_menu() -> void:
	if _resetting:
		return
	_resetting = true
	print("[MatchCoordinator] reset_to_menu")
	AudioManager.reset_match_audio()
	cleanup_game_manager()
	_match_starting = false
	_returning_to_lobby = false
	stop_character_select_timer()

	NetworkManager.disconnect_from_server()
	LobbyManager.reset_lobby_state()
	current_match_char_map.clear()
	current_match_map_id = ""
	LobbyManager.local_player_name = ""
	LobbyManager.selected_map = ""
	LobbyManager.room_name = ""
	LobbyManager.game_mode = "Escape"
	LobbyManager.is_host = false
	LobbyManager.current_phase = LobbyManager.GamePhase.LOBBY

	for match_coordinator in get_tree().get_nodes_in_group(GroupNames.MATCH_COORDINATOR):
		match_coordinator.queue_free()

	call_deferred("_do_change_to_menu")


func _do_change_to_menu() -> void:
	_resetting = false
	if is_inside_tree():
		SceneTransition.change_scene("res://ui/MainMenu/scenes/MainMenu.tscn", 0.45, 0.1, 0.5)
