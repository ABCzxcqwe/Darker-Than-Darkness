# res://core/NetworkManager.gd
extends Node

enum NetworkMode { LAN, STEAM }
const ONLINE = NetworkMode.STEAM

const PORT := 4242
const MAX_LOBBIES := 16
const GAME_ID_FILTER := "darker_than_darkness"

signal connection_succeeded()
signal connection_failed()
signal server_disconnected()
signal steam_lobby_list_updated(lobbies: Array)

var peer: MultiplayerPeer
var network_mode: NetworkMode = NetworkMode.LAN
var steam_lobby_id: int = 0
var _disconnecting := false

var _steam: Variant = null
var current_online_provider: String = "steam"
var _steam_ready := false
# Lista interna dev: hardcodear aquí futuros servidores {name, address} - no accesible al jugador
var custom_servers: Array = [] # Ej: [{"name":"Brazil","address":"brazil.example.com:4242"}]


func _process(_delta: float):
	if _steam:
		_steam.run_callbacks()


func _ready():
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
	current_online_provider = "steam"
	network_mode = NetworkMode.STEAM
	print("[NetworkManager] Modo Steam activado")
	return true


func is_steam_ready() -> bool:
	return _steam_ready

func is_online_available(provider: String = "steam") -> bool:
	if provider.to_lower() == "steam":
		return _steam_ready
	return false

func get_online_providers() -> Array:
	# Solo Steam por ahora, placeholders futuros no visibles
	return ["Steam"]

func initialize_online(provider: String = "steam") -> bool:
	if provider.to_lower() != "steam":
		print("[NetworkManager] Proveedor no soportado: ", provider)
		return false
	return initialize_steam()

func set_online_mode(provider: String = "steam") -> bool:
	return initialize_online(provider)

func set_lan_mode():
	network_mode = NetworkMode.LAN


func _on_internal_server_disconnected():
	if _disconnecting:
		return
	_disconnecting = true
	print("Servidor interno desconectado")
	emit_signal("server_disconnected")


func create_server(player_name: String, map_name: String, room_name: String = "", game_mode: String = "Escape", p_max_players: int = 4) -> bool:
	_disconnecting = false
	LobbyManager.setup_as_host(player_name, map_name, room_name, game_mode, p_max_players)

	if network_mode == NetworkMode.LAN:
		peer = ENetMultiplayerPeer.new()
		var err = peer.create_server(PORT, clampi(p_max_players, 2, LobbyManager.MAX_PLAYERS))
		if err != OK:
			print("Error al crear servidor: ", err)
			LobbyManager.reset_lobby_state()
			return false
	else:
		if not _steam_ready:
			print("[NetworkManager] Steam API no inicializada. Usá modo LAN.")
			LobbyManager.reset_lobby_state()
			return false
		print("[NetworkManager] Creando lobby Steam...")
		_steam.createLobby(_steam.LOBBY_TYPE_PUBLIC, clampi(p_max_players, 2, LobbyManager.MAX_PLAYERS))
		return true

	multiplayer.multiplayer_peer = peer

	var my_id = multiplayer.get_unique_id()
	LobbyManager.register_local_player(my_id, player_name)

	emit_signal("connection_succeeded")
	return true


func join_server(player_name: String, ip_or_lobby_id = "127.0.0.1") -> bool:
	_disconnecting = false
	LobbyManager.setup_as_client(player_name)

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


func request_lobby_list():
	if _steam_ready:
		_steam.addRequestLobbyListResultCountFilter(MAX_LOBBIES)
		_steam.addRequestLobbyListDistanceFilter(_steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
		_steam.addRequestLobbyListStringFilter("game_id", GAME_ID_FILTER, _steam.LOBBY_COMPARISON_EQUAL)
		_steam.requestLobbyList()


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
	emit_signal("server_disconnected")
	LobbyManager.reset_lobby_state()
	LobbyManager.is_host = false
	LobbyManager.local_player_name = ""
	LobbyManager.selected_map = ""
	LobbyManager.room_name = ""
	LobbyManager.game_mode = "Escape"
	LobbyManager.max_players = 4


# ── SEÑALES DE CONEXIÓN ──

func _on_connected_ok():
	emit_signal("connection_succeeded")


func _on_connect_fail():
	emit_signal("connection_failed")


# ── STEAM CALLBACKS ──

func _on_steam_lobby_created(connect_or_result: int, lobby_id: int):
	print("[Steam] Callback lobby_created -> result:", connect_or_result, " lobby_id:", lobby_id)
	if connect_or_result == 1 and lobby_id != 0:
		steam_lobby_id = lobby_id
		print("[Steam] Lobby creado exitosamente! ID:", lobby_id)
		var room_nm: String = LobbyManager.room_name if LobbyManager.room_name != "" else LobbyManager.local_player_name
		_steam.setLobbyData(lobby_id, "name", room_nm)
		_steam.setLobbyData(lobby_id, "room_name", room_nm)
		_steam.setLobbyData(lobby_id, "host", LobbyManager.local_player_name)
		_steam.setLobbyData(lobby_id, "map", LobbyManager.selected_map)
		_steam.setLobbyData(lobby_id, "mode", LobbyManager.game_mode)
		_steam.setLobbyData(lobby_id, "max_players", str(LobbyManager.max_players))
		_steam.setLobbyData(lobby_id, "game_id", GAME_ID_FILTER)
		_steam.setLobbyJoinable(lobby_id, true)
		_steam.setLobbyType(lobby_id, _steam.LOBBY_TYPE_PUBLIC)
		_steam.allowP2PPacketRelay(true)

		peer = ClassDB.instantiate("SteamMultiplayerPeer")
		if not peer:
			print("[Steam] SteamMultiplayerPeer no disponible (DLL no cargada).")
			emit_signal("connection_failed")
			return
		var err = peer.host_with_lobby(lobby_id)
		if err != OK:
			print("[Steam] Error en host_with_lobby: ", err)
			emit_signal("connection_failed")
			return
		multiplayer.multiplayer_peer = peer

		var my_id = multiplayer.get_unique_id()
		LobbyManager.register_local_player(my_id, LobbyManager.local_player_name)
		emit_signal("connection_succeeded")
	else:
		print("[Steam] Error al crear lobby, código:", connect_or_result)
		emit_signal("connection_failed")


func _on_steam_lobby_joined(lobby_id: int, _perm: int, _locked: bool, response: int):
	print("[Steam] Callback lobby_joined -> lobby:", lobby_id, " response:", response)
	if response == _steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		steam_lobby_id = lobby_id
		if LobbyManager.is_host or _steam.getLobbyOwner(lobby_id) == _steam.getSteamID():
			print("[Steam] Somos el host, ignoramos lobby_joined para connect")
			return
		print("[Steam] Conectando al lobby como cliente...")
		_steam.allowP2PPacketRelay(true)
		peer = ClassDB.instantiate("SteamMultiplayerPeer")
		if not peer:
			print("[Steam] SteamMultiplayerPeer no disponible (DLL no cargada).")
			emit_signal("connection_failed")
			return
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
