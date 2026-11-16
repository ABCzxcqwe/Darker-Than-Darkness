class_name SteamProvider
extends OnlineProviderService
## Proveedor online basado en GodotSteam + SteamMultiplayerPeer.
##
## Encapsula todo el ciclo de Steam: init, callbacks, lobbies, metadata y
## creación del peer. NetworkManager solo recibe señales y decide qué hacer.
##
## Hacia afuera los lobbies se identifican con String; Steam sigue usando su id
## numérico internamente. La lista de lobbies se entrega como summaries
## neutrales para que la UI no dependa del singleton de Steam.

const TAG := "Steam"

## EResult / respuestas de Steam usadas acá. Se definen localmente para no
## depender de que el singleton exponga los enums en todas las versiones.
const RESULT_OK := 1
const CHAT_ROOM_ENTER_RESPONSE_SUCCESS := 1
const CHAT_STATE_JOINED := 0

var _steam: Variant = null
var _ready := false
var _init_ok := false
var _steam_running := false
var _poll_accum := 0.0
var _pending_metadata: Dictionary = {}
var _current_lobby_id: int = 0
var _callbacks_connected := false


func _init() -> void:
	provider_id = NetEnums.Provider.STEAM
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _steam == null:
		return
	_steam.run_callbacks()
	_poll_accum += delta
	if not _ready:
		# Si Steam se abrió después del arranque, reintentar el init.
		if _poll_accum >= NetConfig.STEAM_RETRY_INTERVAL:
			_poll_accum = 0.0
			if _is_steam_running():
				initialize()
		return
	if _poll_accum < NetConfig.STEAM_AVAILABILITY_POLL:
		return
	_poll_accum = 0.0
	var running := _is_steam_running()
	if running == _steam_running:
		return
	_steam_running = running
	NetLog.info(TAG, "Disponibilidad de Steam cambió: %s" % str(running))
	availability_changed.emit(is_available())


func initialize() -> bool:
	if _ready:
		_steam_running = _is_steam_running()
		return _steam_running
	if _steam == null:
		_steam = Engine.get_singleton("Steam")
	if _steam == null:
		NetLog.debug(TAG, "GodotSteam no está instalado")
		return false
	if not _init_ok:
		var result = _steam.steamInit()
		if not _parse_init_result(result):
			return false
		_init_ok = true
	if not _is_steam_running():
		NetLog.debug(TAG, "Steam inicializado pero el cliente no responde")
		return false
	_connect_callbacks()
	_ready = true
	_steam_running = true
	_poll_accum = 0.0
	NetLog.debug(TAG, "Steam listo")
	availability_changed.emit(true)
	return true


func is_available() -> bool:
	return _ready and _steam_running


func host_lobby(max_players: int, metadata: Dictionary) -> bool:
	if not is_available():
		NetLog.warn(TAG, "No se puede crear lobby: Steam no disponible")
		return false
	_pending_metadata = metadata.duplicate(true)
	var result = _steam.createLobby(
		_steam.LOBBY_TYPE_PUBLIC,
		clampi(max_players, 2, NetConfig.MAX_PLAYERS)
	)
	if typeof(result) == TYPE_DICTIONARY and int(result.get("result", RESULT_OK)) != RESULT_OK:
		NetLog.error(TAG, "createLobby falló: %s" % str(result))
		_pending_metadata.clear()
		return false
	return true


func join_lobby(lobby_id: String) -> bool:
	var numeric := _lobby_to_int(lobby_id)
	if not is_available() or numeric == 0:
		return false
	var result = _steam.joinLobby(numeric)
	if typeof(result) == TYPE_DICTIONARY and int(result.get("result", RESULT_OK)) != RESULT_OK:
		NetLog.error(TAG, "joinLobby falló: %s" % str(result))
		return false
	return true


func leave_lobby() -> void:
	if _current_lobby_id == 0:
		return
	var lobby := _current_lobby_id
	_current_lobby_id = 0
	if _steam != null and _steam.has_method("leaveLobby"):
		_steam.leaveLobby(lobby)
	lobby_left.emit(str(lobby))


func request_lobby_list(max_results: int, game_id_filter: String) -> void:
	if not is_available():
		return
	_steam.addRequestLobbyListResultCountFilter(max_results)
	_steam.addRequestLobbyListDistanceFilter(_steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	_steam.addRequestLobbyListStringFilter(
		NetConfig.LOBBY_ATTR_GAME_ID,
		game_id_filter,
		_steam.LOBBY_COMPARISON_EQUAL
	)
	_steam.requestLobbyList()


func create_host_peer(lobby_id: String) -> MultiplayerPeer:
	var numeric := _lobby_to_int(lobby_id)
	if numeric == 0:
		return null
	var new_peer := ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if new_peer == null:
		NetLog.error(TAG, "SteamMultiplayerPeer no disponible (¿DLL no cargada?)")
		return null
	var err: int = new_peer.host_with_lobby(numeric)
	if err != OK:
		NetLog.error(TAG, "host_with_lobby falló: %s" % err)
		return null
	return new_peer


func create_client_peer(lobby_id: String) -> MultiplayerPeer:
	var numeric := _lobby_to_int(lobby_id)
	if numeric == 0:
		return null
	var new_peer := ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if new_peer == null:
		NetLog.error(TAG, "SteamMultiplayerPeer no disponible (¿DLL no cargada?)")
		return null
	var err: int = new_peer.connect_to_lobby(numeric)
	if err != OK:
		NetLog.error(TAG, "connect_to_lobby falló: %s" % err)
		return null
	return new_peer


func get_lobby_data(lobby_id: String, key: String) -> String:
	if _steam == null:
		return ""
	var numeric := _lobby_to_int(lobby_id)
	if numeric == 0:
		return ""
	return String(_steam.getLobbyData(numeric, key))


func is_lobby_owner(lobby_id: String) -> bool:
	if _steam == null:
		return false
	var numeric := _lobby_to_int(lobby_id)
	if numeric == 0:
		return false
	return _id_to_int(_steam.getLobbyOwner(numeric)) == _id_to_int(_steam.getSteamID())


func get_lobby_id() -> String:
	if _current_lobby_id == 0:
		return ""
	return str(_current_lobby_id)


func get_current_lobby_summary() -> Dictionary:
	if _current_lobby_id == 0:
		return {}
	return _lobby_summary(_current_lobby_id)


# ── Callbacks de Steam ──

func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result != RESULT_OK or lobby_id == 0:
		NetLog.error(TAG, "lobby_created falló (result=%d, lobby=%d)" % [result, lobby_id])
		_pending_metadata.clear()
		failed.emit("lobby_create_failed")
		return
	_current_lobby_id = lobby_id
	_apply_lobby_metadata(lobby_id)
	_pending_metadata.clear()
	NetLog.debug(TAG, "Lobby creado: %d" % lobby_id)
	lobby_created.emit(str(lobby_id))


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		NetLog.error(TAG, "No se pudo unir al lobby (response=%d)" % response)
		failed.emit("lobby_join_failed")
		return
	_current_lobby_id = lobby_id
	NetLog.debug(TAG, "Lobby unido: %d" % lobby_id)
	lobby_joined.emit(str(lobby_id))


func _on_lobby_match_list(lobbies: Array) -> void:
	var summaries: Array = []
	for raw_id in lobbies:
		var lobby_id := int(raw_id)
		if lobby_id != 0:
			summaries.append(_lobby_summary(lobby_id))
	lobby_list_received.emit(summaries)


func _on_lobby_chat_update(lobby_id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if _steam == null:
		return
	if _id_to_int(changed_id) != _id_to_int(_steam.getSteamID()):
		return
	if chat_state == CHAT_STATE_JOINED:
		return
	_current_lobby_id = 0
	NetLog.info(TAG, "Salimos del lobby %d (chat_state=%d)" % [lobby_id, chat_state])
	lobby_left.emit(str(lobby_id))


# ── Internos ──

func _lobby_summary(lobby_id: int) -> Dictionary:
	var name_text := String(_steam.getLobbyData(lobby_id, NetConfig.LOBBY_ATTR_NAME))
	if name_text == "":
		name_text = "Lobby %d" % lobby_id
	var host_text := String(_steam.getLobbyData(lobby_id, NetConfig.LOBBY_ATTR_HOST))
	var map_text := String(_steam.getLobbyData(lobby_id, NetConfig.LOBBY_ATTR_MAP))
	var mode_text := String(_steam.getLobbyData(lobby_id, NetConfig.LOBBY_ATTR_MODE))
	if mode_text == "":
		mode_text = NetConfig.DEFAULT_MODE
	var max_players := int(String(_steam.getLobbyData(lobby_id, NetConfig.LOBBY_ATTR_MAX_PLAYERS)))
	if max_players <= 0:
		max_players = NetConfig.MAX_PLAYERS
	var players := int(_steam.getNumLobbyMembers(lobby_id))
	return OnlineProviderService.make_summary(
		str(lobby_id),
		NetEnums.provider_to_id(NetEnums.Provider.STEAM),
		name_text,
		host_text,
		map_text,
		mode_text,
		players,
		max_players
	)


func _parse_init_result(result: Variant) -> bool:
	if typeof(result) == TYPE_DICTIONARY:
		var status := int(result.get("status", -1))
		var ok_status := int(_steam.STEAM_API_INIT_RESULT_OK)
		if status != ok_status:
			NetLog.debug(TAG, "steamInit falló (status=%d): %s" % [status, str(result)])
			return false
		return true
	if typeof(result) == TYPE_BOOL:
		if not result:
			NetLog.debug(TAG, "steamInit devolvió false. Verificá steam_appid.txt o el App ID.")
			return false
		return true
	NetLog.error(TAG, "Resultado inesperado de steamInit: %s" % str(typeof(result)))
	return false


func _connect_callbacks() -> void:
	if _callbacks_connected:
		return
	if not _steam.lobby_created.is_connected(_on_lobby_created):
		_steam.lobby_created.connect(_on_lobby_created)
	if not _steam.lobby_joined.is_connected(_on_lobby_joined):
		_steam.lobby_joined.connect(_on_lobby_joined)
	if not _steam.lobby_match_list.is_connected(_on_lobby_match_list):
		_steam.lobby_match_list.connect(_on_lobby_match_list)
	if not _steam.lobby_chat_update.is_connected(_on_lobby_chat_update):
		_steam.lobby_chat_update.connect(_on_lobby_chat_update)
	_callbacks_connected = true


func _apply_lobby_metadata(lobby_id: int) -> void:
	var room_name := String(_pending_metadata.get(NetConfig.LOBBY_ATTR_NAME, _pending_metadata.get(NetConfig.LOBBY_ATTR_ROOM_NAME, "Lobby")))
	_steam.setLobbyData(lobby_id, NetConfig.LOBBY_ATTR_NAME, room_name)
	_steam.setLobbyData(lobby_id, NetConfig.LOBBY_ATTR_ROOM_NAME, String(_pending_metadata.get(NetConfig.LOBBY_ATTR_ROOM_NAME, room_name)))
	_steam.setLobbyData(lobby_id, NetConfig.LOBBY_ATTR_HOST, String(_pending_metadata.get(NetConfig.LOBBY_ATTR_HOST, "")))
	_steam.setLobbyData(lobby_id, NetConfig.LOBBY_ATTR_MAP, String(_pending_metadata.get(NetConfig.LOBBY_ATTR_MAP, "")))
	_steam.setLobbyData(lobby_id, NetConfig.LOBBY_ATTR_MODE, String(_pending_metadata.get(NetConfig.LOBBY_ATTR_MODE, NetConfig.DEFAULT_MODE)))
	_steam.setLobbyData(lobby_id, NetConfig.LOBBY_ATTR_MAX_PLAYERS, String(_pending_metadata.get(NetConfig.LOBBY_ATTR_MAX_PLAYERS, NetConfig.MAX_PLAYERS)))
	_steam.setLobbyData(lobby_id, NetConfig.LOBBY_ATTR_GAME_ID, String(_pending_metadata.get(NetConfig.LOBBY_ATTR_GAME_ID, NetConfig.GAME_ID)))
	_steam.setLobbyJoinable(lobby_id, true)
	_steam.setLobbyType(lobby_id, _steam.LOBBY_TYPE_PUBLIC)
	_steam.allowP2PPacketRelay(true)


func _is_steam_running() -> bool:
	if _steam == null:
		return false
	if not _steam.has_method("isSteamRunning"):
		return false
	return bool(_steam.isSteamRunning())


static func _lobby_to_int(lobby_id: String) -> int:
	var clean := lobby_id.strip_edges()
	if clean.is_valid_int():
		return int(clean)
	return 0


static func _id_to_int(value: Variant) -> int:
	match typeof(value):
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return int(value)
		TYPE_STRING:
			return int(value)
		TYPE_DICTIONARY:
			var low := int(value.get("steam_id_low", 0))
			var high := int(value.get("steam_id_high", 0))
			return (high << 32) | (low & 0xFFFFFFFF)
		_:
			return 0


func _exit_tree() -> void:
	if _current_lobby_id != 0 and _steam != null:
		_steam.leaveLobby(_current_lobby_id)
		_current_lobby_id = 0
