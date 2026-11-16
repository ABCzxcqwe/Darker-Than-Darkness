class_name EOSGProvider
extends OnlineProviderService
## Proveedor online basado en Epic Online Services Godot (EOSG).
##
## No referencia directamente a EOSG/EOS: todo el código que toca el SDK vive
## en `eosg_bridge.gd`, que se carga con `load()` solo si el addon existe. Sin
## addon o sin credenciales el proveedor queda inactivo y no se lista en la UI.
##
## Credenciales: `user://eosg.cfg` (sección `[eos]`) o variables de entorno.
## Nunca versionar ese archivo.

const TAG := "EOSG"

const REQUIRED_KEYS := [
	"product_id",
	"sandbox_id",
	"deployment_id",
	"client_id",
	"client_secret",
]

var _bridge: Node = null
var _config: Dictionary = {}
var _login_mode := "anonymous"
var _display_name := ""
var _available := false
var _initializing := false
var _addon_present := false
var _current_lobby_id := ""


func _init() -> void:
	provider_id = NetEnums.Provider.EOSG
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_addon_present = (
		ClassDB.class_exists("EOSGMultiplayerPeer")
		or FileAccess.file_exists(NetConfig.EOSG_ADDON_PLUGIN)
	)
	_load_config()
	_create_bridge()
	if is_configured():
		# Diferido: deja que SettingsManager termine de cargar el nombre.
		initialize.call_deferred()
	else:
		NetLog.debug(TAG, "Estado EOSG | addon=%s bridge=%s credenciales=%s" % [
			str(_addon_present), str(_bridge != null), str(has_credentials())
		])


func has_credentials() -> bool:
	for key in REQUIRED_KEYS:
		if String(_config.get(key, "")).strip_edges() == "":
			return false
	return true


func is_configured() -> bool:
	return _bridge != null and has_credentials()


func is_available() -> bool:
	return _available


func initialize() -> bool:
	if _available:
		return true
	if not is_configured():
		NetLog.debug(TAG, "EOSG no configurado (faltan credenciales o addon).")
		return false
	if _initializing:
		return false
	_initializing = true
	_display_name = NetworkSettings.get_player_name()
	if _display_name == "":
		_display_name = "Player"
	NetLog.info(TAG, "Iniciando EOSG (login: %s)..." % _login_mode)
	_bridge.start_async(_config, _login_mode, _display_name)
	return false


func initialize_async() -> bool:
	return initialize()


func host_lobby(max_players: int, metadata: Dictionary) -> bool:
	if not _available:
		NetLog.warn(TAG, "No se puede crear lobby: EOSG no disponible.")
		return false
	_bridge.host_lobby_async(max_players, metadata)
	return true


func join_lobby(lobby_id: String) -> bool:
	if not _available or lobby_id.strip_edges() == "":
		return false
	_bridge.join_lobby_async(lobby_id)
	return true


func leave_lobby() -> void:
	if _bridge != null:
		_bridge.leave_lobby_async()
	_current_lobby_id = ""


func request_lobby_list(max_results: int, _game_id_filter: String) -> void:
	if _bridge == null or not _available:
		return
	# EOS busca por bucket; el bucket del juego no lleva guiones bajos.
	_bridge.request_lobby_list_async(max_results, NetConfig.EOSG_BUCKET)


func create_host_peer(lobby_id: String) -> MultiplayerPeer:
	if _bridge == null:
		return null
	var peer: MultiplayerPeer = _bridge.create_host_peer()
	if peer != null:
		_current_lobby_id = lobby_id
	return peer


func create_client_peer(lobby_id: String) -> MultiplayerPeer:
	if _bridge == null:
		return null
	var peer: MultiplayerPeer = _bridge.create_client_peer()
	if peer != null:
		_current_lobby_id = lobby_id
	return peer


func get_lobby_data(lobby_id: String, key: String) -> String:
	if _bridge == null:
		return ""
	return String(_bridge.get_lobby_data(lobby_id, key))


func is_lobby_owner(_lobby_id: String) -> bool:
	if _bridge == null:
		return false
	return bool(_bridge.is_lobby_owner())


func get_lobby_id() -> String:
	if _current_lobby_id != "":
		return _current_lobby_id
	if _bridge == null:
		return ""
	return String(_bridge.get_lobby_id())


func get_current_lobby_summary() -> Dictionary:
	if _bridge == null:
		return {}
	return _bridge.get_current_lobby_summary() as Dictionary


# ── Configuración ──

func _load_config() -> void:
	_config.clear()
	var source := "none"
	var cfg := ConfigFile.new()

	# 1) Override del usuario.
	if cfg.load(NetConfig.EOSG_CONFIG_PATH) == OK:
		_read_config(cfg)
		source = "user"

	# 2) Fallback empaquetado en el build. Solo se usa si el usuario no tiene
	#    una configuración completa.
	if not has_credentials():
		var bundled := ConfigFile.new()
		if bundled.load(NetConfig.EOSG_BUNDLED_CONFIG_PATH) == OK:
			_read_config(bundled)
			cfg = bundled
			source = "bundled"

	_login_mode = String(cfg.get_value("eos", "login_mode", "anonymous")).strip_edges().to_lower()
	if _login_mode == "":
		_login_mode = "anonymous"

	# Variables de entorno: útiles para CI y para no guardar secretos en user://.
	_config["product_id"] = _env_or("EOS_PRODUCT_ID", String(_config.get("product_id", "")))
	_config["sandbox_id"] = _env_or("EOS_SANDBOX_ID", String(_config.get("sandbox_id", "")))
	_config["deployment_id"] = _env_or("EOS_DEPLOYMENT_ID", String(_config.get("deployment_id", "")))
	_config["client_id"] = _env_or("EOS_CLIENT_ID", String(_config.get("client_id", "")))
	_config["client_secret"] = _env_or("EOS_CLIENT_SECRET", String(_config.get("client_secret", "")))

	if not _addon_present:
		NetLog.debug(TAG, "Addon EOSG no instalado en %s." % NetConfig.EOSG_ADDON_PATH)
	elif has_credentials():
		NetLog.debug(TAG, "Credenciales EOSG cargadas desde %s; login %s." % [source, _login_mode])
	else:
		NetLog.info(TAG, "EOSG instalado pero sin credenciales; proveedor oculto.")


func _read_config(cfg: ConfigFile) -> void:
	_config.clear()
	for key in [
		"product_name", "product_version", "product_id", "sandbox_id",
		"deployment_id", "client_id", "client_secret", "encryption_key",
		"login_mode", "devtool_host", "devtool_credential",
	]:
		_config[key] = String(cfg.get_value("eos", key, ""))


func _create_bridge() -> void:
	if not _addon_present:
		return
	if not ResourceLoader.exists(NetConfig.EOSG_BRIDGE_PATH):
		NetLog.error(TAG, "No se encontró el puente EOSG en %s." % NetConfig.EOSG_BRIDGE_PATH)
		return
	var bridge_script := load(NetConfig.EOSG_BRIDGE_PATH)
	if bridge_script == null:
		NetLog.error(TAG, "No se pudo cargar el puente EOSG.")
		return
	_bridge = bridge_script.new()
	if _bridge == null:
		NetLog.error(TAG, "No se pudo instanciar el puente EOSG.")
		return
	add_child(_bridge)
	_bridge.availability_changed.connect(_on_bridge_availability)
	_bridge.lobby_created.connect(_on_bridge_lobby_created)
	_bridge.lobby_joined.connect(_on_bridge_lobby_joined)
	_bridge.lobby_list_received.connect(_on_bridge_lobby_list)
	_bridge.lobby_left.connect(_on_bridge_lobby_left)
	_bridge.failed.connect(_on_bridge_failed)


func _env_or(key: String, fallback: String) -> String:
	var value := OS.get_environment(key).strip_edges()
	return value if value != "" else fallback


# ── Señales del puente ──

func _on_bridge_availability(value: bool) -> void:
	_available = value
	_initializing = false
	availability_changed.emit(value)


func _on_bridge_lobby_created(lobby_id: String) -> void:
	_current_lobby_id = lobby_id
	lobby_created.emit(lobby_id)


func _on_bridge_lobby_joined(lobby_id: String) -> void:
	_current_lobby_id = lobby_id
	lobby_joined.emit(lobby_id)


func _on_bridge_lobby_list(lobbies: Array) -> void:
	lobby_list_received.emit(lobbies)


func _on_bridge_lobby_left(lobby_id: String) -> void:
	_current_lobby_id = ""
	lobby_left.emit(lobby_id)


func _exit_tree() -> void:
	if _bridge != null and _current_lobby_id != "":
		_bridge.leave_lobby_async()


func _on_bridge_failed(reason: String) -> void:
	_initializing = false
	NetLog.warn(TAG, "El proveedor falló: %s" % reason)
	# Un fallo de setup/login no es un error de conexión: solo ocultamos el
	# proveedor. La UI no debe recibir connection_failed por esto.
	if reason in [
		"eosg_peer_missing", "eosg_autoloads_missing",
		"eosg_setup_failed", "eosg_login_failed",
	]:
		_available = false
		availability_changed.emit(false)
		return
	failed.emit(reason)
