# res://core/NetworkManager.gd
extends Node

enum NetworkMode { LAN, STEAM }

const MAX_PLAYERS := 5
const PORT := 4242

signal connection_succeeded()
signal connection_failed()
signal server_disconnected()
signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)
signal lobby_updated()
signal steam_lobby_list_updated(lobbies: Array)


var peer: MultiplayerPeer
var players: Dictionary = {}        # peer_id -> { name, is_host, character_id, killer_points, assigned_role }
var local_player_name: String = ""
var selected_map: String = ""
var is_host: bool = false
var network_mode: NetworkMode = NetworkMode.LAN
var steam_lobby_id: int = 0
var _disconnecting := false

var _steam: Variant = null
var _steam_ready := false

func _process(_delta: float):
	if _steam:
		_steam.run_callbacks()

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connect_fail)
	multiplayer.server_disconnected.connect(_on_internal_server_disconnected)
	_steam = Engine.get_singleton("Steam")
	if _steam:
		_init_steam_once()

func _init_steam_once():
	print("[NetworkManager] Inicializando Steam...")
	var init_result = _steam.steamInit()
	if typeof(init_result) == TYPE_DICTIONARY:
		var status = init_result.get("status", -1)
		if status != _steam.STEAM_API_INIT_RESULT_OK:
			print("[NetworkManager] Steam init falló (status=" + str(status) + "): ", init_result)
			return
	elif typeof(init_result) == TYPE_BOOL:
		if not init_result:
			print("[NetworkManager] Steam init devolvió false")
			print("[NetworkManager] Verificá que steam_appid.txt exista o configura el App ID en Project Settings > Steam")
			return
	else:
		print("[NetworkManager] Resultado inesperado de steamInit: ", typeof(init_result))
		return
	if not _steam.isSteamRunning():
		print("[NetworkManager] Steam está inicializado pero el cliente Steam no responde")
		return
	_steam.lobby_created.connect(_on_steam_lobby_created)
	_steam.lobby_joined.connect(_on_steam_lobby_joined)
	_steam.lobby_match_list.connect(_on_steam_lobby_list)
	_steam.lobby_chat_update.connect(_on_steam_lobby_chat_update)
	_steam_ready = true
	print("[NetworkManager] Steam listo para usar")

func initialize_steam() -> bool:
	if not _steam:
		print("[NetworkManager] GodotSteam no está instalado")
		return false
	if not _steam_ready:
		print("[NetworkManager] Steam no se pudo inicializar. Revisá la consola para más detalles.")
		return false
	network_mode = NetworkMode.STEAM
	print("[NetworkManager] Modo Steam activado")
	return true

func is_steam_ready() -> bool:
	return _steam_ready

func set_lan_mode():
	network_mode = NetworkMode.LAN

func _on_internal_server_disconnected():
	if _disconnecting:
		return
	_disconnecting = true
	print("Servidor interno desconectado")
	emit_signal("server_disconnected")
	
func create_server(player_name: String, map_name: String) -> bool:
	_disconnecting = false
	local_player_name = player_name
	selected_map = map_name
	is_host = true

	if network_mode == NetworkMode.LAN:
		peer = ENetMultiplayerPeer.new()
		var err = peer.create_server(PORT, MAX_PLAYERS)
		if err != OK:
			print("Error al crear servidor: ", err)
			return false
	else:
		if not _steam_ready:
			print("[NetworkManager] Steam API no inicializada. Usá modo LAN.")
			return false
		print("[NetworkManager] Creando lobby Steam...")
		_steam.createLobby(_steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)
		return true

	multiplayer.multiplayer_peer = peer

	var my_id = multiplayer.get_unique_id()
	players[my_id] = {
		"name": player_name,
		"is_host": true,
		"character_id": -1,
		"killer_points": 0,
		"assigned_role": "survivor"
	}
	
	emit_signal("player_joined", my_id, players[my_id])
	emit_signal("connection_succeeded")
	return true

func join_server(player_name: String, ip_or_lobby_id = "127.0.0.1") -> bool:
	_disconnecting = false
	local_player_name = player_name
	is_host = false

	if network_mode == NetworkMode.LAN:
		peer = ENetMultiplayerPeer.new()
		var err = peer.create_client(ip_or_lobby_id as String, PORT)
		if err != OK:
			print("Error al conectar: ", err)
			return false
		multiplayer.multiplayer_peer = peer
		return true
	else:
		if not _steam_ready:
			print("[NetworkManager] Steam API no inicializada")
			return false
		var lobby_id = ip_or_lobby_id as int
		_steam.joinLobby(lobby_id)
		return true

const GAME_ID_FILTER := "darker_than_darkness"

func request_lobby_list():
	if _steam_ready:
		_steam.addRequestLobbyListResultCountFilter(MAX_LOBBIES)
		_steam.addRequestLobbyListDistanceFilter(_steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
		_steam.addRequestLobbyListStringFilter("game_id", GAME_ID_FILTER, _steam.LOBBY_COMPARISON_EQUAL)
		_steam.requestLobbyList()

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

# ── SECCIÓN DE SELECCIÓN DE PERSONAJES Y FLUJO ASIMÉTRICO ──

## El botón "Iniciar" del Lobby ahora debe llamar a ESTA función en lugar de start_game
func host_start_character_selection():
	if not is_host: return
	
	if players.size() < 2:
		print("[NetworkManager] Se necesitan al menos 2 jugadores.")
		return

	randomize()

	# Sorteo por puntos acumulados
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
	
	# Configurar roles iniciales e indicar que nadie ha elegido personaje (-1)
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
	# Borrar la UI del Lobby viejo si se encuentra activa
	for lobby in get_tree().get_nodes_in_group("lobby"):
		lobby.queue_free()
	get_tree().change_scene_to_file("res://ui/GameUI/Scenes/CharacterSelect.tscn")

## Llamado por cada jugador desde la pantalla de selección para asegurar su personaje
@rpc("any_peer", "call_local", "reliable")
func select_character_in_screen(char_id: int):
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Si es 0, la llamada se originó en esta misma computadora
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	# REGLA DE RED: Solo el servidor procesa y distribuye el estado oficial
	if multiplayer.is_server():
		if players.has(sender_id):
			players[sender_id]["character_id"] = char_id
			print("[Server] Peer %d seleccionó personaje ID: %d" % [sender_id, char_id])
			
			# El servidor actualiza su propia interfaz
			emit_signal("lobby_updated")
			
			# El servidor le grita a TODOS los clientes la actualización del bando
			rpc("_sync_screen_selection", sender_id, char_id)
	else:
		# Si un cliente pulsó el botón, le envía un reporte directo y exclusivo al Servidor (ID 1)
		rpc_id(1, "select_character_in_screen", char_id)
		
## RPC de apoyo: Los clientes reciben la verdad absoluta desde el Servidor
@rpc("authority", "reliable")
func _sync_screen_selection(peer_id: int, char_id: int):
	# Evitamos que el servidor lo procese doble, esto es solo para los clientes
	if not multiplayer.is_server():
		if players.has(peer_id):
			players[peer_id]["character_id"] = char_id
			print("[Cliente] Sincronizado: Peer %d ahora es personaje %d" % [peer_id, char_id])
			emit_signal("lobby_updated")

# ── SEÑALES INTERNAS DE PEERS Y RED ──

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
		# Averiguamos qué rol tenía el jugador antes de borrarlo
		var abandoned_role: String = ""
		if players.has(peer_id):
			abandoned_role = players[peer_id]["assigned_role"]
		
		# Borramos al jugador del diccionario de red
		players.erase(peer_id)
		emit_signal("player_left", peer_id)
		
		# NOTIFICACIÓN AL GAMESTATE: Si la partida está activa, informamos la desconexión
		var game_state = GameServiceLocator.get_service("GameStateService") if GameServiceLocator.has_service("GameStateService") else null
		if game_state and game_state.is_in_game():
			game_state.handle_player_disconnect(peer_id, abandoned_role)
		
		# Sincronizamos al resto de clientes que quedan
		var self_id = multiplayer.get_unique_id()
		for pid in players:
			if pid != self_id:
				rpc_id(pid, "_sync_lobby_state", players, selected_map)

func _on_connected_ok():
	emit_signal("connection_succeeded")

func _on_connect_fail():
	emit_signal("connection_failed")

const MAX_LOBBIES := 16

# ── STEAM CALLBACKS ──

func _on_steam_lobby_created(connect_or_result: int, lobby_id: int):
	print("[Steam] Callback lobby_created -> result:", connect_or_result, " lobby_id:", lobby_id)
	if connect_or_result == 1 and lobby_id != 0:
		steam_lobby_id = lobby_id
		print("[Steam] Lobby creado exitosamente! ID:", lobby_id)
		_steam.setLobbyData(lobby_id, "name", local_player_name)
		_steam.setLobbyData(lobby_id, "map", selected_map)
		_steam.setLobbyData(lobby_id, "game_id", GAME_ID_FILTER)
		_steam.setLobbyJoinable(lobby_id, true)
		_steam.setLobbyType(lobby_id, _steam.LOBBY_TYPE_PUBLIC)
		_steam.allowP2PPacketRelay(true)

		peer = SteamMultiplayerPeer.new()
		var err = peer.host_with_lobby(lobby_id)
		if err != OK:
			print("[Steam] Error en host_with_lobby: ", err)
			emit_signal("connection_failed")
			return
		multiplayer.multiplayer_peer = peer

		var my_id = multiplayer.get_unique_id()
		players[my_id] = {
			"name": local_player_name,
			"is_host": true,
			"character_id": -1,
			"killer_points": 0,
			"assigned_role": "survivor"
		}
		emit_signal("player_joined", my_id, players[my_id])
		emit_signal("connection_succeeded")
	else:
		print("[Steam] Error al crear lobby, código:", connect_or_result)
		emit_signal("connection_failed")

func _on_steam_lobby_joined(lobby_id: int, _perm: int, _locked: bool, response: int):
	print("[Steam] Callback lobby_joined -> lobby:", lobby_id, " response:", response)
	if response == _steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		steam_lobby_id = lobby_id
		if is_host or _steam.getLobbyOwner(lobby_id) == _steam.getSteamID():
			print("[Steam] Somos el host, ignoramos lobby_joined para connect")
			return
		print("[Steam] Conectando al lobby como cliente...")
		_steam.allowP2PPacketRelay(true)
		peer = SteamMultiplayerPeer.new()
		var err = peer.connect_to_lobby(lobby_id)
		if err != OK:
			print("[Steam] Error en connect_to_lobby: ", err)
			emit_signal("connection_failed")
			return
		multiplayer.multiplayer_peer = peer
		emit_signal("connection_succeeded")
	else:
		print("[Steam] Error al unirse al lobby, response:", response)
		emit_signal("connection_failed")

func _on_steam_lobby_list(lobbies: Array):
	print("[Steam] Callback lobby_match_list -> count:", lobbies.size())
	emit_signal("steam_lobby_list_updated", lobbies)

func _on_steam_lobby_chat_update(_lobby_id: int, _changed_id: int, _making_change_id: int, _chat_state: int):
	pass

# ── DISCONNECT ──

func disconnect_from_server():
	if _disconnecting:
		return
	_disconnecting = true
	if _steam and steam_lobby_id != 0:
		_steam.leaveLobby(steam_lobby_id)
		steam_lobby_id = 0
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	emit_signal("server_disconnected")
