extends Node
## Puente entre EOSGProvider y el addon Epic Online Services Godot.
##
## Este archivo NO tiene `class_name` a propósito: solo se carga con `load()`
## cuando el addon de EOSG está instalado. Así el resto del recode sigue
## parseando y funcionando sin EOSG (el proveedor simplemente no se lista).
##
## No lo instanciar directamente desde otros scripts; usar EOSGProvider.

signal availability_changed(is_available: bool)
signal lobby_created(lobby_id: String)
signal lobby_joined(lobby_id: String)
signal lobby_list_received(lobbies: Array)
signal lobby_left(lobby_id: String)
signal failed(reason: String)

const TAG := "EOSG"

var _lobby: Variant = null
var _host_puid: String = ""
var _setup_ok := false
var _logged_in := false
var _starting := false
var _connected_kick := false


func _ready() -> void:
	if not ClassDB.class_exists("EOSGMultiplayerPeer"):
		NetLog.debug(TAG, "EOSGMultiplayerPeer no está cargado; proveedor inactivo.")


func is_available() -> bool:
	return _setup_ok and _logged_in and ClassDB.class_exists("EOSGMultiplayerPeer")


## Inicializa EOS y loguea al usuario. Es una corrutina: EOSGProvider la llama
## sin await y espera `availability_changed`.
func start_async(config: Dictionary, login_mode: String, display_name: String) -> void:
	if _starting or is_available():
		return
	_starting = true

	if not ClassDB.class_exists("EOSGMultiplayerPeer"):
		_fail("eosg_peer_missing")
		_starting = false
		return

	var hp := get_node_or_null("/root/HPlatform")
	var ha := get_node_or_null("/root/HAuth")
	if hp == null or ha == null:
		_fail("eosg_autoloads_missing")
		_starting = false
		return

	var creds = HCredentials.new()
	creds.product_name = String(config.get("product_name", "Darker Than Darkness"))
	creds.product_version = String(config.get("product_version", "1.0.0"))
	creds.product_id = String(config.get("product_id", ""))
	creds.sandbox_id = String(config.get("sandbox_id", ""))
	creds.deployment_id = String(config.get("deployment_id", ""))
	creds.client_id = String(config.get("client_id", ""))
	creds.client_secret = String(config.get("client_secret", ""))
	var encryption_key := String(config.get("encryption_key", ""))
	if encryption_key != "":
		creds.encryption_key = encryption_key

	NetLog.info(TAG, "Inicializando EOS...")
	var setup_ok: bool = await hp.setup_eos_async(creds)
	if not setup_ok:
		_fail("eosg_setup_failed")
		_starting = false
		return
	_setup_ok = true

	var login_ok := false
	var mode := login_mode.strip_edges().to_lower()
	match mode:
		"devtool":
			login_ok = await ha.login_devtool_async(
				String(config.get("devtool_host", "localhost:4545")),
				String(config.get("devtool_credential", "DarkerPlayer"))
			)
		"account_portal":
			login_ok = await ha.login_account_portal_async()
		"launcher":
			login_ok = await ha.login_launcher_async()
		_:
			var safe_name := display_name.strip_edges()
			if safe_name == "":
				safe_name = "Player"
			login_ok = await ha.login_anonymous_async(safe_name)

	if not login_ok:
		_fail("eosg_login_failed")
		_starting = false
		return

	_logged_in = true
	_starting = false
	NetLog.info(TAG, "EOS listo (modo %s, puid %s)" % [mode, String(ha.product_user_id)])
	availability_changed.emit(true)


func host_lobby_async(max_players: int, metadata: Dictionary) -> void:
	if not is_available():
		_fail("eosg_not_available")
		return
	var hl := get_node_or_null("/root/HLobbies")
	if hl == null:
		_fail("eosg_lobbies_missing")
		return

	var opts := EOS.Lobby.CreateLobbyOptions.new()
	opts.bucket_id = NetConfig.EOSG_BUCKET
	opts.max_lobby_members = clampi(max_players, 2, NetConfig.MAX_PLAYERS)
	opts.presence_enabled = true
	opts.enable_rtc_room = false
	opts.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	opts.allow_invites = true

	var lobby = await hl.create_lobby_async(opts)
	if lobby == null:
		_fail("eosg_lobby_create_failed")
		return

	_apply_metadata(lobby, metadata)
	lobby.allow_host_migration = false
	var updated: bool = await lobby.update_async()
	if not updated:
		NetLog.warn(TAG, "No se pudieron escribir todos los atributos del lobby.")
		return

	_bind_lobby(lobby)
	_host_puid = String(lobby.owner_product_user_id)
	NetLog.info(TAG, "Lobby EOS creado: %s" % lobby.lobby_id)
	lobby_created.emit(String(lobby.lobby_id))


func join_lobby_async(lobby_id: String) -> void:
	if not is_available():
		_fail("eosg_not_available")
		return
	var hl := get_node_or_null("/root/HLobbies")
	if hl == null:
		_fail("eosg_lobbies_missing")
		return

	var results = await hl.search_by_lobby_id_async(lobby_id)
	if results == null or results.is_empty():
		_fail("eosg_lobby_not_found")
		return
	var lobby = await hl.join_async(results[0])
	if lobby == null:
		_fail("eosg_lobby_join_failed")
		return

	_bind_lobby(lobby)
	_host_puid = String(lobby.owner_product_user_id)
	NetLog.info(TAG, "Lobby EOS unido: %s (host %s)" % [lobby.lobby_id, _host_puid])
	lobby_joined.emit(String(lobby.lobby_id))


func leave_lobby_async() -> void:
	if _lobby == null:
		return
	var lobby = _lobby
	_lobby = null
	_host_puid = ""
	if lobby != null and lobby.is_valid():
		await lobby.leave_async()
	lobby_left.emit(String(lobby.lobby_id))


func request_lobby_list_async(max_results: int, game_id_filter: String) -> void:
	if not is_available():
		lobby_list_received.emit([])
		return
	var hl := get_node_or_null("/root/HLobbies")
	if hl == null:
		lobby_list_received.emit([])
		return
	hl.max_search_results = maxi(1, max_results)
	var results = await hl.search_by_bucket_id_async(game_id_filter)
	var summaries: Array = []
	if results != null:
		for lobby in results:
			summaries.append(_summary_for(lobby))
	lobby_list_received.emit(summaries)


func create_host_peer() -> MultiplayerPeer:
	if not is_available():
		return null
	var peer = ClassDB.instantiate("EOSGMultiplayerPeer")
	if peer == null:
		_fail("eosg_peer_missing")
		return null
	var err: int = peer.create_server(NetConfig.EOSG_SOCKET)
	if err != OK:
		_fail("eosg_create_server_failed_%d" % err)
		return null
	return peer as MultiplayerPeer


func create_client_peer() -> MultiplayerPeer:
	if not is_available():
		return null
	if _host_puid == "":
		_fail("eosg_host_unknown")
		return null
	var peer = ClassDB.instantiate("EOSGMultiplayerPeer")
	if peer == null:
		_fail("eosg_peer_missing")
		return null
	var err: int = peer.create_client(NetConfig.EOSG_SOCKET, _host_puid)
	if err != OK:
		_fail("eosg_create_client_failed_%d" % err)
		return null
	return peer as MultiplayerPeer


func get_lobby_data(_lobby_id: String, key: String) -> String:
	return _attr(_lobby, key, "")


func is_lobby_owner() -> bool:
	if _lobby == null:
		return false
	return bool(_lobby.is_owner())


func get_lobby_id() -> String:
	if _lobby == null:
		return ""
	return String(_lobby.lobby_id)


func get_current_lobby_summary() -> Dictionary:
	if _lobby == null:
		return {}
	return _summary_for(_lobby)


# ── Internos ──

func _bind_lobby(lobby: Variant) -> void:
	_lobby = lobby
	if _connected_kick:
		return
	_connected_kick = true
	if lobby.has_signal("kicked_from_lobby"):
		lobby.kicked_from_lobby.connect(_on_kicked)


func _on_kicked() -> void:
	var old_id := String(_lobby.lobby_id) if _lobby != null else ""
	_lobby = null
	_host_puid = ""
	NetLog.info(TAG, "Expulsado o lobby destruido: %s" % old_id)
	lobby_left.emit(old_id)


func _apply_metadata(lobby: Variant, metadata: Dictionary) -> void:
	lobby.add_attribute(NetConfig.LOBBY_ATTR_NAME, String(metadata.get(NetConfig.LOBBY_ATTR_NAME, "Lobby")))
	lobby.add_attribute(NetConfig.LOBBY_ATTR_ROOM_NAME, String(metadata.get(NetConfig.LOBBY_ATTR_ROOM_NAME, metadata.get(NetConfig.LOBBY_ATTR_NAME, "Lobby"))))
	lobby.add_attribute(NetConfig.LOBBY_ATTR_HOST, String(metadata.get(NetConfig.LOBBY_ATTR_HOST, "")))
	lobby.add_attribute(NetConfig.LOBBY_ATTR_MAP, String(metadata.get(NetConfig.LOBBY_ATTR_MAP, "")))
	lobby.add_attribute(NetConfig.LOBBY_ATTR_MODE, String(metadata.get(NetConfig.LOBBY_ATTR_MODE, NetConfig.DEFAULT_MODE)))
	lobby.add_attribute(NetConfig.LOBBY_ATTR_MAX_PLAYERS, int(metadata.get(NetConfig.LOBBY_ATTR_MAX_PLAYERS, NetConfig.MAX_PLAYERS)))
	lobby.add_attribute(NetConfig.LOBBY_ATTR_GAME_ID, String(metadata.get(NetConfig.LOBBY_ATTR_GAME_ID, NetConfig.GAME_ID)))


func _summary_for(lobby: Variant) -> Dictionary:
	var name_text := _attr(lobby, NetConfig.LOBBY_ATTR_NAME, "")
	if name_text == "":
		name_text = "Lobby %s" % String(lobby.lobby_id)
	var mode_text := _attr(lobby, NetConfig.LOBBY_ATTR_MODE, NetConfig.DEFAULT_MODE)
	var max_players := int(_attr(lobby, NetConfig.LOBBY_ATTR_MAX_PLAYERS, str(NetConfig.MAX_PLAYERS)))
	return OnlineProviderService.make_summary(
		String(lobby.lobby_id),
		NetEnums.provider_to_id(NetEnums.Provider.EOSG),
		name_text,
		_attr(lobby, NetConfig.LOBBY_ATTR_HOST, ""),
		_attr(lobby, NetConfig.LOBBY_ATTR_MAP, ""),
		mode_text,
		lobby.members.size(),
		max_players
	)


func _attr(lobby: Variant, key: String, fallback: String) -> String:
	if lobby == null:
		return fallback
	var attr = lobby.get_attribute(key)
	if typeof(attr) != TYPE_DICTIONARY or attr.is_empty():
		return fallback
	return String(attr.get("value", fallback))


func _fail(reason: String) -> void:
	NetLog.warn(TAG, "Fallo: %s" % reason)
	failed.emit(reason)
