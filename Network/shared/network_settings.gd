class_name NetworkSettings
extends RefCounted
## Fachada tipada sobre los campos de red de `SettingsManager`.
##
## `SettingsManager` sigue siendo el dueño de la persistencia (settings.cfg).
## Esta clase convierte los valores crudos (int/String) a NetEnums y aplica
## saneo/normalización, para que la UI y los autoloads no repitan esa lógica.

const SETTINGS_NODE := "/root/SettingsManager"


static func _settings() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(SETTINGS_NODE)


static func get_mode() -> NetEnums.Mode:
	var sm := _settings()
	if sm == null:
		return NetEnums.Mode.LAN
	return NetEnums.Mode.ONLINE if int(sm.network_mode) == 1 else NetEnums.Mode.LAN


static func set_mode(mode: NetEnums.Mode) -> void:
	var sm := _settings()
	if sm == null:
		return
	sm.network_mode = 1 if mode == NetEnums.Mode.ONLINE else 0


static func get_provider() -> NetEnums.Provider:
	var sm := _settings()
	if sm == null:
		return NetEnums.Provider.STEAM
	var id := String(sm.online_provider).strip_edges().to_lower()
	if id.is_empty():
		return NetEnums.Provider.STEAM
	var provider := NetEnums.provider_from_id(id)
	return provider if provider != NetEnums.Provider.DISABLE else NetEnums.Provider.STEAM


static func set_provider(provider: NetEnums.Provider) -> void:
	var sm := _settings()
	if sm == null or provider == NetEnums.Provider.DISABLE:
		return
	sm.online_provider = NetEnums.provider_to_id(provider)


static func get_player_name() -> String:
	var sm := _settings()
	if sm == null:
		return ""
	return PlayerInfo.sanitize_name(String(sm.player_name), "")


static func set_player_name(name: String) -> void:
	var sm := _settings()
	if sm == null:
		return
	sm.player_name = PlayerInfo.sanitize_name(name, "")


static func get_coordinator_url() -> String:
	var sm := _settings()
	if sm == null:
		return NetConfig.COORDINATOR_URL_DEFAULT
	var url := normalize_url(String(sm.coordinator_url))
	return url if url != "" else NetConfig.COORDINATOR_URL_DEFAULT


static func set_coordinator_url(url: String) -> void:
	var sm := _settings()
	if sm == null:
		return
	var clean := normalize_url(url)
	sm.coordinator_url = clean if clean != "" else NetConfig.COORDINATOR_URL_DEFAULT


static func get_lan_server_ip() -> String:
	var sm := _settings()
	if sm == null:
		return NetConfig.LAN_SERVER_IP_DEFAULT
	var ip := String(sm.lan_server_ip).strip_edges()
	return ip if ip != "" else NetConfig.LAN_SERVER_IP_DEFAULT


static func set_lan_server_ip(ip: String) -> void:
	var sm := _settings()
	if sm == null:
		return
	var clean := ip.strip_edges()
	sm.lan_server_ip = clean if clean != "" else NetConfig.LAN_SERVER_IP_DEFAULT


static func get_dedicated_server_ip() -> String:
	var sm := _settings()
	if sm == null:
		return ""
	return String(sm.dedicated_server_ip).strip_edges()


static func set_dedicated_server_ip(ip: String) -> void:
	var sm := _settings()
	if sm == null:
		return
	sm.dedicated_server_ip = ip.strip_edges()


static func normalize_url(url: String) -> String:
	var clean := url.strip_edges()
	while clean.ends_with("/"):
		clean = clean.left(clean.length() - 1)
	return clean
