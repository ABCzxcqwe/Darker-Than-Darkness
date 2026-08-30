extends Node
## ThemeManager — resuelve tema del menú (paleta + música + fondo animado).
## Carga MenuThemeData .tres desde ui/MainMenu/themes/*/ + alias legacy.

const MenuThemeDataScript = preload("res://core/MenuThemeData.gd")

const DEFAULT_THEME := "device"
const LEGACY_ALIAS := {"green_drone": "device"}

# Temas cargados dinámicamente: id lowercase -> Resource
var _themes: Dictionary = {}
var _fallback_themes: Dictionary = {
	"device": {
		"label": "DEVICE",
		"border_color": Color(0, 0.5019608, 0, 1),
		"hint_color": Color(0, 1, 0, 1),
		"dim_color": Color(0, 0.50196081, 0, 1),
		"bg_color": Color(0, 0, 0, 1),
		"music": "res://ui/Boot/scenes/AUDIO_DRONE.wav",
		"sfx_profile": "deltarune",
	},
}

signal theme_changed(id: String)

var current_theme_id: String = DEFAULT_THEME:
	set(v):
		var nid := _normalize_id(v)
		if nid == current_theme_id:
			return
		current_theme_id = nid
		theme_changed.emit(current_theme_id)
		var am := get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_menu_drone"):
			if am.current_global_state == "menu_drone" or am.current_global_state == "menu":
				am.play_menu_drone(get_music_path(nid))

func _normalize_id(raw: String) -> String:
	var nid := raw.to_lower().strip_edges()
	if LEGACY_ALIAS.has(nid):
		nid = LEGACY_ALIAS[nid]
	if _themes.has(nid):
		return nid
	if _fallback_themes.has(nid):
		return nid
	return DEFAULT_THEME

func _ready() -> void:
	_load_themes()
	var sm := get_node_or_null("/root/SettingsManager")
	if sm:
		if "menu_theme" in sm:
			var nid: String = _normalize_id(str(sm.menu_theme))
			if is_theme_unlocked(nid):
				current_theme_id = nid
			else:
				current_theme_id = DEFAULT_THEME
		if sm.has_signal("setting_changed"):
			sm.setting_changed.connect(_on_setting_changed)
	theme_changed.connect(_on_theme_changed_forward_audio)

func _load_themes() -> void:
	_themes.clear()
	var base := "res://ui/MainMenu/themes"
	var dir := DirAccess.open(base)
	if dir == null:
		push_warning("[ThemeManager] No se pudo abrir " + base)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var p := base + "/" + fname
			var res = load(p)
			if res and "id" in res and str(res.id) != "":
				_themes[str(res.id).to_lower()] = res
			elif res:
				push_warning("[ThemeManager] .tres sin id: " + p)
		elif dir.current_is_dir() and not fname.begins_with("."):
			var sub := base + "/" + fname
			var sd := DirAccess.open(sub)
			if sd:
				sd.list_dir_begin()
				var sf := sd.get_next()
				while sf != "":
					if sf.ends_with(".tres"):
						var p2 := sub + "/" + sf
						var r2 = load(p2)
						if r2 and "id" in r2 and str(r2.id) != "":
							_themes[str(r2.id).to_lower()] = r2
					sf = sd.get_next()
				sd.list_dir_end()
		fname = dir.get_next()
	dir.list_dir_end()
	if _themes.is_empty():
		push_warning("[ThemeManager] No se cargó ningún MenuThemeData, usando fallback")
	print("[ThemeManager] Temas cargados: ", _themes.keys())

func _on_theme_changed_forward_audio(_id: String) -> void:
	pass

func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "menu_theme":
		var nid := _normalize_id(str(value))
		if _themes.has(nid) or _fallback_themes.has(nid):
			current_theme_id = nid
	elif key == "unlocked_themes":
		pass

func get_theme(id: String = current_theme_id) -> Variant:
	var nid := _normalize_id(id)
	if _themes.has(nid):
		return _themes[nid]
	if _fallback_themes.has(nid):
		return _fallback_themes[nid]
	if _themes.has(DEFAULT_THEME):
		return _themes[DEFAULT_THEME]
	return _fallback_themes[DEFAULT_THEME]

func get_theme_data(id: String = current_theme_id) -> Resource:
	var t = get_theme(id)
	if t != null and t is Resource and t.get_script() == MenuThemeDataScript:
		return t
	return null

func get_music_path(id: String = current_theme_id) -> String:
	var t = get_theme(id)
	if t != null and t is Resource and "music" in t:
		var m = t.music
		if m != null and m.resource_path != "":
			return m.resource_path
		return "res://ui/Boot/scenes/AUDIO_DRONE.wav"
	if t is Dictionary:
		return str(t.get("music", _fallback_themes[DEFAULT_THEME]["music"]))
	return "res://ui/Boot/scenes/AUDIO_DRONE.wav"

func get_palette(id: String = current_theme_id) -> Dictionary:
	var t = get_theme(id)
	if t != null and t is Resource and "border_color" in t:
		return {
			"border": t.border_color,
			"title": t.title_color,
			"hint": t.hint_color,
			"dim": t.dim_color,
			"selected": t.selected_color,
			"separator": t.separator_color,
			"bg": t.bg_color,
		}
	if t is Dictionary:
		return {
			"border": t["border_color"],
			"title": t.get("hint_color", t["border_color"]),
			"hint": t["hint_color"],
			"dim": t["dim_color"],
			"selected": t.get("hint_color", t["dim_color"]),
			"separator": t["border_color"],
			"bg": t["bg_color"],
		}
	return get_palette(DEFAULT_THEME)

func get_sfx_profile(id: String = current_theme_id) -> String:
	var t = get_theme(id)
	if t != null and t is Resource and "sfx_profile" in t:
		return str(t.sfx_profile)
	if t is Dictionary:
		return str(t.get("sfx_profile", "deltarune"))
	return "deltarune"

func get_font(id: String = current_theme_id) -> FontFile:
	var t = get_theme(id)
	if t != null and t is Resource and "font" in t:
		return t.font as FontFile
	return null

func get_soul_texture(id: String = current_theme_id) -> Texture2D:
	var t = get_theme(id)
	if t != null and t is Resource and "soul_texture" in t:
		return t.soul_texture as Texture2D
	return null

func get_background_scene(id: String = current_theme_id) -> PackedScene:
	var t = get_theme(id)
	if t != null and t is Resource and "background_scene" in t:
		return t.background_scene as PackedScene
	return null

func list_all_ids() -> PackedStringArray:
	var arr := PackedStringArray()
	for k in _themes.keys():
		arr.append(k)
	if arr.is_empty():
		for k in _fallback_themes.keys():
			arr.append(k)
	return arr

func list_all_labels() -> PackedStringArray:
	var arr := PackedStringArray()
	for k in _themes.keys():
		var d = _themes[k]
		var lbl: String = str(k).to_upper()
		if d != null and "label" in d and str(d.label) != "":
			lbl = str(d.label)
		arr.append(lbl)
	if arr.is_empty():
		for k in _fallback_themes.keys():
			arr.append(str(_fallback_themes[k].get("label", str(k).to_upper())))
	return arr

func list_unlocked() -> PackedStringArray:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and "unlocked_themes" in sm:
		var raw: PackedStringArray = sm.unlocked_themes
		var out := PackedStringArray()
		for id in raw:
			out.append(_normalize_id(str(id)))
		return out
	return PackedStringArray([DEFAULT_THEME])

func is_theme_unlocked(id: String) -> bool:
	var nid := _normalize_id(id)
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and sm.has_method("is_theme_unlocked"):
		return sm.is_theme_unlocked(nid)
	return nid == DEFAULT_THEME

func try_unlock(id: String) -> bool:
	var nid := _normalize_id(id)
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and sm.has_method("unlock_theme"):
		var ok: bool = sm.unlock_theme(nid)
		if ok and sm.has_method("try_set_theme"):
			sm.try_set_theme(nid)
		return ok
	return false

func apply_to_background(bg_node: Control, id: String = current_theme_id) -> void:
	if bg_node == null:
		return
	for c in bg_node.get_children():
		if str(c.name).begins_with("ThemeBg_"):
			c.queue_free()
	var scene: PackedScene = get_background_scene(id)
	if scene:
		var inst: Control = scene.instantiate() as Control
		if inst:
			inst.name = "ThemeBg_" + id
			inst.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inst.set_anchors_preset(Control.PRESET_FULL_RECT)
			bg_node.add_child(inst)
			if bg_node is ColorRect:
				(bg_node as ColorRect).color = Color.TRANSPARENT
		return
	var palette := get_palette(id)
	if bg_node is ColorRect:
		(bg_node as ColorRect).color = palette["bg"]
	else:
		bg_node.modulate = palette["bg"]

func make_box_style(id: String = current_theme_id) -> StyleBoxFlat:
	var palette := get_palette(id)
	var sb := StyleBoxFlat.new()
	sb.bg_color = palette["bg"]
	sb.border_color = palette["border"]
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.anti_aliasing = false
	return sb
