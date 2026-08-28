extends Node
## ThemeManager — resuelve tema del menú (paleta + música).
## Por ahora solo "green_drone" (verde Deltarune + AUDIO_DRONE).
## Futuro: desbloquear temas y cambiar música/box dinámicamente.

const DEFAULT_THEME := "green_drone"

# Definición estática de temas. Clave = id en minúsculas.
const THEMES := {
	"green_drone": {
		"label": "GREEN DRONE",
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
		var nid := v.to_lower()
		if not THEMES.has(nid):
			nid = DEFAULT_THEME
		if nid == current_theme_id:
			return
		current_theme_id = nid
		theme_changed.emit(current_theme_id)

func _ready() -> void:
	# Sincronizar con SettingsManager si existe
	var sm := get_node_or_null("/root/SettingsManager")
	if sm:
		if "menu_theme" in sm:
			var nid: String = str(sm.menu_theme).to_lower()
			if THEMES.has(nid) and sm.is_theme_unlocked(nid):
				current_theme_id = nid
			else:
				current_theme_id = DEFAULT_THEME
		if sm.has_signal("setting_changed"):
			sm.setting_changed.connect(_on_setting_changed)

func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "menu_theme":
		var nid: String = str(value).to_lower()
		if THEMES.has(nid):
			current_theme_id = nid

func get_theme(id: String = current_theme_id) -> Dictionary:
	var nid := id.to_lower()
	if THEMES.has(nid):
		return THEMES[nid]
	return THEMES[DEFAULT_THEME]

func get_music_path(id: String = current_theme_id) -> String:
	return str(get_theme(id).get("music", THEMES[DEFAULT_THEME]["music"]))

func get_palette(id: String = current_theme_id) -> Dictionary:
	var t := get_theme(id)
	return {
		"border": t["border_color"],
		"hint": t["hint_color"],
		"dim": t["dim_color"],
		"bg": t["bg_color"],
	}

func list_unlocked() -> PackedStringArray:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and "unlocked_themes" in sm:
		return sm.unlocked_themes
	return PackedStringArray([DEFAULT_THEME])

func try_unlock(id: String) -> bool:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and sm.has_method("unlock_theme"):
		return sm.unlock_theme(id)
	return false
