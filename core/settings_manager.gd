extends Node

signal setting_changed(key: String, value: Variant)

const SETTINGS_PATH := "user://settings.cfg"

var music_volume: float = 1.0:
	set(v):
		music_volume = v
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Music"), linear_to_db(v))
		var menu_idx := AudioServer.get_bus_index(&"Menu Music")
		if menu_idx != -1:
			AudioServer.set_bus_volume_db(menu_idx, linear_to_db(v))
		setting_changed.emit("music_volume", v)

var sfx_volume: float = 1.0:
	set(v):
		sfx_volume = v
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"SFX"), linear_to_db(v))
		setting_changed.emit("sfx_volume", v)

var network_mode: int = 0:
	set(v):
		network_mode = v
		setting_changed.emit("network_mode", v)

var display_mode: int = 3:
	set(v):
		display_mode = v
		call_deferred("_apply_display_mode", v)
		setting_changed.emit("display_mode", v)


func _apply_display_mode(v: int) -> void:
	if v == 0:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	elif v == 3:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

var vhs_enabled: bool = true:
	set(v):
		vhs_enabled = v
		setting_changed.emit("vhs_enabled", v)

var brightness: float = 1.0:
	set(v):
		brightness = clampf(v, 0.5, 1.5)
		setting_changed.emit("brightness", v)

var language: String = "es":
	set(v):
		# Idioma bloqueado a es hasta tener traducciones
		language = "es"
		TranslationServer.set_locale("es")
		setting_changed.emit("language", "es")

var first_launch_done: bool = false:
	set(v):
		first_launch_done = v
		setting_changed.emit("first_launch_done", v)

var player_name: String = "":
	set(v):
		player_name = v
		setting_changed.emit("player_name", v)

var vessel_data: Dictionary = {}:
	set(v):
		vessel_data = v
		setting_changed.emit("vessel_data", v)

var favorite_color: String = "":
	set(v):
		favorite_color = v
		setting_changed.emit("favorite_color", v)

var lan_server_ip: String = "127.0.0.1":
	set(v):
		lan_server_ip = v
		setting_changed.emit("lan_server_ip", v)

var dedicated_server_ip: String = "":
	set(v):
		dedicated_server_ip = v
		setting_changed.emit("dedicated_server_ip", v)

var online_provider: String = "steam":
	set(v):
		online_provider = v.to_lower()
		setting_changed.emit("online_provider", v)

var menu_theme: String = "green_drone":
	set(v):
		menu_theme = v.to_lower()
		setting_changed.emit("menu_theme", v)

var unlocked_themes: PackedStringArray = PackedStringArray(["green_drone"]):
	set(v):
		unlocked_themes = v
		setting_changed.emit("unlocked_themes", v)


func is_first_launch() -> bool:
	return not first_launch_done


func _ready() -> void:
	load_settings()
	var actual_mode := DisplayServer.window_get_mode()
	if actual_mode != display_mode:
		display_mode = actual_mode


func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		print("[SettingsManager] No se encontró settings.cfg, usando valores por defecto")
		return

	music_volume = cfg.get_value("audio", "music_volume", 1.0)
	sfx_volume = cfg.get_value("audio", "sfx_volume", 1.0)
	network_mode = cfg.get_value("network", "network_mode", 0)
	lan_server_ip = cfg.get_value("network", "lan_server_ip", "127.0.0.1")
	dedicated_server_ip = cfg.get_value("network", "dedicated_server_ip", "")
	online_provider = str(cfg.get_value("network", "online_provider", "steam")).to_lower()
	if online_provider == "":
		online_provider = "steam"
	vhs_enabled = cfg.get_value("video", "vhs_enabled", true)
	brightness = cfg.get_value("video", "brightness", 1.0)
	display_mode = cfg.get_value("video", "display_mode", 3)
	language = cfg.get_value("general", "language", "es")
	first_launch_done = cfg.get_value("profile", "first_launch_done", false)
	player_name = cfg.get_value("profile", "player_name", "")
	vessel_data = cfg.get_value("profile", "vessel_data", {})
	favorite_color = cfg.get_value("profile", "favorite_color", "")
	menu_theme = str(cfg.get_value("theme", "menu_theme", "green_drone")).to_lower()
	if menu_theme == "":
		menu_theme = "green_drone"
	var ut: Variant = cfg.get_value("theme", "unlocked_themes", PackedStringArray(["green_drone"]))
	if ut is PackedStringArray:
		unlocked_themes = ut
	elif ut is Array:
		unlocked_themes = PackedStringArray(ut)
	else:
		unlocked_themes = PackedStringArray(["green_drone"])
	if not unlocked_themes.has("green_drone"):
		unlocked_themes.append("green_drone")


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("network", "network_mode", network_mode)
	cfg.set_value("network", "lan_server_ip", lan_server_ip)
	cfg.set_value("network", "dedicated_server_ip", dedicated_server_ip)
	cfg.set_value("network", "online_provider", online_provider)
	cfg.set_value("video", "vhs_enabled", vhs_enabled)
	cfg.set_value("video", "brightness", brightness)
	cfg.set_value("video", "display_mode", display_mode)
	cfg.set_value("general", "language", language)
	cfg.set_value("profile", "first_launch_done", first_launch_done)
	cfg.set_value("profile", "player_name", player_name)
	cfg.set_value("profile", "vessel_data", vessel_data)
	cfg.set_value("profile", "favorite_color", favorite_color)
	cfg.set_value("theme", "menu_theme", menu_theme)
	cfg.set_value("theme", "unlocked_themes", unlocked_themes)
	cfg.save(SETTINGS_PATH)
	print("[SettingsManager] Configuración guardada")

func is_theme_unlocked(id: String) -> bool:
	return unlocked_themes.has(id.to_lower())

func unlock_theme(id: String) -> bool:
	var nid := id.to_lower()
	if unlocked_themes.has(nid):
		return false
	unlocked_themes.append(nid)
	save_settings()
	return true

func try_set_theme(id: String) -> bool:
	var nid := id.to_lower()
	if not is_theme_unlocked(nid):
		return false
	menu_theme = nid
	save_settings()
	return true
	
# Agrega esta función al final de tu SettingsManager.gd
func complete_goner_creation(p_name: String, v_data: Dictionary, fav_color: String) -> void:
	player_name = p_name
	vessel_data = v_data
	favorite_color = fav_color
	first_launch_done = true
	save_settings()
