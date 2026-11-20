# res://Network/autoload/MatchCoordinator.gd
extends Node
## Autoload del ciclo de vida de la partida: countdown, selección, inicio,
## estadísticas y regreso al lobby.

const TAG := "MatchCoordinator"

var current_game_manager: Node = null
## Delegados en SessionState.
var current_match_char_map: Dictionary:
	get:
		return SessionState.char_map
	set(value):
		SessionState.char_map = value
var current_match_map_id: String:
	get:
		return SessionState.active_map_id
	set(value):
		SessionState.active_map_id = value
var last_match_results: Dictionary = {}
var _resetting := false
var _match_starting := false
var _returning_to_lobby := false
var _pending_spectate := false
var _main_scene: PackedScene = null
var _character_select_timer: Timer = null
var _start_countdown_timer: Timer = null

signal start_countdown_started(seconds: float)
signal start_countdown_cancelled()

# Alias de compatibilidad con consumidores existentes.
const MATCH_START_COUNTDOWN := NetConfig.MATCH_START_COUNTDOWN
const CHARACTER_SELECT_DURATION := NetConfig.CHARACTER_SELECT_DURATION


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	_start_countdown_timer = _make_timer(_on_start_countdown_timeout)
	_character_select_timer = _make_timer(_on_character_select_timeout)


func _make_timer(callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(callback)
	add_child(timer)
	return timer


func _on_server_disconnected() -> void:
	reset_to_menu()


func _is_dedicated_server() -> bool:
	var ds := get_node_or_null("/root/DedicatedServer")
	return ds != null and ds.is_dedicated


func _load_main_scene() -> PackedScene:
	if _main_scene != null:
		return _main_scene
	_main_scene = load(NetScenes.MAIN_UID) as PackedScene
	if _main_scene == null:
		NetLog.error(TAG, "No se pudo cargar la escena principal (%s)" % NetScenes.MAIN_UID)
	return _main_scene


func _can_continue_match_start() -> bool:
	return is_inside_tree() and multiplayer.multiplayer_peer != null


# ── Countdown de inicio ──

func start_match_countdown() -> void:
	if not multiplayer.is_server():
		return
	if LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY:
		return
	if is_start_countdown_active():
		return
	if LobbyManager.selected_map == "" or not MapRegistry.has_map(LobbyManager.selected_map):
		return
	if not LobbyManager.can_start_match():
		return
	_start_countdown_timer.start(NetConfig.MATCH_START_COUNTDOWN)
	rpc("_sync_start_countdown", NetConfig.MATCH_START_COUNTDOWN)


func stop_match_countdown() -> void:
	if multiplayer.multiplayer_peer == null:
		return
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
	if LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY:
		return
	if not LobbyManager.can_start_match():
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


# ── Selección de personaje ──

func start_character_select_timer() -> void:
	if not multiplayer.is_server():
		return
	_character_select_timer.start(NetConfig.CHARACTER_SELECT_DURATION)


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

	var char_map: Dictionary = {}
	for id in LobbyManager.players:
		if LobbyManager.is_spectator(id) or LobbyManager.is_afk(id):
			continue
		if not LobbyManager.match_participants.is_empty() and not LobbyManager.is_match_participant(id):
			continue

		var role: String = String(LobbyManager.players[id].get("assigned_role", PlayerInfo.ROLE_SURVIVOR))
		var char_id: int = int(LobbyManager.players[id].get("character_id", -1))
		var data: CharacterData = CharacterRegistry.get_character(char_id) if char_id > 0 else null

		var needs_fallback := data == null
		if data and data.dev_only and not LobbyManager.is_dev_peer(id):
			needs_fallback = true
		if data and data.team.to_lower().strip_edges() != role.to_lower().strip_edges():
			needs_fallback = true

		if needs_fallback:
			var fallback = CharacterRegistry.get_fallback(role)
			if fallback == null:
				NetLog.error(TAG, "Peer %d sin personaje resoluble para rol '%s'; se omite." % [id, role])
				continue
			char_id = fallback.id
			LobbyManager.players[id]["character_id"] = char_id

		char_map[id] = char_id

	current_match_char_map = char_map.duplicate()
	current_match_map_id = LobbyManager.selected_map
	if char_map.is_empty():
		NetLog.warn(TAG, "No hay participantes válidos para iniciar la partida")
		_match_starting = false
		LobbyManager.current_phase = LobbyManager.GamePhase.LOBBY
		return
	rpc("_begin_game", char_map, LobbyManager.selected_map)


@rpc("authority", "call_local", "reliable")
func _begin_game(char_map: Dictionary, map_id: String) -> void:
	NetLog.info(TAG, "Comenzando partida con mapa: %s" % map_id)
	current_match_char_map = char_map.duplicate()
	current_match_map_id = map_id
	LobbyManager.apply_match_presence(char_map)

	var local_id := multiplayer.get_unique_id()
	var is_dedicated := _is_dedicated_server()
	var is_server := multiplayer.is_server()
	var is_participant := char_map.has(local_id)
	var hub := get_tree().get_first_node_in_group(NetScenes.HUB_SESSION_GROUP)

	# Cliente no participante: se queda en el hub y carga el mapa bajo demanda.
	if not is_participant and not is_dedicated and not is_server:
		LobbyManager.current_phase = LobbyManager.GamePhase.PLAYING
		if hub and hub.has_method("on_match_started_for_hub"):
			hub.on_match_started_for_hub()
		return

	var local_view_mode := "play" if is_participant else "hub"

	if local_view_mode == "play":
		await SceneTransition.fade_to_black(0.45)
		if not _can_continue_match_start():
			_match_starting = false
			LobbyManager.current_phase = LobbyManager.GamePhase.LOBBY
			return
		for node in get_tree().get_nodes_in_group(GroupNames.CHARACTER_SELECT_SCREEN):
			node.queue_free()
		if hub and hub.has_method("enter_match_view"):
			hub.enter_match_view()
	elif hub and hub.has_method("on_match_started_for_hub"):
		hub.on_match_started_for_hub()

	var scene := _load_main_scene()
	if scene == null:
		_match_starting = false
		LobbyManager.current_phase = LobbyManager.GamePhase.LOBBY
		return
	current_game_manager = scene.instantiate()
	add_child(current_game_manager)
	if current_game_manager.has_method("start_game"):
		current_game_manager.start_game(char_map, map_id, local_view_mode)
	LobbyManager.current_phase = LobbyManager.GamePhase.PLAYING

	if local_view_mode == "play" and DisplayServer.get_name() != "headless":
		await get_tree().process_frame
		await get_tree().create_timer(0.15).timeout
		SceneTransition.fade_from_black(0.65)


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
		map_id = LobbyManager.selected_map
	if map_id == "":
		return false
	current_match_map_id = map_id

	var scene := _load_main_scene()
	if scene == null:
		return false
	current_game_manager = scene.instantiate()
	add_child(current_game_manager)
	if current_game_manager.has_method("start_game"):
		current_game_manager.start_game(current_match_char_map, map_id, mode)
	return true


# ── Espectador ──

func request_spectate() -> bool:
	if LobbyManager.current_phase != LobbyManager.GamePhase.PLAYING:
		return false
	var has_world := (
		current_game_manager != null
		and is_instance_valid(current_game_manager)
		and current_game_manager.has_method("get_world_instance")
		and current_game_manager.get_world_instance() != null
	)
	if current_match_char_map.is_empty() and not has_world:
		if not _pending_spectate:
			_pending_spectate = true
			rpc_id(LobbyManager.server_peer_id, "_request_match_snapshot")
		return false
	if not _get_or_create_match_world("spectate"):
		return false
	var hub := get_tree().get_first_node_in_group(NetScenes.HUB_SESSION_GROUP)
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
		sender = multiplayer.get_unique_id()
	if not LobbyManager.players.has(sender):
		return
	rpc_id(sender, "_receive_match_snapshot", current_match_char_map.duplicate(), current_match_map_id)


@rpc("authority", "reliable")
func _receive_match_snapshot(char_map: Dictionary, map_id: String) -> void:
	current_match_char_map = char_map.duplicate()
	if map_id != "":
		current_match_map_id = map_id
	if _pending_spectate:
		_pending_spectate = false
		if not current_match_char_map.is_empty():
			request_spectate()


@rpc("authority", "reliable")
func _join_late_as_spectator(phase: int, data: Dictionary) -> void:
	LobbyManager.current_phase = phase
	current_match_char_map = data.get("char_map", {}).duplicate()
	current_match_map_id = String(data.get("map_id", ""))

	for lobby in get_tree().get_nodes_in_group(GroupNames.LOBBY):
		lobby.queue_free()
	for node in get_tree().get_nodes_in_group(GroupNames.CHARACTER_SELECT_SCREEN):
		node.queue_free()

	var scene := get_tree().current_scene
	if scene == null or scene.name != "Session":
		SceneTransition.change_scene(NetScenes.SESSION, 0.45, 0.1, 0.6)
		return

	var hub = get_tree().get_first_node_in_group(NetScenes.HUB_SESSION_GROUP)
	if phase == LobbyManager.GamePhase.PLAYING and hub and hub.has_method("on_match_started_for_hub"):
		hub.on_match_started_for_hub()
	elif phase == LobbyManager.GamePhase.ENDED and hub and hub.has_method("on_match_ended_for_hub"):
		hub.on_match_ended_for_hub()


# ── Fin de partida ──

func cleanup_game_manager() -> void:
	if not current_game_manager or not is_instance_valid(current_game_manager):
		return
	if current_game_manager.has_method("cleanup"):
		current_game_manager.cleanup()
	current_game_manager.queue_free()
	current_game_manager = null


@rpc("authority", "call_local", "reliable")
func _go_to_stats_screen(stats_data: Dictionary) -> void:
	var local_id := multiplayer.get_unique_id()
	var is_participant := LobbyManager.is_match_participant(local_id)
	if (
		LobbyManager.match_participants.is_empty()
		and LobbyManager.players.has(local_id)
		and not LobbyManager.is_spectator(local_id)
		and not LobbyManager.is_afk(local_id)
	):
		is_participant = true
	LobbyManager.current_phase = LobbyManager.GamePhase.ENDED
	AudioManager.reset_match_audio()
	cleanup_game_manager()

	if not is_participant:
		var hub := get_tree().get_first_node_in_group(NetScenes.HUB_SESSION_GROUP)
		if hub and hub.has_method("on_match_ended_for_hub"):
			hub.on_match_ended_for_hub()
		return

	last_match_results = stats_data
	LobbyManager.set_local_presence(PlayerInfo.PRESENCE_MATCH)
	if not _is_dedicated_server():
		SceneTransition.change_scene(NetScenes.MATCH_STATS, 0.45, 0.1, 0.6)


func request_return_to_lobby() -> void:
	if multiplayer.is_server():
		_server_return_to_lobby()
	else:
		rpc_id(LobbyManager.server_peer_id, "_server_return_to_lobby")


@rpc("any_peer", "reliable")
func _server_return_to_lobby() -> void:
	if not multiplayer.is_server():
		return
	if LobbyManager.current_phase != LobbyManager.GamePhase.ENDED:
		return
	if _returning_to_lobby:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var is_local_server := sender == multiplayer.get_unique_id()
	# Cualquier jugador registrado puede volver al lobby desde la pantalla de
	# estadísticas. Antes solo se permitía al host, así que a los clientes el
	# botón les quedaba sin efecto.
	if not is_local_server and not LobbyManager.players.has(sender):
		NetLog.warn(TAG, "Peer %d intentó volver al lobby sin estar registrado." % sender)
		return
	_returning_to_lobby = true
	NetLog.info(TAG, "El room host ordenó volver al lobby.")
	_return_to_lobby_local()


## Local, no RPC. Solo se llama desde `_server_return_to_lobby`, que valida
## remitente y fase.
func _return_to_lobby_local() -> void:
	LobbyManager.clear_forced_killer_state()
	for pid in LobbyManager.players:
		LobbyManager.players[pid]["character_id"] = -1
		LobbyManager.players[pid]["afk"] = false
		LobbyManager.players[pid]["presence"] = PlayerInfo.PRESENCE_HUB
		if LobbyManager.players[pid].get("is_spectator", false):
			LobbyManager.players[pid]["assigned_role"] = PlayerInfo.ROLE_SURVIVOR
			LobbyManager.players[pid]["is_spectator"] = false
		else:
			LobbyManager.players[pid]["assigned_role"] = PlayerInfo.ROLE_SURVIVOR
	LobbyManager.match_participants.clear()

	rpc("_back_to_lobby_scene", PlayerInfo.public_copy(LobbyManager.players))


@rpc("authority", "call_local", "reliable")
func _back_to_lobby_scene(reseted_players: Dictionary) -> void:
	_match_starting = false
	_returning_to_lobby = false
	stop_character_select_timer()
	LobbyManager.players = reseted_players
	LobbyManager.clear_forced_killer_state()
	SessionState.clear_match()
	LobbyManager.current_phase = LobbyManager.GamePhase.LOBBY
	AudioManager.reset_match_audio()
	SceneTransition.change_scene(NetScenes.SESSION, 0.5, 0.25, 0.7)


func reset_to_menu() -> void:
	if _resetting:
		return
	_resetting = true
	AudioManager.reset_match_audio()
	cleanup_game_manager()
	_match_starting = false
	_returning_to_lobby = false
	_pending_spectate = false
	stop_character_select_timer()
	stop_match_countdown()

	NetworkManager.disconnect_from_server()
	LobbyManager.reset_session()

	for match_coordinator in get_tree().get_nodes_in_group(GroupNames.MATCH_COORDINATOR):
		match_coordinator.queue_free()

	call_deferred("_do_change_to_menu")


func _do_change_to_menu() -> void:
	_resetting = false
	if is_inside_tree():
		SceneTransition.change_scene(NetScenes.MAIN_MENU, 0.45, 0.1, 0.5)
