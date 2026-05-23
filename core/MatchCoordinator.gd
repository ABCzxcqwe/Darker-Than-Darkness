# res://core/MatchCoordinator.gd
# Gestiona el ciclo de vida de la partida: inicio, fin, estadísticas y regreso al lobby.
extends Node

var current_game_manager: Node = null
var last_match_results: Dictionary = {}

const MAIN_SCENE := preload("uid://c4oma0j4cetoj")


func _ready() -> void:
	NetworkManager.server_disconnected.connect(_on_server_disconnected)


func _on_server_disconnected() -> void:
	reset_to_menu()


func host_launch_game() -> void:
	if not NetworkManager.is_host:
		return

	var char_map = {}
	for id in NetworkManager.players:
		char_map[id] = NetworkManager.players[id].character_id

	rpc("_begin_game", char_map, NetworkManager.selected_map)


@rpc("authority", "call_local", "reliable")
func _begin_game(char_map: Dictionary, map_id: String) -> void:
	print("Comenzando partida con el mapa: ", map_id)
	GameData.selected_map = map_id

	for node in get_tree().get_nodes_in_group("character_select_screen"):
		node.queue_free()

	current_game_manager = MAIN_SCENE.instantiate()
	add_child(current_game_manager)
	current_game_manager.start_game(char_map, map_id)


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

	cleanup_game_manager()

	get_tree().change_scene_to_file("res://ui/GameUI/Scenes/MatchStats.tscn")


@rpc("any_peer", "call_local", "reliable")
func host_return_to_lobby_reconfigured() -> void:
	if not NetworkManager.is_host:
		return

	for pid in NetworkManager.players:
		NetworkManager.players[pid]["character_id"] = -1

	rpc("_back_to_lobby_scene", NetworkManager.players)


@rpc("authority", "call_local", "reliable")
func _back_to_lobby_scene(reseted_players: Dictionary) -> void:
	NetworkManager.players = reseted_players
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/Lobby.tscn")


func reset_to_menu() -> void:
	print("[MatchCoordinator] reset_to_menu")
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

	cleanup_game_manager()

	NetworkManager.players.clear()
	NetworkManager.local_player_name = ""
	NetworkManager.selected_map = ""
	NetworkManager.is_host = false

	for match_coordinator in get_tree().get_nodes_in_group("match_coordinator"):
		match_coordinator.queue_free()

	call_deferred("_do_change_to_menu")


func _do_change_to_menu() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")
