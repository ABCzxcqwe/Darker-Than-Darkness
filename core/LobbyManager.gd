# res://core/LobbyManager.gd (Autoload)
# Gestiona el estado de la sala: jugadores, roles, selección de personajes.
extends Node

signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)
signal lobby_updated()
signal kicked(reason: String)

const MAX_PLAYERS := 10

enum GamePhase { LOBBY, CHARACTER_SELECT, PLAYING, ENDED }

var players: Dictionary = {}
var local_player_name: String = ""
var selected_map: String = ""
var room_name: String = ""
var game_mode: String = "Escape"
var max_players: int = 4
var is_host: bool = false
var current_phase: int = GamePhase.LOBBY
var forced_killer_peer: int = -1


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func is_spectator(peer_id: int) -> bool:
	return players.has(peer_id) and players[peer_id].get("is_spectator", false)


# ── Peer management ──

func _on_peer_connected(peer_id: int):
	if not multiplayer.is_server():
		return
	if current_phase != GamePhase.LOBBY:
		rpc_id(peer_id, "_request_player_info")
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
		var is_full := players.size() >= max_players
		var is_late_join := current_phase != GamePhase.LOBBY or is_full
		players[sender] = {
			"name": player_name,
			"is_host": false,
			"character_id": -1,
			"killer_points": 0,
			"assigned_role": "spectator" if is_late_join else "survivor",
			"is_spectator": is_late_join
		}
		emit_signal("player_joined", sender, players[sender])

		var self_id = multiplayer.get_unique_id()
		if not is_late_join:
			for pid in players:
				if pid != self_id:
					rpc_id(pid, "_sync_lobby_state", players, selected_map, room_name, game_mode, max_players)
		else:
			for pid in players:
				if pid != self_id and pid != sender:
					rpc_id(pid, "_sync_lobby_state", players, selected_map, room_name, game_mode, max_players)
			rpc_id(sender, "_sync_lobby_state", players, selected_map, room_name, game_mode, max_players)
			_send_spectator_join(sender)


@rpc("authority", "reliable")
func _sync_lobby_state(all_players: Dictionary, map_id: String, p_room_name: String = "", p_game_mode: String = "Escape", p_max_players: int = 4):
	players = all_players
	selected_map = map_id
	room_name = p_room_name
	game_mode = p_game_mode
	max_players = clampi(p_max_players, 2, MAX_PLAYERS)
	emit_signal("lobby_updated")


func _send_spectator_join(peer_id: int) -> void:
	var char_map = {}
	for pid in players:
		if not is_spectator(pid):
			char_map[pid] = players[pid].character_id

	var data = {
		"char_map": char_map,
		"map_id": selected_map,
	}

	MatchCoordinator.rpc_id(peer_id, "_join_late_as_spectator", current_phase, data)


func _on_peer_disconnected(peer_id: int):
	if multiplayer.is_server():
		var abandoned_role: String = ""
		var was_spectator := false
		if players.has(peer_id):
			abandoned_role = players[peer_id]["assigned_role"]
			was_spectator = players[peer_id].get("is_spectator", false)
			if forced_killer_peer == peer_id:
				forced_killer_peer = -1

		players.erase(peer_id)
		emit_signal("player_left", peer_id)

		if not was_spectator:
			var game_state = GameServiceLocator.game_state if GameServiceLocator.has_service(ServiceNames.GAME_STATE) else null
			if game_state and game_state.is_in_game():
				game_state.handle_player_disconnect(peer_id, abandoned_role)

		var self_id = multiplayer.get_unique_id()
		for pid in players:
			if pid != self_id:
				rpc_id(pid, "_sync_lobby_state", players, selected_map, room_name, game_mode, max_players)


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


# ── Host admin actions ──

func _broadcast_lobby_state() -> void:
	var self_id = multiplayer.get_unique_id()
	for pid in players:
		if pid != self_id:
			rpc_id(pid, "_sync_lobby_state", players, selected_map, room_name, game_mode, max_players)
	emit_signal("lobby_updated")


func admin_set_spectator(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	if not players.has(peer_id):
		return false
	if players[peer_id].get("is_spectator", false):
		return false
	# Si era el killer forzado, restaurar sus puntos antes
	if forced_killer_peer == peer_id and players[peer_id].has("_prev_killer_points"):
		players[peer_id]["killer_points"] = players[peer_id]["_prev_killer_points"]
		players[peer_id].erase("_prev_killer_points")
		forced_killer_peer = -1
	players[peer_id]["is_spectator"] = true
	players[peer_id]["assigned_role"] = "spectator"
	_broadcast_lobby_state()
	print("[LobbyManager] Peer %d puesto como espectador" % peer_id)
	return true


func admin_set_survivor(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	if not players.has(peer_id):
		return false
	var was_spectator: bool = players[peer_id].get("is_spectator", false)
	var was_spectator_role: bool = players[peer_id].get("assigned_role", "") == "spectator"
	if not was_spectator and not was_spectator_role:
		return false
	players[peer_id]["is_spectator"] = false
	players[peer_id]["assigned_role"] = "survivor"
	_broadcast_lobby_state()
	print("[LobbyManager] Peer %d restaurado a survivor" % peer_id)
	return true


func admin_force_killer(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	if not players.has(peer_id):
		return false
	if players[peer_id].get("is_spectator", false):
		# Quitar de espectador primero
		players[peer_id]["is_spectator"] = false
	# Restaurar puntos del anterior forzado si existe y es distinto
	if forced_killer_peer != -1 and forced_killer_peer != peer_id and players.has(forced_killer_peer):
		if players[forced_killer_peer].has("_prev_killer_points"):
			players[forced_killer_peer]["killer_points"] = players[forced_killer_peer]["_prev_killer_points"]
			players[forced_killer_peer].erase("_prev_killer_points")
		# El anterior vuelve a survivor si sigue en sala
		if players[forced_killer_peer].get("assigned_role", "") == "killer":
			players[forced_killer_peer]["assigned_role"] = "survivor"
	if forced_killer_peer == peer_id and players[peer_id].get("assigned_role", "") == "killer" and players[peer_id].get("killer_points", 0) == 99:
		# Ya es el killer forzado
		return false
	# Guardar puntos previos del nuevo forzado si no estaban guardados
	if not players[peer_id].has("_prev_killer_points"):
		players[peer_id]["_prev_killer_points"] = players[peer_id].get("killer_points", 0)
	players[peer_id]["killer_points"] = 99
	players[peer_id]["assigned_role"] = "killer"
	players[peer_id]["is_spectator"] = false
	forced_killer_peer = peer_id
	# Todos los demas no-espectadores pasan a survivor
	for pid in players:
		if pid == peer_id:
			continue
		if players[pid].get("is_spectator", false):
			continue
		players[pid]["assigned_role"] = "survivor"
	_broadcast_lobby_state()
	print("[LobbyManager] Peer %d forzado como KILLER (99 pts)" % peer_id)
	return true


func admin_kick_player(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	if not players.has(peer_id):
		return false
	var self_id = multiplayer.get_unique_id()
	if peer_id == self_id:
		return false
	print("[LobbyManager] Expulsando peer %d" % peer_id)
	rpc_id(peer_id, "_notify_kicked", "Expulsado por el host")
	# Dar tiempo a que llegue el RPC antes de desconectar
	_do_kick_after_notify(peer_id)
	return true


func _do_kick_after_notify(peer_id: int) -> void:
	await get_tree().create_timer(0.35).timeout
	if not players.has(peer_id):
		return
	if forced_killer_peer == peer_id:
		forced_killer_peer = -1
	var leaving_name: String = players[peer_id].get("name", str(peer_id))
	players.erase(peer_id)
	emit_signal("player_left", peer_id)
	_broadcast_lobby_state()
	var mp_peer = multiplayer.multiplayer_peer
	if mp_peer and mp_peer.has_method("disconnect_peer"):
		mp_peer.disconnect_peer(peer_id)
	print("[LobbyManager] Peer %d (%s) expulsado" % [peer_id, leaving_name])


@rpc("authority", "reliable")
func _notify_kicked(reason: String) -> void:
	if multiplayer.is_server():
		return
	print("[LobbyManager] Fuiste expulsado: ", reason)
	kicked.emit(reason)
	# Mostrar feedback rapido si hay lobby en escena
	await get_tree().create_timer(0.4).timeout
	var mc := get_node_or_null("/root/MatchCoordinator")
	if mc and mc.has_method("reset_to_menu"):
		mc.reset_to_menu()


func clear_forced_killer_state() -> void:
	# Restaura los puntos del jugador forzado al flujo normal (llamado al volver al lobby)
	if forced_killer_peer != -1 and players.has(forced_killer_peer):
		if players[forced_killer_peer].has("_prev_killer_points"):
			# Si _calculate_killer_points ya restauró, este erase es no-op
			var prev = players[forced_killer_peer]["_prev_killer_points"]
			# Solo restaurar si aún está en 99 (no pasó por el cálculo de fin de partida)
			if players[forced_killer_peer].get("killer_points", 0) == 99:
				players[forced_killer_peer]["killer_points"] = prev
			players[forced_killer_peer].erase("_prev_killer_points")
	forced_killer_peer = -1


func get_killer_candidates() -> Array[int]:
	var highest_points: int = -1
	var candidates: Array[int] = []
	for pid in players:
		if is_spectator(pid):
			continue
		var pts: int = int(players[pid].get("killer_points", 0))
		if pts > highest_points:
			highest_points = pts
			candidates = [pid]
		elif pts == highest_points:
			candidates.append(pid)
	return candidates


# ── Character selection flow ──

func host_start_character_selection():
	if not is_host:
		return

	if players.size() < 2:
		print("[LobbyManager] Se necesitan al menos 2 jugadores.")
		return

	current_phase = GamePhase.CHARACTER_SELECT

	var killer_peer_id: int = -1
	# Si hay killer forzado (99 pts) respetar el override inmediato
	if forced_killer_peer != -1 and players.has(forced_killer_peer) and not is_spectator(forced_killer_peer):
		killer_peer_id = forced_killer_peer
	else:
		var candidates: Array[int] = get_killer_candidates()
		if candidates.is_empty():
			print("[LobbyManager] No hay jugadores elegibles para ser killer (todos espectadores).")
			return
		randomize()
		killer_peer_id = candidates[randi() % candidates.size()]

	for pid in players:
		if is_spectator(pid):
			continue
		players[pid]["character_id"] = -1
		if pid == killer_peer_id:
			players[pid]["assigned_role"] = "killer"
		else:
			players[pid]["assigned_role"] = "survivor"

	rpc("_go_to_character_selection", players)


@rpc("authority", "call_local", "reliable")
func _go_to_character_selection(assigned_players: Dictionary):
	current_phase = GamePhase.CHARACTER_SELECT
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

func setup_as_host(player_name: String, map_name: String, p_room_name: String = "", p_game_mode: String = "Escape", p_max_players: int = 4) -> void:
	reset_lobby_state()
	is_host = true
	local_player_name = player_name
	selected_map = map_name
	room_name = p_room_name if p_room_name != "" else player_name
	game_mode = p_game_mode if p_game_mode != "" else "Escape"
	max_players = clampi(p_max_players, 2, MAX_PLAYERS)


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
	current_phase = GamePhase.LOBBY
	forced_killer_peer = -1
