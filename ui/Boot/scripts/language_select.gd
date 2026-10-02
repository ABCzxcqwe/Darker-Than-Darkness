extends Control
## Selector de idioma inicial. Se muestra antes que todo (desde Boot).
## Guarda en SettingsManager.language y continúa a LegalNotice.

const NEXT_SCENE := "res://ui/Boot/scenes/LegalNotice.tscn"
const MAIN_FONT_PATH := "res://Fonts/deltarune font.ttf"

const LANGS := [
	{"id": "es", "label": "Español"},
	{"id": "en", "label": "English"},
	{"id": "pt", "label": "Português"},
	{"id": "ru", "label": "Русский"},
	{"id": "ko", "label": "한국어"},
	{"id": "ja", "label": "日本語"},
]
# Idiomas que deltarune no cubre -> SystemFont para evitar ???
const SYSTEM_FONT_IDS := ["ru", "ko", "ja"]

@onready var title_label: Label = $Center/VBox/TitleLabel
@onready var buttons_box: VBoxContainer = $Center/VBox/Buttons

var _buttons: Array[Button] = []
var _done := false


func _ready() -> void:
	_apply_fonts()
	_build_buttons()
	_refresh_title()
	_preselect_saved()
	if _buttons.size() > 0:
		_buttons[0].grab_focus()


func _apply_fonts() -> void:
	var main_font: Font = load(MAIN_FONT_PATH) as Font
	var sys := SystemFont.new()
	sys.font_names = ["Noto Sans", "Noto Sans CJK JP", "Noto Sans KR", "Arial", "sans-serif"]
	if main_font and main_font is FontFile:
		# Fallback global: deltarune + sistema (cubre ru/ko/ja)
		(main_font as FontFile).fallbacks = [sys]
		title_label.add_theme_font_override("font", main_font)
	else:
		title_label.add_theme_font_override("font", sys)


func _build_buttons() -> void:
	for c in buttons_box.get_children():
		c.queue_free()
	_buttons.clear()
	var main_font: Font = load(MAIN_FONT_PATH) as Font
	var sys := SystemFont.new()
	sys.font_names = ["Noto Sans", "Noto Sans CJK JP", "Noto Sans KR", "Arial", "sans-serif"]
	for entry in LANGS:
		var b := Button.new()
		b.text = str(entry["label"])
		b.custom_minimum_size = Vector2(320, 56)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", 28)
		if str(entry["id"]) in SYSTEM_FONT_IDS:
			b.add_theme_font_override("font", sys)
		elif main_font:
			b.add_theme_font_override("font", main_font)
		var lang_id := str(entry["id"])
		b.pressed.connect(_on_lang_pressed.bind(lang_id))
		# Vista previa del título al pasar el foco (sin guardar aún)
		b.focus_entered.connect(_on_lang_focused.bind(lang_id))
		buttons_box.add_child(b)
		_buttons.append(b)


func _refresh_title() -> void:
	# tr() si hay traducción cargada, si no inglés por defecto
	var t := tr("SELECT_LANGUAGE")
	if t == "" or t == "SELECT_LANGUAGE":
		t = "SELECT YOUR LANGUAGE"
	title_label.text = t


func _preselect_saved() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	var cur := str(sm.get("language")) if sm else "es"
	for i in LANGS.size():
		if str(LANGS[i]["id"]) == cur and i < _buttons.size():
			_buttons[i].grab_focus()
			break


func _on_lang_focused(lang_id: String) -> void:
	TranslationServer.set_locale(lang_id)
	_refresh_title()


func _on_lang_pressed(lang_id: String) -> void:
	if _done:
		return
	_done = true
	TranslationServer.set_locale(lang_id)
	var sm := get_node_or_null("/root/SettingsManager")
	if sm:
		sm.set("language", lang_id)
		if sm.has_method("save_settings"):
			sm.save_settings()
	if has_node("/root/AudioManager") and AudioManager.has_method("play_sfx_ui"):
		AudioManager.play_sfx_ui(SfxId.SELECT)
	get_tree().change_scene_to_file.call_deferred(NEXT_SCENE)
