extends Node

signal setting_changed(key: String, value: Variant)

const SETTINGS_PATH := "user://settings.cfg"

var music_volume: float = 1.0:
	set(v):
		music_volume = v
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Music"), linear_to_db(v))
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

var fog_enabled: bool = true:
	set(v):
		fog_enabled = v
		setting_changed.emit("fog_enabled", v)

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
	vhs_enabled = cfg.get_value("video", "vhs_enabled", true)
	fog_enabled = cfg.get_value("video", "fog_enabled", true)
	display_mode = cfg.get_value("video", "display_mode", 3)
	first_launch_done = cfg.get_value("profile", "first_launch_done", false)
	player_name = cfg.get_value("profile", "player_name", "")
	vessel_data = cfg.get_value("profile", "vessel_data", {})
	favorite_color = cfg.get_value("profile", "favorite_color", "")


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("network", "network_mode", network_mode)
	cfg.set_value("video", "vhs_enabled", vhs_enabled)
	cfg.set_value("video", "fog_enabled", fog_enabled)
	cfg.set_value("video", "display_mode", display_mode)
	cfg.set_value("profile", "first_launch_done", first_launch_done)
	cfg.set_value("profile", "player_name", player_name)
	cfg.set_value("profile", "vessel_data", vessel_data)
	cfg.set_value("profile", "favorite_color", favorite_color)
	cfg.save(SETTINGS_PATH)
	print("[SettingsManager] Configuración guardada")
	
# Agrega esta función al final de tu SettingsManager.gd
func complete_goner_creation(p_name: String, v_data: Dictionary, fav_color: String) -> void:
	player_name = p_name
	vessel_data = v_data
	favorite_color = fav_color
	first_launch_done = true
	save_settings()
