# res://core/LobbyManager.gd (Autoload)
# Gestiona el estado de la sala: jugadores, roles, selección de personajes.
extends Node

signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)
signal lobby_updated()

const MAX_PLAYERS := 5

var players: Dictionary = {}
var local_player_name: String = ""
var selected_map: String = ""
var is_host: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


# ── Peer management ──

func _on_peer_connected(peer_id: int):
	if not multiplayer.is_server():
		return
	rpc_id(peer_id, "_request_player_info")


@rpc("any_peer", "call_local")
func _request_player_info():
	var sender = multiplayer.get_remote_sender_id()
	rpc_id(sender, "_send_player_info", local_player_name)


@rpc("any_peer", "call_local")
func _send_player_info(player_name: String):
	var sender = multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		players[sender] = {
			"name": player_name,
			"is_host": false,
			"character_id": -1,
			"killer_points": 0,
			"assigned_role": "survivor"
		}
		emit_signal("player_joined", sender, players[sender])

		var self_id = multiplayer.get_unique_id()
		for pid in players:
			if pid != self_id:
				rpc_id(pid, "_sync_lobby_state", players, selected_map)


@rpc("authority", "reliable")
func _sync_lobby_state(all_players: Dictionary, map_id: String):
	players = all_players
	selected_map = map_id
	emit_signal("lobby_updated")


func _on_peer_disconnected(peer_id: int):
	if multiplayer.is_server():
		var abandoned_role: String = ""
		if players.has(peer_id):
			abandoned_role = players[peer_id]["assigned_role"]

		players.erase(peer_id)
		emit_signal("player_left", peer_id)

		var game_state = GameServiceLocator.get_service(ServiceNames.GAME_STATE) if GameServiceLocator.has_service(ServiceNames.GAME_STATE) else null
		if game_state and game_state.is_in_game():
			game_state.handle_player_disconnect(peer_id, abandoned_role)

		var self_id = multiplayer.get_unique_id()
		for pid in players:
			if pid != self_id:
				rpc_id(pid, "_sync_lobby_state", players, selected_map)


# ── Player list management ──

func get_player_list() -> Array:
	var list = []
	for id in players:
		var info = players[id].duplicate()
		info.id = id
		list.append(info)
	return list


func get_local_character() -> int:
	var my_id = multiplayer.get_unique_id()
	if players.has(my_id):
		return players[my_id].character_id
	return -1


func set_my_character(char_id: int):
	var my_id = multiplayer.get_unique_id()
	if players.has(my_id):
		players[my_id].character_id = char_id
		if is_host:
			emit_signal("lobby_updated")
		else:
			rpc_id(1, "_update_character", char_id)


@rpc("any_peer", "call_local")
func _update_character(char_id: int):
	var sender = multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		if players.has(sender):
			players[sender].character_id = char_id
			emit_signal("lobby_updated")
			rpc("_sync_character", sender, char_id)


@rpc("authority", "reliable")
func _sync_character(peer_id: int, char_id: int):
	if not multiplayer.is_server():
		if players.has(peer_id):
			players[peer_id].character_id = char_id
			emit_signal("lobby_updated")


# ── Character selection flow ──

func host_start_character_selection():
	if not is_host:
		return

	if players.size() < 2:
		print("[LobbyManager] Se necesitan al menos 2 jugadores.")
		return

	randomize()

	var highest_points: int = -1
	var candidates: Array[int] = []

	for pid in players:
		var p_data = players[pid]
		if p_data.killer_points > highest_points:
			highest_points = p_data.killer_points
			candidates = [pid]
		elif p_data.killer_points == highest_points:
			candidates.append(pid)

	var killer_peer_id: int = candidates[randi() % candidates.size()]

	for pid in players:
		players[pid]["character_id"] = -1
		if pid == killer_peer_id:
			players[pid]["assigned_role"] = "killer"
		else:
			players[pid]["assigned_role"] = "survivor"

	rpc("_go_to_character_selection", players)


@rpc("authority", "call_local", "reliable")
func _go_to_character_selection(assigned_players: Dictionary):
	players = assigned_players
	for lobby in get_tree().get_nodes_in_group("lobby"):
		lobby.queue_free()
	get_tree().change_scene_to_file("res://ui/GameUI/Scenes/CharacterSelect.tscn")


@rpc("any_peer", "call_local", "reliable")
func select_character_in_screen(char_id: int):
	var sender_id = multiplayer.get_remote_sender_id()

	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	if multiplayer.is_server():
		if players.has(sender_id):
			players[sender_id]["character_id"] = char_id
			print("[Server] Peer %d seleccionó personaje ID: %d" % [sender_id, char_id])
			emit_signal("lobby_updated")
			rpc("_sync_screen_selection", sender_id, char_id)
	else:
		rpc_id(1, "select_character_in_screen", char_id)


@rpc("authority", "reliable")
func _sync_screen_selection(peer_id: int, char_id: int):
	if not multiplayer.is_server():
		if players.has(peer_id):
			players[peer_id]["character_id"] = char_id
			print("[Cliente] Sincronizado: Peer %d ahora es personaje %d" % [peer_id, char_id])
			emit_signal("lobby_updated")


# ── Setup / Reset ──

func setup_as_host(player_name: String, map_name: String) -> void:
	is_host = true
	local_player_name = player_name
	selected_map = map_name
	reset_lobby_state()


func setup_as_client(player_name: String) -> void:
	is_host = false
	local_player_name = player_name
	reset_lobby_state()


func register_local_player(peer_id: int, player_name: String) -> void:
	players[peer_id] = {
		"name": player_name,
		"is_host": is_host,
		"character_id": -1,
		"killer_points": 0,
		"assigned_role": "survivor"
	}
	emit_signal("player_joined", peer_id, players[peer_id])


func reset_lobby_state() -> void:
	players.clear()
