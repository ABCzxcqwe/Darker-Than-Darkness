extends Node

signal setting_changed(key: String, value: Variant)

const SETTINGS_PATH := "user://settings.cfg"

var music_volume: float = 1.0:
	set(v):
		music_volume = v
		var mus_idx := AudioServer.get_bus_index(&"Music")
		var db := linear_to_db(v)
		AudioServer.set_bus_volume_db(mus_idx, db)
		var menu_idx := AudioServer.get_bus_index(&"Menu Music")
		if menu_idx != -1:
			AudioServer.set_bus_volume_db(menu_idx, db)
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
	match v:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		3:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		4:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

var vhs_enabled: bool = true:
	set(v):
		vhs_enabled = v
		setting_changed.emit("vhs_enabled", v)

var brightness: float = 1.0:
	set(v):
		brightness = clampf(v, 0.5, 1.5)
		setting_changed.emit("brightness", brightness)

var fog_enabled: bool = true:
	set(v):
		fog_enabled = v
		setting_changed.emit("fog_enabled", v)

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

var menu_theme: String = "device":
	set(v):
		var nid := v.to_lower()
		# alias legacy green_drone -> device
		if nid == "green_drone":
			nid = "device"
		menu_theme = nid
		setting_changed.emit("menu_theme", nid)

var unlocked_themes: PackedStringArray = PackedStringArray(["device", "light"]):
	set(v):
		unlocked_themes = v
		setting_changed.emit("unlocked_themes", v)

var wins_by_character: Dictionary = {}:
	set(v):
		wins_by_character = v
		setting_changed.emit("wins_by_character", v)


func is_first_launch() -> bool:
	return not first_launch_done


func _ready() -> void:
	load_settings()
	# Aplicar modo guardado a la ventana, no pisar el setting con el estado actual
	var actual_mode := DisplayServer.window_get_mode()
	if actual_mode != display_mode:
		_apply_display_mode(display_mode)


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
	fog_enabled = cfg.get_value("video", "fog_enabled", true)
	display_mode = cfg.get_value("video", "display_mode", 3)
	language = cfg.get_value("general", "language", "es")
	first_launch_done = cfg.get_value("profile", "first_launch_done", false)
	player_name = cfg.get_value("profile", "player_name", "")
	vessel_data = cfg.get_value("profile", "vessel_data", {})
	favorite_color = cfg.get_value("profile", "favorite_color", "")
	menu_theme = str(cfg.get_value("theme", "menu_theme", "device")).to_lower()
	if menu_theme == "green_drone":
		menu_theme = "device"
	if menu_theme == "":
		menu_theme = "device"
	var ut: Variant = cfg.get_value("theme", "unlocked_themes", PackedStringArray(["device", "light"]))
	if ut is PackedStringArray:
		unlocked_themes = ut
	elif ut is Array:
		unlocked_themes = PackedStringArray(ut)
	else:
		unlocked_themes = PackedStringArray(["device", "light"])
	# migrar alias green_drone -> device
	for i in unlocked_themes.size():
		if unlocked_themes[i].to_lower() == "green_drone":
			unlocked_themes[i] = "device"
	if not unlocked_themes.has("device"):
		unlocked_themes.append("device")
	if not unlocked_themes.has("light"):
		unlocked_themes.append("light")
	# progreso victorias por personaje
	var wbc: Variant = cfg.get_value("progress", "wins_by_character", {})
	if wbc is Dictionary:
		wins_by_character = wbc
	else:
		wins_by_character = {}


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
	cfg.set_value("video", "fog_enabled", fog_enabled)
	cfg.set_value("video", "display_mode", display_mode)
	cfg.set_value("general", "language", language)
	cfg.set_value("profile", "first_launch_done", first_launch_done)
	cfg.set_value("profile", "player_name", player_name)
	cfg.set_value("profile", "vessel_data", vessel_data)
	cfg.set_value("profile", "favorite_color", favorite_color)
	cfg.set_value("theme", "menu_theme", menu_theme)
	cfg.set_value("theme", "unlocked_themes", unlocked_themes)
	cfg.set_value("progress", "wins_by_character", wins_by_character)
	cfg.save(SETTINGS_PATH)
	print("[SettingsManager] Configuración guardada")

func is_theme_unlocked(id: String) -> bool:
	var nid := id.to_lower()
	if nid == "green_drone":
		nid = "device"
	return unlocked_themes.has(nid)

func unlock_theme(id: String) -> bool:
	var nid := id.to_lower()
	if nid == "green_drone":
		nid = "device"
	if unlocked_themes.has(nid):
		return false
	unlocked_themes.append(nid)
	# auto-activar al desbloquear (un solo save)
	menu_theme = nid
	save_settings()
	return true

func try_set_theme(id: String) -> bool:
	var nid := id.to_lower()
	if nid == "green_drone":
		nid = "device"
	if not is_theme_unlocked(nid):
		return false
	menu_theme = nid
	save_settings()
	return true

func record_win_for_character(char_id: int) -> bool:
	var key := str(char_id)
	if wins_by_character.has(key):
		return false
	wins_by_character[key] = true
	# trigger para que ThemeManager re-evalúe si se puede desbloquear light
	wins_by_character = wins_by_character.duplicate()
	save_settings()
	_check_light_unlock()
	return true

func has_won_with_character(char_id: int) -> bool:
	return wins_by_character.has(str(char_id))

func has_won_with_all_characters() -> bool:
	var cr := get_node_or_null("/root/CharacterRegistry")
	if cr == null or not cr.has_method("get_all"):
		return false
	for data in cr.get_all():
		if data == null:
			continue
		if not wins_by_character.has(str(data.id)):
			return false
	return cr.get_all().size() > 0

func _check_light_unlock() -> void:
	if is_theme_unlocked("light"):
		return
	if has_won_with_all_characters():
		unlock_theme("light")
		print("[SettingsManager] ¡Tema LIGHT desbloqueado! Ganaste con todos los personajes.")

func debug_unlock_all_themes() -> void:
	for tid in ["device", "light"]:
		if not unlocked_themes.has(tid):
			unlocked_themes.append(tid)
	wins_by_character = {}
	# marcar todas las victorias para test
	var cr2 := get_node_or_null("/root/CharacterRegistry")
	if cr2:
		for d in cr2.get_all():
			if d:
				wins_by_character[str(d.id)] = true
	save_settings()
	
# Agrega esta función al final de tu SettingsManager.gd
func complete_goner_creation(p_name: String, v_data: Dictionary, fav_color: String) -> void:
	player_name = p_name
	vessel_data = v_data
	favorite_color = fav_color
	first_launch_done = true
	save_settings()
