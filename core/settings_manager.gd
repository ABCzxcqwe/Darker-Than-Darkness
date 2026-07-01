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
		if v == 0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		elif v == 3:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		setting_changed.emit("display_mode", v)

var vhs_enabled: bool = true:
	set(v):
		vhs_enabled = v
		setting_changed.emit("vhs_enabled", v)

var fog_enabled: bool = true:
	set(v):
		fog_enabled = v
		setting_changed.emit("fog_enabled", v)


func _ready() -> void:
	load_settings()


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


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("network", "network_mode", network_mode)
	cfg.set_value("video", "vhs_enabled", vhs_enabled)
	cfg.set_value("video", "fog_enabled", fog_enabled)
	cfg.save(SETTINGS_PATH)
	print("[SettingsManager] Configuración guardada")
