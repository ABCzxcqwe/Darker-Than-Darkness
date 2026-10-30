# res://core/LobbyManager.gd (Autoload)
# Gestiona el estado de la sala: jugadores, roles, selección de personajes.
extends Node

signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)
signal lobby_updated()
signal kicked(reason: String)
## Se emite en el cliente cuando el servidor rechaza una selección de personaje.
signal character_selection_rejected(char_id: int, message: String)

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
var room_host_peer: int = -1
## Solo en el servidor: peers que han reclamado el modo dev (--dev).
## No se sincroniza a los clientes.
var dev_peers: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func is_spectator(peer_id: int) -> bool:
	return players.has(peer_id) and players[peer_id].get("is_spectator", false)


func is_room_host() -> bool:
	return room_host_peer != -1 and room_host_peer == multiplayer.get_unique_id()


## True solo en el servidor si ese peer puede seleccionar personajes dev.
## El host local cuenta como dev si su proceso tiene DevMode activo.
func is_dev_peer(peer_id: int) -> bool:
	if not DevMode.is_enabled():
		return false
	if peer_id == multiplayer.get_unique_id():
		return true
	return dev_peers.has(peer_id)


## Un cliente dev lo llama al conectar. No es una frontera de seguridad
## criptográfica: es una salvaguarda para que un cliente normal conectado a un
## servidor dev no pueda seleccionar personajes de test por accidente.
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
	print("[LobbyManager] Peer %d reclamó modo dev" % sender)


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
		if not is_late_join and room_host_peer == -1:
			room_host_peer = sender
		emit_signal("player_joined", sender, players[sender])

		var self_id = multiplayer.get_unique_id()
		if not is_late_join:
			for pid in players:
				if pid != self_id:
					rpc_id(pid, "_sync_lobby_state", players, selected_map, room_name, game_mode, max_players, room_host_peer)
		else:
			for pid in players:
				if pid != self_id and pid != sender:
					rpc_id(pid, "_sync_lobby_state", players, selected_map, room_name, game_mode, max_players, room_host_peer)
			rpc_id(sender, "_sync_lobby_state", players, selected_map, room_name, game_mode, max_players, room_host_peer)
			_send_spectator_join(sender)


@rpc("authority", "reliable")
func _sync_lobby_state(all_players: Dictionary, map_id: String, p_room_name: String = "", p_game_mode: String = "Escape", p_max_players: int = 4, p_room_host: int = -1):
	players = all_players
	selected_map = map_id
	room_name = p_room_name
	game_mode = p_game_mode
	max_players = clampi(p_max_players, 2, MAX_PLAYERS)
	room_host_peer = p_room_host
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
		dev_peers.erase(peer_id)
		emit_signal("player_left", peer_id)

		if room_host_peer == peer_id:
			room_host_peer = -1
			MatchCoordinator.stop_match_countdown()
			_reassign_room_host()

		if not was_spectator:
			var game_state = GameServiceLocator.game_state if GameServiceLocator.has_service(ServiceNames.GAME_STATE) else null
			if game_state and game_state.is_in_game():
				game_state.handle_player_disconnect(peer_id, abandoned_role)

		var self_id = multiplayer.get_unique_id()
		for pid in players:
			if pid != self_id:
				rpc_id(pid, "_sync_lobby_state", players, selected_map, room_name, game_mode, max_players, room_host_peer)


func _reassign_room_host() -> void:
	if not multiplayer.is_server():
		return
	var candidates: Array[int] = []
	for pid in players:
		if not is_spectator(pid):
			candidates.append(pid)
	candidates.sort()
	room_host_peer = candidates[0] if not candidates.is_empty() else -1


@rpc("any_peer", "reliable")
func request_start_match() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != room_host_peer:
		return
	MatchCoordinator.start_match_countdown()


## Cambio de mapa desde el tablero del hub. Solo el host/sala host puede.
func request_select_map(map_id: String) -> void:
	if multiplayer.is_server():
		_server_select_map(map_id)
	else:
		rpc_id(1, "_server_select_map", map_id)


@rpc("any_peer", "reliable")
func _server_select_map(map_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != room_host_peer and not is_host:
		return
	if not MapRegistry.has_map(map_id):
		return
	if selected_map == map_id:
		return
	selected_map = map_id
	print("[LobbyManager] Mapa de sala cambiado a '%s' por peer %d" % [map_id, sender])
	_broadcast_lobby_state()


@rpc("any_peer", "reliable")
func request_cancel_start() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != room_host_peer:
		return
	MatchCoordinator.stop_match_countdown()


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
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if multiplayer.is_server():
		if players.has(sender):
			var validation := _validate_character_selection(sender, char_id)
			if not validation["ok"]:
				players[sender]["character_id"] = -1
				_reject_selection(sender, char_id, String(validation["reason"]))
				emit_signal("lobby_updated")
				return
			players[sender].character_id = char_id
			emit_signal("lobby_updated")
			rpc("_sync_character", sender, char_id)


@rpc("authority", "reliable")
func _sync_character(peer_id: int, char_id: int):
	if not multiplayer.is_server():
		if players.has(peer_id):
			players[peer_id].character_id = char_id
			emit_signal("lobby_updated")


# ── Host actions ──

func _broadcast_lobby_state() -> void:
	var self_id = multiplayer.get_unique_id()
	for pid in players:
		if pid != self_id:
			rpc_id(pid, "_sync_lobby_state", players, selected_map, room_name, game_mode, max_players, room_host_peer)
	emit_signal("lobby_updated")


func host_set_spectator(peer_id: int) -> bool:
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


func host_set_survivor(peer_id: int) -> bool:
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


func host_force_killer(peer_id: int) -> bool:
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


func host_kick_player(peer_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	if not players.has(peer_id):
		return false
	var self_id = multiplayer.get_unique_id()
	if peer_id == self_id:
		return false
	print("[LobbyManager] Expulsando peer %d" % peer_id)
	# Se envía código, cada cliente lo traduce a su idioma al recibirlo.
	rpc_id(peer_id, "_notify_kicked", "host_kick")
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
	var text := reason
	if reason == "host_kick":
		text = tr("LOBBY_KICK_REASON")
	print("[LobbyManager] Fuiste expulsado: ", text)
	kicked.emit(text)
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
	if not multiplayer.is_server():
		return

	if players.size() < 2 and not DevMode.is_enabled():
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
	MatchCoordinator.start_character_select_timer()


## Rellena con un personaje por defecto a los jugadores no-espectador que no
## eligieron nada. Lo ejecuta el servidor al agotarse el tiempo de selección.
func host_resolve_missing_selections() -> void:
	if not multiplayer.is_server():
		return
	for pid in players:
		if is_spectator(pid):
			continue
		if players[pid].get("character_id", -1) == -1:
			var role: String = players[pid].get("assigned_role", "survivor")
			var fallback := CharacterRegistry.get_fallback(role)
			if fallback:
				players[pid]["character_id"] = fallback.id
				print("[LobbyManager] Auto-selección para peer %d: '%s' (id %d)" % [
					pid, fallback.display_name, fallback.id
				])
			else:
				players[pid]["character_id"] = -1
				push_error("[LobbyManager] No hay fallback normal para peer %d (rol '%s')." % [pid, role])


@rpc("authority", "call_local", "reliable")
func _go_to_character_selection(assigned_players: Dictionary):
	current_phase = GamePhase.CHARACTER_SELECT
	players = assigned_players
	for lobby in get_tree().get_nodes_in_group("lobby"):
		lobby.queue_free()
	# El hub deja de procesar avatares/interacciones mientras dura la partida.
	# En servidor dedicado la escena queda como shell; en clientes se libera
	# igual al cambiar a CharacterSelect.
	for hub in get_tree().get_nodes_in_group("hub_session"):
		if hub.has_method("prepare_for_match"):
			hub.prepare_for_match()
		else:
			hub.queue_free()
	var ds := get_node_or_null("/root/DedicatedServer")
	if not (ds and ds.is_dedicated):
		SceneTransition.change_scene("res://ui/GameUI/Scenes/CharacterSelect.tscn", 0.45, 0.15, 0.6)


@rpc("any_peer", "call_local", "reliable")
func select_character_in_screen(char_id: int):
	var sender_id = multiplayer.get_remote_sender_id()

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
			emit_signal("lobby_updated")
			return

		players[sender_id]["character_id"] = char_id
		print("[Server] Peer %d seleccionó personaje ID: %d" % [sender_id, char_id])
		emit_signal("lobby_updated")
		rpc("_sync_screen_selection", sender_id, char_id,
			String(players[sender_id].get("assigned_role", "survivor")))
	else:
		rpc_id(1, "select_character_in_screen", char_id)


## Valida una selección en el servidor. Devuelve { ok: bool, reason: String }.
## Reglas:
##   - El ID debe existir en el registro (normal o dev).
##   - El equipo debe coincidir con el rol asignado.
##   - Un personaje dev_only solo lo puede elegir un peer dev, y el servidor
##     también debe tener DevMode activo.
##   - Un peer dev puede elegir un personaje test de cualquier bando: el rol
##     se ajusta al equipo del personaje para que spawn/HUD/colisiones sean
##     coherentes. Esto permite probar killer y survivor desde el mismo panel.
func _validate_character_selection(peer_id: int, char_id: int) -> Dictionary:
	var data: CharacterData = CharacterRegistry.get_character(char_id)
	if data == null:
		return {"ok": false, "reason": "invalid"}

	var role: String = String(players[peer_id].get("assigned_role", "survivor")).to_lower().strip_edges()
	var data_team := data.team.to_lower().strip_edges()
	var team_ok := data_team == role

	if data.dev_only:
		if not is_dev_peer(peer_id):
			return {"ok": false, "reason": "not_dev"}
		if not team_ok:
			players[peer_id]["assigned_role"] = data.team
			team_ok = true
			print("[LobbyManager] Dev: peer %d cambia a rol '%s' por personaje test '%s'" % [
				peer_id, data.team, data.display_name
			])

	if not team_ok:
		return {"ok": false, "reason": "team"}

	return {"ok": true, "reason": ""}


func _reject_selection(peer_id: int, char_id: int, reason: String) -> void:
	var message := reason
	match reason:
		"not_dev":
			message = "Personaje de test: se requiere modo dev en el servidor y en el jugador."
		"invalid":
			message = "Personaje inválido."
		"team":
			message = "Ese personaje no pertenece a tu rol."
		"spectator":
			message = "Los espectadores no eligen personaje."
	print("[LobbyManager] Selección rechazada | peer=%d char=%d motivo=%s" % [peer_id, char_id, reason])

	if peer_id == multiplayer.get_unique_id():
		character_selection_rejected.emit(char_id, message)
	else:
		rpc_id(peer_id, "_notify_selection_rejected", char_id, message)


@rpc("authority", "reliable")
func _notify_selection_rejected(char_id: int, message: String) -> void:
	if multiplayer.is_server():
		return
	var my_id := multiplayer.get_unique_id()
	if players.has(my_id) and int(players[my_id].get("character_id", -1)) == char_id:
		players[my_id]["character_id"] = -1
		emit_signal("lobby_updated")
	character_selection_rejected.emit(char_id, message)


@rpc("authority", "reliable")
func _sync_screen_selection(peer_id: int, char_id: int, p_role: String = ""):
	if not multiplayer.is_server():
		if players.has(peer_id):
			players[peer_id]["character_id"] = char_id
			if p_role != "":
				players[peer_id]["assigned_role"] = p_role
			print("[Cliente] Sincronizado: Peer %d ahora es personaje %d (%s)" % [peer_id, char_id, p_role])
			emit_signal("lobby_updated")


# ── Setup / Reset ──

func setup_as_host(player_name: String, map_name: String, p_room_name: String = "", p_game_mode: String = "Escape", p_max_players: int = 4) -> void:
	reset_lobby_state()
	is_host = true
	room_host_peer = 1
	local_player_name = player_name
	selected_map = map_name
	room_name = p_room_name if p_room_name != "" else player_name
	game_mode = p_game_mode if p_game_mode != "" else "Escape"
	max_players = clampi(p_max_players, 2, MAX_PLAYERS)


func setup_as_dedicated(p_room_name: String, map_name: String, p_game_mode: String = "Escape", p_max_players: int = 4) -> void:
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
	dev_peers.clear()
	current_phase = GamePhase.LOBBY
	forced_killer_peer = -1
	room_host_peer = -1
