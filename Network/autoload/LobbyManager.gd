# res://Network/autoload/LobbyManager.gd
extends Node
## Autoload autoritativo del estado de la sala.
##
## El servidor es la única fuente de verdad de `players`. Los clientes reciben
## snapshots públicos (sin claves internas que empiezan con `_`) y envían
## peticiones validadas. `server_peer_id` permite que los clientes hablen con el
## servidor tanto en ENet (id 1) como en Steam (SteamID).

signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)
signal lobby_updated()
signal character_select_started()
signal kicked(reason: String)
## Se emite en el cliente cuando el servidor rechaza una selección de personaje.
signal character_selection_rejected(char_id: int, message: String)

const TAG := "LobbyManager"
const MAX_PLAYERS := NetConfig.MAX_PLAYERS

# Alias: LobbyManager.GamePhase sigue funcionando.
const GamePhase = NetEnums.Phase

var players: Dictionary = {}
var local_player_name: String = ""
## Delegado en SessionState: mapa elegido en el lobby.
var selected_map: String:
	get:
		return SessionState.selected_map
	set(value):
		SessionState.selected_map = value
var room_name: String = ""
var game_mode: String = "Escape"
var max_players: int = 4
var is_host: bool = false
## Delegado en SessionState: fase de la sala/partida.
var current_phase: int:
	get:
		return int(SessionState.phase)
	set(value):
		SessionState.phase = value
var forced_killer_peer: int = -1
var room_host_peer: int = -1
## ID del servidor desde el punto de vista del cliente. Hoy ENet y Steam usan
## `1`; se abstrae para futuros transportes con otro esquema de IDs.
var server_peer_id: int = 1
## Delegado en SessionState: peers que entraron a la ronda actual.
var match_participants: Array[int]:
	get:
		return SessionState.participants
	set(value):
		SessionState.participants = value
## Solo en el servidor: peers que han reclamado el modo dev (--dev).
var dev_peers: Dictionary = {}


func _ready() -> void:
	randomize()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func is_spectator(peer_id: int) -> bool:
	return players.has(peer_id) and bool(players[peer_id].get("is_spectator", false))


func is_afk(peer_id: int) -> bool:
	return players.has(peer_id) and bool(players[peer_id].get("afk", false))


## "hub" | "match" | "spectate".
func is_in_hub(peer_id: int) -> bool:
	return players.has(peer_id) and str(players[peer_id].get("presence", PlayerInfo.PRESENCE_HUB)) == PlayerInfo.PRESENCE_HUB


func set_local_presence(presence: String) -> void:
	if presence not in [PlayerInfo.PRESENCE_HUB, PlayerInfo.PRESENCE_MATCH, PlayerInfo.PRESENCE_SPECTATE]:
		return
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_apply_presence(multiplayer.get_unique_id(), presence)
	else:
		rpc_id(server_peer_id, "_server_set_presence", presence)


@rpc("any_peer", "reliable")
func _server_set_presence(presence: String) -> void:
	if not multiplayer.is_server():
		return
	if presence not in [PlayerInfo.PRESENCE_HUB, PlayerInfo.PRESENCE_MATCH, PlayerInfo.PRESENCE_SPECTATE]:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	_apply_presence(sender, presence)


func _apply_presence(peer_id: int, presence: String) -> void:
	if not players.has(peer_id):
		return
	players[peer_id]["presence"] = presence
	_broadcast_lobby_state()


func apply_match_presence(char_map: Dictionary) -> void:
	for pid in players:
		players[pid]["presence"] = (
			PlayerInfo.PRESENCE_MATCH if char_map.has(int(pid)) else PlayerInfo.PRESENCE_HUB
		)
	lobby_updated.emit()


func is_match_participant(peer_id: int) -> bool:
	return match_participants.has(peer_id)


func can_local_toggle_afk() -> bool:
	return true


## Peers que pueden entrar a la próxima ronda.
func get_active_participants() -> Array[int]:
	var out: Array[int] = []
	for pid in players:
		if is_spectator(pid) or is_afk(pid):
			continue
		out.append(int(pid))
	return out


## Regla única de "se puede iniciar". En builds de prueba se permite 1
## jugador para poder validar mapas/controles sin un segundo peer.
func can_start_match() -> bool:
	return get_active_participants().size() >= 2 or DevMode.allows_solo_match()


func request_toggle_afk() -> void:
	if multiplayer.is_server():
		_server_toggle_afk()
	else:
		rpc_id(server_peer_id, "_server_toggle_afk")


@rpc("any_peer", "reliable")
func _server_toggle_afk() -> void:
	if not multiplayer.is_server():
		return
	if current_phase != GamePhase.LOBBY:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if not players.has(sender) or is_spectator(sender):
		return
	players[sender]["afk"] = not bool(players[sender].get("afk", false))
	_broadcast_lobby_state()


func is_room_host() -> bool:
	return room_host_peer != -1 and room_host_peer == multiplayer.get_unique_id()


## True solo en el servidor si ese peer puede seleccionar personajes dev.
func is_dev_peer(peer_id: int) -> bool:
	if not DevMode.is_enabled():
		return false
	if peer_id == multiplayer.get_unique_id():
		return true
	return dev_peers.has(peer_id)


## Un cliente dev lo llama al conectar. Es una salvaguarda para tests, no una
## frontera criptográfica: un servidor dev no debe ser público.
@rpc("any_peer", "reliable")
func claim_dev_mode() -> void:
	if not multiplayer.is_server():
		return
	if not DevMode.is_enabled():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or dev_peers.has(sender):
		return
	dev_peers[sender] = true
	NetLog.debug(TAG, "Peer %d reclamó modo dev" % sender)


# ── Peer management ──

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	rpc_id(peer_id, "_request_player_info")


@rpc("authority", "reliable")
func _request_player_info() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0:
		server_peer_id = sender
	rpc_id(server_peer_id, "_send_player_info", local_player_name)


@rpc("any_peer", "reliable")
func _send_player_info(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var safe_name := PlayerInfo.sanitize_name(player_name, "Player %d" % sender)

	# Reenvíos: solo se permite actualizar el nombre y solo en el lobby.
	if players.has(sender):
		if current_phase != GamePhase.LOBBY:
			NetLog.warn(TAG, "Peer %d intentó reenviar player_info fuera del lobby" % sender)
			return
		players[sender]["name"] = safe_name
		_broadcast_lobby_state()
		return

	var is_full := players.size() >= max_players
	var is_late_join := current_phase != GamePhase.LOBBY or is_full
	players[sender] = PlayerInfo.make(safe_name, false, is_late_join)
	if not is_late_join and room_host_peer == -1:
		room_host_peer = sender
	player_joined.emit(sender, PlayerInfo.public_entry(players[sender]))
	_broadcast_lobby_state()
	if is_late_join:
		_send_spectator_join(sender)


@rpc("authority", "reliable")
func _sync_lobby_state(
	all_players: Dictionary,
	map_id: String,
	p_room_name: String = "",
	p_game_mode: String = "Escape",
	p_max_players: int = 4,
	p_room_host: int = -1,
	p_server_peer_id: int = 1
) -> void:
	players = all_players
	selected_map = map_id
	room_name = p_room_name
	game_mode = p_game_mode
	max_players = clampi(p_max_players, 2, MAX_PLAYERS)
	room_host_peer = p_room_host
	server_peer_id = p_server_peer_id
	lobby_updated.emit()


func _send_spectator_join(peer_id: int) -> void:
	var char_map: Dictionary = {}
	if not MatchCoordinator.current_match_char_map.is_empty():
		char_map = MatchCoordinator.current_match_char_map.duplicate()
	else:
		for pid in players:
			if is_spectator(pid) or is_afk(pid):
				continue
			char_map[pid] = players[pid]["character_id"]

	var data := {
		"char_map": char_map,
		"map_id": MatchCoordinator.current_match_map_id if MatchCoordinator.current_match_map_id != "" else selected_map,
	}
	MatchCoordinator.rpc_id(peer_id, "_join_late_as_spectator", current_phase, data)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var abandoned_role := ""
	var was_spectator := false
	if players.has(peer_id):
		abandoned_role = String(players[peer_id].get("assigned_role", PlayerInfo.ROLE_SURVIVOR))
		was_spectator = bool(players[peer_id].get("is_spectator", false))
		if forced_killer_peer == peer_id:
			forced_killer_peer = -1

	players.erase(peer_id)
	dev_peers.erase(peer_id)
	player_left.emit(peer_id)

	if room_host_peer == peer_id:
		room_host_peer = -1
		MatchCoordinator.stop_match_countdown()
		_reassign_room_host()

	if not was_spectator:
		var game_state = GameServiceLocator.game_state if GameServiceLocator.has_service(ServiceNames.GAME_STATE) else null
		if game_state and game_state.is_in_game():
			game_state.handle_player_disconnect(peer_id, abandoned_role)

	_broadcast_lobby_state()


func _reassign_room_host() -> void:
	if not multiplayer.is_server():
		return
	var candidates: Array[int] = []
	for pid in players:
		if not is_spectator(pid):
			candidates.append(int(pid))
	candidates.sort()
	room_host_peer = candidates[0] if not candidates.is_empty() else -1
	NetLog.debug(TAG, "Nuevo room host: %d" % room_host_peer)


# ── Peticiones del host/sala ──

func request_start() -> void:
	if multiplayer.is_server():
		request_start_match()
	else:
		rpc_id(server_peer_id, "request_start_match")


func request_cancel() -> void:
	if multiplayer.is_server():
		request_cancel_start()
	else:
		rpc_id(server_peer_id, "request_cancel_start")


@rpc("any_peer", "reliable")
func request_start_match() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != room_host_peer:
		return
	MatchCoordinator.start_match_countdown()


func request_select_map(map_id: String) -> void:
	if multiplayer.is_server():
		_server_select_map(map_id)
	else:
		rpc_id(server_peer_id, "_server_select_map", map_id)


@rpc("any_peer", "reliable")
func _server_select_map(map_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	# El servidor mismo también puede cambiar el mapa (útil en dedicado).
	if sender != room_host_peer and sender != multiplayer.get_unique_id():
		return
	if not MapRegistry.has_map(map_id):
		return
	if selected_map == map_id:
		return
	selected_map = map_id
	NetLog.info(TAG, "Mapa de sala cambiado a '%s' por peer %d" % [map_id, sender])
	_broadcast_lobby_state()


func request_set_max_players(value: int) -> void:
	if multiplayer.is_server():
		_server_set_max_players(value)
	else:
		rpc_id(server_peer_id, "_server_set_max_players", value)


@rpc("any_peer", "reliable")
func _server_set_max_players(value: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != room_host_peer:
		return
	max_players = clampi(value, 2, MAX_PLAYERS)
	_broadcast_lobby_state()


@rpc("any_peer", "reliable")
func request_cancel_start() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != room_host_peer:
		return
	MatchCoordinator.stop_match_countdown()


# ── Lista de jugadores ──

func get_player_list() -> Array:
	var list: Array = []
	for id in players:
		var info := PlayerInfo.public_entry(players[id])
		info["id"] = id
		list.append(info)
	return list


func get_local_character() -> int:
	var my_id := multiplayer.get_unique_id()
	if players.has(my_id):
		return int(players[my_id].get("character_id", -1))
	return -1


func set_my_character(char_id: int) -> void:
	var my_id := multiplayer.get_unique_id()
	if not players.has(my_id):
		return
	players[my_id]["character_id"] = char_id
	if is_host:
		lobby_updated.emit()
	else:
		rpc_id(server_peer_id, "_update_character", char_id)


@rpc("any_peer", "call_local")
func _update_character(char_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if not multiplayer.is_server():
		return
	if not players.has(sender):
		return
	var validation := _validate_character_selection(sender, char_id)
	if not validation["ok"]:
		players[sender]["character_id"] = -1
		_reject_selection(sender, char_id, String(validation["reason"]))
		lobby_updated.emit()
		return
	players[sender]["character_id"] = char_id
	lobby_updated.emit()
	rpc("_sync_character", sender, char_id)


@rpc("authority", "reliable")
func _sync_character(peer_id: int, char_id: int) -> void:
	if not multiplayer.is_server() and players.has(peer_id):
		players[peer_id]["character_id"] = char_id
		lobby_updated.emit()


# ── Estado de sala ──

func _broadcast_lobby_state() -> void:
	var snapshot := PlayerInfo.public_copy(players)
	var self_id := multiplayer.get_unique_id()
	for pid in players:
		if pid != self_id:
			rpc_id(
				pid,
				"_sync_lobby_state",
				snapshot,
				selected_map,
				room_name,
				game_mode,
				max_players,
				room_host_peer,
				server_peer_id
			)
	lobby_updated.emit()


# ── Acciones del host ──

func host_set_spectator(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	if not players.has(peer_id):
		return false
	if players[peer_id].get("is_spectator", false):
		return false
	# Si era el killer forzado, restaurar sus puntos.
	if forced_killer_peer == peer_id and players[peer_id].has("_prev_killer_points"):
		players[peer_id]["killer_points"] = players[peer_id]["_prev_killer_points"]
		players[peer_id].erase("_prev_killer_points")
		forced_killer_peer = -1
	players[peer_id]["is_spectator"] = true
	players[peer_id]["assigned_role"] = PlayerInfo.ROLE_SPECTATOR
	players[peer_id]["afk"] = false
	_broadcast_lobby_state()
	return true


func host_set_survivor(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	if not players.has(peer_id):
		return false
	var was_spectator: bool = players[peer_id].get("is_spectator", false)
	var was_spectator_role: bool = players[peer_id].get("assigned_role", "") == PlayerInfo.ROLE_SPECTATOR
	if not was_spectator and not was_spectator_role:
		return false
	players[peer_id]["is_spectator"] = false
	players[peer_id]["assigned_role"] = PlayerInfo.ROLE_SURVIVOR
	players[peer_id]["afk"] = false
	_broadcast_lobby_state()
	return true


func host_force_killer(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	if not players.has(peer_id):
		return false
	if players[peer_id].get("is_spectator", false):
		players[peer_id]["is_spectator"] = false
	# Restaurar al killer forzado anterior.
	if forced_killer_peer != -1 and forced_killer_peer != peer_id and players.has(forced_killer_peer):
		if players[forced_killer_peer].has("_prev_killer_points"):
			players[forced_killer_peer]["killer_points"] = players[forced_killer_peer]["_prev_killer_points"]
			players[forced_killer_peer].erase("_prev_killer_points")
		if players[forced_killer_peer].get("assigned_role", "") == PlayerInfo.ROLE_KILLER:
			players[forced_killer_peer]["assigned_role"] = PlayerInfo.ROLE_SURVIVOR
	if (
		forced_killer_peer == peer_id
		and players[peer_id].get("assigned_role", "") == PlayerInfo.ROLE_KILLER
		and players[peer_id].get("killer_points", 0) == 99
	):
		return false
	if not players[peer_id].has("_prev_killer_points"):
		players[peer_id]["_prev_killer_points"] = players[peer_id].get("killer_points", 0)
	players[peer_id]["killer_points"] = 99
	players[peer_id]["assigned_role"] = PlayerInfo.ROLE_KILLER
	players[peer_id]["is_spectator"] = false
	players[peer_id]["afk"] = false
	forced_killer_peer = peer_id
	for pid in players:
		if pid == peer_id:
			continue
		if players[pid].get("is_spectator", false):
			continue
		players[pid]["assigned_role"] = PlayerInfo.ROLE_SURVIVOR
	_broadcast_lobby_state()
	return true


func host_kick_player(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	if not players.has(peer_id):
		return false
	if peer_id == multiplayer.get_unique_id():
		return false
	rpc_id(peer_id, "_notify_kicked", "host_kick")
	_do_kick_after_notify(peer_id)
	return true


# ── Acciones de host desde cliente (sala dedicada) ──

func request_set_spectator(peer_id: int) -> bool:
	if multiplayer.is_server():
		return host_set_spectator(peer_id)
	rpc_id(server_peer_id, "_server_set_spectator", peer_id)
	return true


func request_set_survivor(peer_id: int) -> bool:
	if multiplayer.is_server():
		return host_set_survivor(peer_id)
	rpc_id(server_peer_id, "_server_set_survivor", peer_id)
	return true


func request_force_killer(peer_id: int) -> bool:
	if multiplayer.is_server():
		return host_force_killer(peer_id)
	rpc_id(server_peer_id, "_server_force_killer", peer_id)
	return true


func request_kick(peer_id: int) -> bool:
	if multiplayer.is_server():
		return host_kick_player(peer_id)
	rpc_id(server_peer_id, "_server_kick", peer_id)
	return true


@rpc("any_peer", "reliable")
func _server_set_spectator(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _remote_sender() != room_host_peer:
		return
	host_set_spectator(peer_id)


@rpc("any_peer", "reliable")
func _server_set_survivor(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _remote_sender() != room_host_peer:
		return
	host_set_survivor(peer_id)


@rpc("any_peer", "reliable")
func _server_force_killer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _remote_sender() != room_host_peer:
		return
	host_force_killer(peer_id)


@rpc("any_peer", "reliable")
func _server_kick(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _remote_sender() != room_host_peer:
		return
	host_kick_player(peer_id)


func _remote_sender() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return sender if sender != 0 else multiplayer.get_unique_id()


func _do_kick_after_notify(peer_id: int) -> void:
	await get_tree().create_timer(NetConfig.KICK_NOTIFY_DELAY).timeout
	if not players.has(peer_id):
		return
	if forced_killer_peer == peer_id:
		forced_killer_peer = -1
	players.erase(peer_id)
	player_left.emit(peer_id)
	_broadcast_lobby_state()
	var mp_peer = multiplayer.multiplayer_peer
	if mp_peer and mp_peer.has_method("disconnect_peer"):
		mp_peer.disconnect_peer(peer_id)


@rpc("authority", "reliable")
func _notify_kicked(reason: String) -> void:
	if multiplayer.is_server():
		return
	var text := _tr_or("LOBBY_KICK_REASON", "Fuiste expulsado por el host.") if reason == "host_kick" else reason
	kicked.emit(text)
	await get_tree().create_timer(NetConfig.KICK_RESET_DELAY).timeout
	var mc := get_node_or_null("/root/MatchCoordinator")
	if mc and mc.has_method("reset_to_menu"):
		mc.reset_to_menu()


func clear_forced_killer_state() -> void:
	if forced_killer_peer != -1 and players.has(forced_killer_peer):
		if players[forced_killer_peer].has("_prev_killer_points"):
			var prev = players[forced_killer_peer]["_prev_killer_points"]
			if players[forced_killer_peer].get("killer_points", 0) == 99:
				players[forced_killer_peer]["killer_points"] = prev
			players[forced_killer_peer].erase("_prev_killer_points")
	forced_killer_peer = -1


func get_killer_candidates() -> Array[int]:
	var highest_points: int = -1
	var candidates: Array[int] = []
	for pid in players:
		if is_spectator(pid) or is_afk(pid):
			continue
		var pts: int = int(players[pid].get("killer_points", 0))
		if pts > highest_points:
			highest_points = pts
			candidates = [pid]
		elif pts == highest_points:
			candidates.append(pid)
	return candidates


# ── Selección de personaje ──

func host_start_character_selection() -> void:
	if not multiplayer.is_server():
		return

	var active := get_active_participants()
	if not can_start_match():
		return

	var killer_peer_id: int = -1
	if (
		forced_killer_peer != -1
		and players.has(forced_killer_peer)
		and not is_spectator(forced_killer_peer)
		and not is_afk(forced_killer_peer)
	):
		killer_peer_id = forced_killer_peer
	else:
		var candidates := get_killer_candidates()
		if candidates.is_empty():
			return
		killer_peer_id = candidates[randi_range(0, candidates.size() - 1)]

	current_phase = GamePhase.CHARACTER_SELECT
	match_participants = active.duplicate()

	for pid in players:
		if is_spectator(pid) or is_afk(pid):
			players[pid]["presence"] = PlayerInfo.PRESENCE_HUB
			continue
		players[pid]["character_id"] = -1
		players[pid]["presence"] = PlayerInfo.PRESENCE_MATCH
		if pid == killer_peer_id:
			players[pid]["assigned_role"] = PlayerInfo.ROLE_KILLER
		else:
			players[pid]["assigned_role"] = PlayerInfo.ROLE_SURVIVOR

	# Local con el diccionario completo; a los clientes va la copia pública.
	_go_to_character_selection(players, match_participants)
	rpc("_go_to_character_selection", PlayerInfo.public_copy(players), match_participants)
	MatchCoordinator.start_character_select_timer()


func host_resolve_missing_selections() -> void:
	if not multiplayer.is_server():
		return
	for pid in players:
		if is_spectator(pid) or is_afk(pid):
			continue
		if int(players[pid].get("character_id", -1)) == -1:
			var role: String = String(players[pid].get("assigned_role", PlayerInfo.ROLE_SURVIVOR))
			var fallback = CharacterRegistry.get_fallback(role)
			if fallback:
				players[pid]["character_id"] = fallback.id
			else:
				players[pid]["character_id"] = -1


@rpc("authority", "reliable")
func _go_to_character_selection(assigned_players: Dictionary, participants: Array = []) -> void:
	current_phase = GamePhase.CHARACTER_SELECT
	players = assigned_players
	match_participants.clear()
	for pid in participants:
		match_participants.append(int(pid))
	if match_participants.is_empty():
		match_participants = get_active_participants()
	character_select_started.emit()


@rpc("any_peer", "call_local", "reliable")
func select_character_in_screen(char_id: int) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	if multiplayer.is_server():
		if not players.has(sender_id):
			return
		if is_spectator(sender_id):
			_reject_selection(sender_id, char_id, "spectator")
			return
		var validation := _validate_character_selection(sender_id, char_id)
		if not validation["ok"]:
			players[sender_id]["character_id"] = -1
			_reject_selection(sender_id, char_id, String(validation["reason"]))
			lobby_updated.emit()
			return
		players[sender_id]["character_id"] = char_id
		lobby_updated.emit()
		rpc(
			"_sync_screen_selection",
			sender_id,
			char_id,
			String(players[sender_id].get("assigned_role", PlayerInfo.ROLE_SURVIVOR))
		)
	else:
		rpc_id(server_peer_id, "select_character_in_screen", char_id)


## Valida una selección en el servidor: existe, coincide el equipo y, si es
## dev_only, el peer y el servidor deben estar en modo dev.
func _validate_character_selection(peer_id: int, char_id: int) -> Dictionary:
	var data: CharacterData = CharacterRegistry.get_character(char_id)
	if data == null:
		return {"ok": false, "reason": "invalid"}

	var role: String = String(players[peer_id].get("assigned_role", PlayerInfo.ROLE_SURVIVOR)).to_lower().strip_edges()
	var data_team := data.team.to_lower().strip_edges()
	var team_ok := data_team == role

	if data.dev_only:
		if not is_dev_peer(peer_id):
			return {"ok": false, "reason": "not_dev"}
		if not team_ok:
			players[peer_id]["assigned_role"] = data.team
			team_ok = true

	if not team_ok:
		return {"ok": false, "reason": "team"}

	return {"ok": true, "reason": ""}


func _reject_selection(peer_id: int, char_id: int, reason: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		character_selection_rejected.emit(char_id, _reason_text(reason))
	else:
		rpc_id(peer_id, "_notify_selection_rejected", char_id, reason)


@rpc("authority", "reliable")
func _notify_selection_rejected(char_id: int, reason: String) -> void:
	if multiplayer.is_server():
		return
	var my_id := multiplayer.get_unique_id()
	if players.has(my_id) and int(players[my_id].get("character_id", -1)) == char_id:
		players[my_id]["character_id"] = -1
		lobby_updated.emit()
	character_selection_rejected.emit(char_id, _reason_text(reason))


@rpc("authority", "reliable")
func _sync_screen_selection(peer_id: int, char_id: int, p_role: String = "") -> void:
	if not multiplayer.is_server() and players.has(peer_id):
		players[peer_id]["character_id"] = char_id
		if p_role != "":
			players[peer_id]["assigned_role"] = p_role
		lobby_updated.emit()


func _reason_text(reason: String) -> String:
	match reason:
		"not_dev":
			return _tr_or("CHARACTER_REJECT_NOT_DEV", "Personaje de test: se requiere modo dev en el servidor y en el jugador.")
		"invalid":
			return _tr_or("CHARACTER_REJECT_INVALID", "Personaje inválido.")
		"team":
			return _tr_or("CHARACTER_REJECT_TEAM", "Ese personaje no pertenece a tu rol.")
		"spectator":
			return _tr_or("CHARACTER_REJECT_SPECTATOR", "Los espectadores no eligen personaje.")
		_:
			return _tr_or("CHARACTER_REJECT_UNKNOWN", "Selección rechazada.")


func _tr_or(key: String, fallback: String) -> String:
	var text := tr(key)
	return fallback if text == key else text


# ── Setup / Reset ──

## Llamado por NetworkManager después de crear el peer del servidor (LAN o
## Steam). En dedicado NO se llama: el primer cliente será room host.
func on_server_ready() -> void:
	if not multiplayer.is_server():
		return
	server_peer_id = multiplayer.get_unique_id()
	room_host_peer = server_peer_id
	NetLog.debug(TAG, "Room host asignado al servidor (peer %d)" % room_host_peer)


func setup_as_host(
	player_name: String,
	map_name: String,
	p_room_name: String = "",
	p_game_mode: String = "Escape",
	p_max_players: int = 4
) -> void:
	reset_lobby_state()
	is_host = true
	local_player_name = player_name
	selected_map = map_name
	room_name = p_room_name if p_room_name != "" else player_name
	game_mode = p_game_mode if p_game_mode != "" else "Escape"
	max_players = clampi(p_max_players, 2, MAX_PLAYERS)


func setup_as_dedicated(
	p_room_name: String,
	map_name: String,
	p_game_mode: String = "Escape",
	p_max_players: int = 4
) -> void:
	reset_lobby_state()
	is_host = true
	local_player_name = ""
	selected_map = map_name
	room_name = p_room_name if p_room_name != "" else "Servidor Dedicado"
	game_mode = p_game_mode if p_game_mode != "" else "Escape"
	max_players = clampi(p_max_players, 2, MAX_PLAYERS)


func setup_as_client(player_name: String) -> void:
	is_host = false
	local_player_name = player_name
	server_peer_id = 1
	reset_lobby_state()


func register_local_player(peer_id: int, player_name: String) -> void:
	players[peer_id] = PlayerInfo.make(player_name, is_host)
	player_joined.emit(peer_id, PlayerInfo.public_entry(players[peer_id]))


func reset_lobby_state() -> void:
	players.clear()
	dev_peers.clear()
	SessionState.clear_match()
	current_phase = GamePhase.LOBBY
	forced_killer_peer = -1
	room_host_peer = -1


## Reset completo de sesión. Lo usan NetworkManager y MatchCoordinator al
## desconectar o volver al menú.
func reset_session() -> void:
	reset_lobby_state()
	is_host = false
	local_player_name = ""
	selected_map = ""
	room_name = ""
	game_mode = "Escape"
	max_players = 4
	server_peer_id = 1
