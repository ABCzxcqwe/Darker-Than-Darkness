# res://core/MatchCoordinator.gd
# Gestiona el ciclo de vida de la partida: inicio, fin, estadísticas y regreso al lobby.
extends Node

var current_game_manager: Node = null
var last_match_results: Dictionary = {}
var _resetting := false
var _match_starting := false
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
	if LobbyManager.players.size() < 2:
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
		if LobbyManager.is_spectator(id):
			continue
		char_map[id] = LobbyManager.players[id].character_id

	rpc("_begin_game", char_map, LobbyManager.selected_map)


@rpc("authority", "call_local", "reliable")
func _begin_game(char_map: Dictionary, map_id: String) -> void:
	print("Comenzando partida con el mapa: ", map_id)
	GameData.selected_map = map_id

	if LobbyManager.is_spectator(multiplayer.get_unique_id()) \
			and LobbyManager.current_phase == LobbyManager.GamePhase.PLAYING:
		print("[MatchCoordinator] Espectador ignorando _begin_game (ya en World)")
		return

	for node in get_tree().get_nodes_in_group(GroupNames.CHARACTER_SELECT_SCREEN):
		node.queue_free()

	current_game_manager = MAIN_SCENE.instantiate()
	add_child(current_game_manager)
	current_game_manager.start_game(char_map, map_id)

	LobbyManager.current_phase = LobbyManager.GamePhase.PLAYING


@rpc("authority", "reliable")
func _join_late_as_spectator(phase: int, data: Dictionary) -> void:
	print("[MatchCoordinator] Late-join como espectador, fase: ", phase)
	LobbyManager.current_phase = phase

	for lobby in get_tree().get_nodes_in_group("lobby"):
		lobby.queue_free()

	for node in get_tree().get_nodes_in_group(GroupNames.CHARACTER_SELECT_SCREEN):
		node.queue_free()

	match phase:
		LobbyManager.GamePhase.CHARACTER_SELECT:
			# Si el host ya lanzó (_begin_game llegó en el mismo frame), el World ya
			# existe y cambiar a CharacterSelect lo superpondría encima, dejando al
			# espectador clavado. Esperamos un frame y solo cambiamos si sigue sin World.
			await get_tree().process_frame
			if current_game_manager == null:
				get_tree().change_scene_to_file("res://ui/GameUI/Scenes/CharacterSelect.tscn")
		LobbyManager.GamePhase.PLAYING:
			GameData.selected_map = data.get("map_id", "")
			current_game_manager = MAIN_SCENE.instantiate()
			add_child(current_game_manager)
			var char_map: Dictionary = data.get("char_map", {})
			current_game_manager.start_game(char_map, data.get("map_id", ""))
			call_deferred("_sync_spectator_audio", data.get("map_id", ""))
		LobbyManager.GamePhase.ENDED:
			AudioManager.reset_match_audio()
			get_tree().change_scene_to_file("res://ui/GameUI/Scenes/MatchStats.tscn")


func _sync_spectator_audio(_map_id: String) -> void:
	var game_state = GameServiceLocator.game_state
	if game_state and game_state.current_state != 1:
		game_state.current_state = 1
	# La musica la sincroniza el servidor via ClientRelay._rpc_sync_spectator_audio
	# (mapa + personajes + track prioritario/LMS a mitad).


func cleanup_game_manager() -> void:
	if current_game_manager:
		if current_game_manager.has_method("cleanup"):
			current_game_manager.cleanup()
		current_game_manager.queue_free()
		current_game_manager = null
		await get_tree().process_frame
		await get_tree().process_frame


@rpc("authority", "call_local", "reliable")
func _go_to_stats_screen(stats_data: Dictionary) -> void:
	last_match_results = stats_data

	# Fix: silencio total en TODOS los peers (stats ya es call_local)
	# Placeholder hasta nueva música de stats — evita que map/terror/chase/LMS queden sonando en clientes
	AudioManager.reset_match_audio()

	cleanup_game_manager()

	if not _is_dedicated_server():
		get_tree().change_scene_to_file("res://ui/GameUI/Scenes/MatchStats.tscn")

	LobbyManager.current_phase = LobbyManager.GamePhase.ENDED


@rpc("any_peer", "call_local", "reliable")
func host_return_to_lobby_reconfigured() -> void:
	if not LobbyManager.is_host:
		return

	LobbyManager.clear_forced_killer_state()
	for pid in LobbyManager.players:
		LobbyManager.players[pid]["character_id"] = -1
		if LobbyManager.players[pid].get("is_spectator", false):
			LobbyManager.players[pid]["assigned_role"] = "survivor"
			LobbyManager.players[pid]["is_spectator"] = false
		else:
			LobbyManager.players[pid]["assigned_role"] = "survivor"

	rpc("_back_to_lobby_scene", LobbyManager.players)


@rpc("authority", "call_local", "reliable")
func _back_to_lobby_scene(reseted_players: Dictionary) -> void:
	_match_starting = false
	stop_character_select_timer()
	LobbyManager.players = reseted_players
	# Asegurar que el flag/bakcup del forzado no quede colgado si _calculate no corrió
	LobbyManager.clear_forced_killer_state()
	LobbyManager.current_phase = LobbyManager.GamePhase.LOBBY
	AudioManager.reset_match_audio()
	if not _is_dedicated_server():
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/Lobby.tscn")


func reset_to_menu() -> void:
	if _resetting:
		return
	_resetting = true
	print("[MatchCoordinator] reset_to_menu")
	AudioManager.reset_match_audio()
	cleanup_game_manager()
	_match_starting = false
	stop_character_select_timer()

	NetworkManager.disconnect_from_server()
	LobbyManager.reset_lobby_state()
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
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")
