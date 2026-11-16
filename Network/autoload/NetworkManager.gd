# res://Network/autoload/NetworkManager.gd
extends Node
## Autoload de transporte y proveedores online.
##
## Responsabilidades:
## - Crear servidor/cliente ENet (LAN) y servidor dedicado.
## - Delegar el modo online a los servicios registrados en `providers/`.
## - Exponer la lista de proveedores realmente usables.
##
## Importante: este autoload desactiva `get_tree().multiplayer_poll` y hace
## polling manual a `NetConfig.NETWORK_TICK_HZ`. Si se reemplaza este nodo, hay
## que devolver `multiplayer_poll = true`.

signal connection_succeeded()
signal connection_failed()
signal server_disconnected()
## Lista neutral de lobbies: Array[Dictionary] (ver OnlineProviderService).
signal online_lobby_list_updated(lobbies: Array)
## Alias de compatibilidad con la UI anterior. Se emite junto al nuevo.
signal steam_lobby_list_updated(lobbies: Array)
signal online_providers_changed(providers: Array)

const TAG := "NetworkManager"

# Alias de compatibilidad: permiten seguir usando NetworkManager.OnlineProvider
# y NetworkManager.NetworkMode desde el código existente.
const OnlineProvider = NetEnums.Provider
const NetworkMode = NetEnums.Mode
const PORT := NetConfig.PORT

var peer: MultiplayerPeer
var network_mode: NetworkMode = NetworkMode.LAN
var current_online_provider: OnlineProvider = OnlineProvider.DISABLE
## ID del lobby online actual. Es un string opaco: Steam lo expone como número
## y EOSG como string. `steam_lobby_id` se conserva como alias numérico para
## código viejo.
var online_lobby_id: String = ""
var steam_lobby_id: int = 0
## Lista interna dev: hardcodear aquí futuros servidores {name, address}.
## No se expone al jugador; queda para un futuro CustomProvider.
var custom_servers: Array = []

var _provider_services: Dictionary = {}  # OnlineProvider -> OnlineProviderService
var _last_online_providers: Array[OnlineProvider] = []
var _disconnecting := false
var _connection_signal_emitted := false
var _net_poll_accum := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().multiplayer_poll = false
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connect_fail)
	multiplayer.server_disconnected.connect(_on_internal_server_disconnected)
	_build_providers()
	_last_online_providers = get_online_providers()
	_initialize_online_quietly()


func _physics_process(delta: float) -> void:
	if get_tree() == null or get_tree().multiplayer_poll:
		return
	_net_poll_accum += delta
	var step := 1.0 / NetConfig.NETWORK_TICK_HZ
	while _net_poll_accum >= step:
		_net_poll_accum -= step
		if multiplayer.multiplayer_peer:
			multiplayer.poll()


# ── Proveedores ──

func _build_providers() -> void:
	_register_provider(SteamProvider.new())
	# EOSG se registra siempre; su is_available() queda false si falta el addon
	# o las credenciales, por lo que get_online_providers() no lo muestra.
	_register_provider(EOSGProvider.new())
	# P2P y CUSTOM no se registran hasta tener una implementación real.


func _register_provider(service: OnlineProviderService) -> void:
	if service == null:
		return
	_provider_services[service.provider_id] = service
	add_child(service)
	service.availability_changed.connect(_on_provider_availability_changed)
	service.lobby_created.connect(_on_provider_lobby_created)
	service.lobby_joined.connect(_on_provider_lobby_joined)
	service.lobby_list_received.connect(_on_provider_lobby_list)
	service.lobby_left.connect(_on_provider_lobby_left)
	service.failed.connect(_on_provider_failed)


func _initialize_online_quietly() -> void:
	# Steam loguea rápido y de forma sincrónica. EOSG arranca su login async y
	# avisa por `availability_changed` cuando está listo.
	for id in _provider_services:
		# EOSG se autoinicializa diferido para que SettingsManager ya esté listo.
		if int(id) == OnlineProvider.EOSG:
			continue
		var service = _provider_services[id]
		if service != null and service.has_method("is_configured") and service.is_configured():
			service.initialize()


## Espera a que un proveedor termine su inicialización async (EOSG).
## Devuelve false si no está disponible dentro del timeout.
func initialize_online_async(provider: OnlineProvider = OnlineProvider.STEAM, timeout: float = 15.0) -> bool:
	if is_online_available(provider):
		current_online_provider = provider
		network_mode = NetworkMode.ONLINE
		return true
	var service = _provider_services.get(provider)
	if service == null:
		return false
	if service.has_method("is_configured") and not service.is_configured():
		return false
	# Solo EOSG tiene login asíncrono; Steam/LAN resuelven en el acto.
	if provider != OnlineProvider.EOSG:
		return initialize_online(provider)
	initialize_online(provider)
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if is_online_available(provider):
			current_online_provider = provider
			network_mode = NetworkMode.ONLINE
			return true
	if is_online_available(provider):
		current_online_provider = provider
		network_mode = NetworkMode.ONLINE
		return true
	return false


func is_steam_ready() -> bool:
	var service = _provider_services.get(OnlineProvider.STEAM)
	return service != null and service.is_available()


func initialize_steam() -> bool:
	return initialize_online(OnlineProvider.STEAM)


func is_online_available(provider: OnlineProvider = OnlineProvider.STEAM) -> bool:
	if provider == OnlineProvider.DISABLE:
		return false
	var service = _provider_services.get(provider)
	return service != null and service.is_available()


func get_online_providers() -> Array[OnlineProvider]:
	var out: Array[OnlineProvider] = []
	var ids: Array = _provider_services.keys()
	ids.sort()
	for id in ids:
		var service = _provider_services[id]
		if service.is_available():
			out.append(int(id))
	return out


func initialize_online(provider: OnlineProvider = OnlineProvider.STEAM) -> bool:
	var service = _provider_services.get(provider)
	if service == null:
		NetLog.warn(TAG, "Proveedor no implementado: %s" % NetEnums.provider_to_id(provider))
		return false
	if not service.is_available():
		service.initialize()
	if not service.is_available():
		NetLog.warn(TAG, "Proveedor no disponible: %s" % NetEnums.provider_to_id(provider))
		return false
	current_online_provider = provider
	network_mode = NetworkMode.ONLINE
	NetLog.info(TAG, "Modo ONLINE activado | proveedor: %s" % NetEnums.provider_to_id(provider))
	return true


func set_online_mode(provider: OnlineProvider = OnlineProvider.STEAM) -> bool:
	return initialize_online(provider)


func set_lan_mode() -> void:
	network_mode = NetworkMode.LAN
	current_online_provider = OnlineProvider.DISABLE


func has_active_peer() -> bool:
	return multiplayer.multiplayer_peer != null


# ── Direcciones LAN ──

func get_local_ip() -> String:
	return NetAddress.local_ip()


func get_lan_address() -> String:
	return NetAddress.lan_address(NetConfig.PORT)


# ── Creación de servidor ──

func create_server(
	player_name: String,
	map_name: String,
	room_name: String = "",
	game_mode: String = "Escape",
	p_max_players: int = 4
) -> bool:
	_disconnecting = false
	_connection_signal_emitted = false
	match network_mode:
		NetworkMode.LAN:
			return _create_lan_server(player_name, map_name, room_name, game_mode, p_max_players)
		NetworkMode.ONLINE:
			return _create_online_server(player_name, map_name, room_name, game_mode, p_max_players)
		_:
			NetLog.error(TAG, "Modo de red no soportado")
			return false


func _create_lan_server(
	player_name: String,
	map_name: String,
	room_name: String,
	game_mode: String,
	p_max_players: int
) -> bool:
	online_lobby_id = ""
	steam_lobby_id = 0
	LobbyManager.setup_as_host(player_name, map_name, room_name, game_mode, p_max_players)
	peer = ENetMultiplayerPeer.new()
	var err: int = peer.create_server(
		NetConfig.PORT,
		clampi(p_max_players, 2, LobbyManager.MAX_PLAYERS)
	)
	if err != OK:
		NetLog.error(TAG, "No se pudo crear el servidor ENet (error %s)" % err)
		LobbyManager.reset_session()
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	LobbyManager.on_server_ready()
	LobbyManager.register_local_player(multiplayer.get_unique_id(), player_name)
	NetLog.info(TAG, "Servidor LAN escuchando en el puerto %d" % NetConfig.PORT)
	connection_succeeded.emit()
	return true


func _create_online_server(
	player_name: String,
	map_name: String,
	room_name: String,
	game_mode: String,
	p_max_players: int
) -> bool:
	var service = _provider_services.get(current_online_provider)
	if service == null:
		NetLog.error(TAG, "Proveedor online no implementado")
		return false
	if not service.is_available():
		NetLog.error(TAG, "Proveedor online no disponible")
		return false
	LobbyManager.setup_as_host(player_name, map_name, room_name, game_mode, p_max_players)
	var metadata := {
		NetConfig.LOBBY_ATTR_NAME: LobbyManager.room_name,
		NetConfig.LOBBY_ATTR_ROOM_NAME: LobbyManager.room_name,
		NetConfig.LOBBY_ATTR_HOST: player_name,
		NetConfig.LOBBY_ATTR_MAP: map_name,
		NetConfig.LOBBY_ATTR_MODE: game_mode,
		NetConfig.LOBBY_ATTR_MAX_PLAYERS: str(LobbyManager.max_players),
		NetConfig.LOBBY_ATTR_GAME_ID: NetConfig.GAME_ID,
	}
	return service.host_lobby(
		clampi(p_max_players, 2, LobbyManager.MAX_PLAYERS),
		metadata
	)


func start_dedicated_server(
	room_name: String,
	map_name: String,
	game_mode: String = "Escape",
	p_max_players: int = 4,
	port: int = -1
) -> bool:
	_disconnecting = false
	network_mode = NetworkMode.LAN
	current_online_provider = OnlineProvider.DISABLE
	online_lobby_id = ""
	steam_lobby_id = 0
	var resolved_port := port if port > 0 else NetConfig.PORT
	LobbyManager.setup_as_dedicated(room_name, map_name, game_mode, p_max_players)

	peer = ENetMultiplayerPeer.new()
	var err: int = peer.create_server(
		resolved_port,
		clampi(p_max_players, 2, LobbyManager.MAX_PLAYERS)
	)
	if err != OK:
		NetLog.error(TAG, "No se pudo crear el servidor dedicado (error %s). ¿Puerto %d en uso?" % [err, resolved_port])
		LobbyManager.reset_session()
		peer = null
		return false

	multiplayer.multiplayer_peer = peer
	# El servidor dedicado no es jugador: no llama a on_server_ready().
	# El primer cliente que entre será el room host.
	LobbyManager.server_peer_id = multiplayer.get_unique_id()
	NetLog.info(TAG, "Servidor dedicado escuchando en el puerto %d (max %d)" % [resolved_port, p_max_players])
	return true


# ── Conexión de clientes ──

func join_server(player_name: String, address: String = "127.0.0.1") -> bool:
	_disconnecting = false
	_connection_signal_emitted = false
	# Compatibilidad: la UI vieja llama join_server también para online.
	if network_mode != NetworkMode.LAN:
		return join_online_lobby(player_name, address)
	LobbyManager.setup_as_client(player_name)
	var parsed := NetAddress.parse_host_port(address, NetConfig.PORT)
	var host := String(parsed["host"])
	var port := int(parsed["port"])

	peer = ENetMultiplayerPeer.new()
	var err: int = peer.create_client(host, port)
	if err != OK:
		NetLog.error(TAG, "No se pudo conectar a %s:%d (error %s)" % [host, port, err])
		peer = null
		LobbyManager.reset_session()
		return false
	multiplayer.multiplayer_peer = peer
	NetLog.info(TAG, "Conectando a %s:%d" % [host, port])
	return true


## Une al lobby del proveedor online actual. `lobby_id` es opaco (String).
func join_online_lobby(player_name: String, lobby_id: String) -> bool:
	_disconnecting = false
	_connection_signal_emitted = false
	if network_mode != NetworkMode.ONLINE:
		NetLog.warn(TAG, "join_online_lobby requiere modo ONLINE")
		return false
	if lobby_id.strip_edges() == "":
		NetLog.warn(TAG, "Lobby ID inválido")
		return false
	var service = _provider_services.get(current_online_provider)
	if service == null or not service.is_available():
		NetLog.warn(TAG, "Proveedor online no disponible")
		return false
	LobbyManager.setup_as_client(player_name)
	online_lobby_id = lobby_id
	steam_lobby_id = int(lobby_id) if lobby_id.is_valid_int() else 0
	return service.join_lobby(lobby_id)


## Wrapper de compatibilidad. Preferir `join_online_lobby`.
func join_steam_lobby(player_name: String, lobby_id: int) -> bool:
	if current_online_provider != OnlineProvider.STEAM:
		NetLog.warn(TAG, "Steam no está en modo online")
		return false
	return join_online_lobby(player_name, str(lobby_id))


func request_lobby_list() -> void:
	var service = _provider_services.get(current_online_provider)
	if service == null:
		service = _provider_services.get(OnlineProvider.STEAM)
	if service != null and service.is_available():
		service.request_lobby_list(NetConfig.MAX_LOBBIES, NetConfig.GAME_ID)


func disconnect_from_server() -> void:
	if _disconnecting:
		return
	_disconnecting = true
	_teardown_connection()
	LobbyManager.reset_session()
	server_disconnected.emit()


func _teardown_connection() -> void:
	_close_peer()
	_leave_lobby()


func _close_peer() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	peer = null


func _leave_lobby() -> void:
	if online_lobby_id == "":
		return
	var service = _provider_services.get(current_online_provider)
	if service == null:
		service = _provider_services.get(OnlineProvider.STEAM)
	if service != null:
		service.leave_lobby()
	online_lobby_id = ""
	steam_lobby_id = 0


# ── Señales de conexión ──

func _emit_connection_succeeded() -> void:
	if _connection_signal_emitted:
		return
	_connection_signal_emitted = true
	connection_succeeded.emit()


func _on_connected_ok() -> void:
	_emit_connection_succeeded()


func _on_connect_fail() -> void:
	NetLog.warn(TAG, "Conexión fallida")
	_disconnecting = true
	_close_peer()
	_leave_lobby()
	connection_failed.emit()


func _on_internal_server_disconnected() -> void:
	if _disconnecting:
		return
	_disconnecting = true
	NetLog.info(TAG, "Servidor desconectado")
	_teardown_connection()
	LobbyManager.reset_session()
	server_disconnected.emit()


# ── Callbacks de proveedores ──

func _on_provider_availability_changed(_is_available: bool) -> void:
	var providers := get_online_providers()
	if providers != _last_online_providers:
		_last_online_providers = providers
		online_providers_changed.emit(providers)


func _on_provider_lobby_created(lobby_id: String) -> void:
	var service = _provider_services.get(current_online_provider)
	if service == null:
		return
	var new_peer: MultiplayerPeer = service.create_host_peer(lobby_id)
	if new_peer == null:
		_disconnecting = true
		service.leave_lobby()
		connection_failed.emit()
		return
	peer = new_peer
	multiplayer.multiplayer_peer = peer
	online_lobby_id = lobby_id
	steam_lobby_id = int(lobby_id) if lobby_id.is_valid_int() else 0
	LobbyManager.on_server_ready()
	LobbyManager.register_local_player(multiplayer.get_unique_id(), LobbyManager.local_player_name)
	_emit_connection_succeeded()


func _on_provider_lobby_joined(lobby_id: String) -> void:
	var service = _provider_services.get(current_online_provider)
	if service == null:
		return
	var lobby_game_id: String = service.get_lobby_data(lobby_id, NetConfig.LOBBY_ATTR_GAME_ID)
	if lobby_game_id != "" and lobby_game_id != NetConfig.GAME_ID:
		NetLog.warn(TAG, "El lobby pertenece a otro juego; saliendo")
		_disconnecting = true
		service.leave_lobby()
		connection_failed.emit()
		return
	var new_peer: MultiplayerPeer = service.create_client_peer(lobby_id)
	if new_peer == null:
		_disconnecting = true
		service.leave_lobby()
		connection_failed.emit()
		return
	peer = new_peer
	multiplayer.multiplayer_peer = peer
	online_lobby_id = lobby_id
	steam_lobby_id = int(lobby_id) if lobby_id.is_valid_int() else 0
	# Steam emitía la señal apenas se unía al lobby (comportamiento histórico).
	# EOSG tarda en completar el handshake P2P, así que esperamos a
	# `connected_to_server` para no lanzar RPCs sobre un peer CONNECTING.
	if current_online_provider != OnlineProvider.EOSG:
		_emit_connection_succeeded()


func _on_provider_lobby_list(lobbies: Array) -> void:
	online_lobby_list_updated.emit(lobbies)
	steam_lobby_list_updated.emit(lobbies)


func _on_provider_lobby_left(lobby_id: String) -> void:
	NetLog.info(TAG, "Salida del lobby %s" % lobby_id)
	online_lobby_id = ""
	steam_lobby_id = 0
	if _disconnecting:
		return
	_disconnecting = true
	_teardown_connection()
	LobbyManager.reset_session()
	server_disconnected.emit()


func _on_provider_failed(reason: String) -> void:
	NetLog.warn(TAG, "El proveedor falló: %s" % reason)
	_disconnecting = true
	_close_peer()
	_leave_lobby()
	connection_failed.emit()
