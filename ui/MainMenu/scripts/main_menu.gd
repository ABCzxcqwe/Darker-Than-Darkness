extends Control

##  MainMenu fiel Deltarune Ch1 — sandbox visual con temas.
## Heart (Soul.png) se anima con tween y sigue la opción seleccionada.
## Tematizable vía ThemeManager (colores + fondo animado + soul/font).

const FONT_MAIN := preload("uid://dvelfumepo3c0")
const SOUL_TEX := preload("uid://cn3fwx46ofue5")

const OPTIONS := ["JUGAR", "OPCIONES", "EXTRAS", "SALIR"]
const OPTION_HINT := ["Busca o crea partida — LAN y Online", "Perfil, audio, video y mando", "Galería y créditos — Próximamente", "Cerrar a escritorio"]

@onready var _labels: Array[Label] = []
@onready var _soul: TextureRect = $SoulCursor
@onready var _box: PanelContainer = $CenterContainer/DeltaruneBox
@onready var _hint: Label = $CenterContainer/DeltaruneBox/Margin/VBox/HintLabel
@onready var _title: Label = $CenterContainer/DeltaruneBox/Margin/VBox/Title
@onready var _bg: Control = $Background
@onready var _separator: ColorRect = $CenterContainer/DeltaruneBox/Margin/VBox/Separator
@onready var _footer: Label = $Footer

var _index := 0
var _busy := false
var _soul_tween: Tween

func _ready() -> void:
	var btn := get_node_or_null("BackToOriginal")
	if btn:
		btn.visible = false
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.focus_mode = Control.FOCUS_NONE

	var menu_vbox := $CenterContainer/DeltaruneBox/Margin/VBox/MenuList
	for c in menu_vbox.get_children():
		if c is Label:
			_labels.append(c)

	_apply_theme()

	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		if not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)

	_highlight(_index, true)
	_position_soul(_index, true)
	_update_footer()

	_setup_audio()
	grab_focus()

func _exit_tree() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.disconnect(_on_theme_changed)

func _setup_audio() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if not am:
		return

	if am.has_method("play_menu_drone"):
		var is_playing: bool = am.menu_music_player and am.menu_music_player.playing
		if am.current_global_state != "menu_drone" or not is_playing:
			am.play_menu_drone()
	elif am.has_method("change_audio_state"):
		var tm := get_node_or_null("/root/ThemeManager")
		var path: String = tm.get_music_path() if tm and tm.has_method("get_music_path") else "res://ui/Boot/scenes/AUDIO_DRONE.wav"
		var s := load(path) as AudioStream
		if s:
			if "loop" in s:
				s.set("loop", true)
			am.map_music_player.stream = s
			am.change_audio_state("menu_drone")

func _on_theme_changed(_id: String) -> void:
	_apply_theme()
	_highlight(_index, true)

func _apply_theme() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null:
		return

	var palette: Dictionary = tm.get_palette() if tm.has_method("get_palette") else {}
	var bg_color: Color = palette.get("bg", Color.BLACK)
	var border: Color = palette.get("border", Color(0, 0.5, 0, 1))
	var title_col: Color = palette.get("title", Color(0, 1, 0, 1))
	var hint_col: Color = palette.get("hint", Color(0, 1, 0, 1))
	var sep_col: Color = palette.get("separator", border)

	if tm.has_method("apply_to_background") and _bg:
		tm.apply_to_background(_bg)
	elif _bg is ColorRect:
		(_bg as ColorRect).color = bg_color

	if _box:
		_box.add_theme_stylebox_override("panel", tm.make_box_style() if tm.has_method("make_box_style") else null)

	if _title:
		_title.add_theme_color_override("font_color", title_col)
		if tm.has_method("get_font"):
			var f: FontFile = tm.get_font()
			if f:
				_title.add_theme_font_override("font", f)

	if _separator:
		_separator.color = sep_col

	if _hint:
		_hint.add_theme_color_override("font_color", hint_col)

	if _soul:
		var st: Texture2D = tm.get_soul_texture() if tm.has_method("get_soul_texture") else null
		_soul.texture = st if st else SOUL_TEX

	if _footer:
		var footer_col: Color = palette.get("dim", Color(1, 1, 1, 1))
		_footer.add_theme_color_override("font_color", footer_col)

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return

	var vp := get_viewport()
	if vp == null:
		return

	if event.is_action_pressed("menu_up"):
		_move(-1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		_move(1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_accept") or event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_Z):
		_confirm()
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		if _index != 0:
			_set_index(0)
		vp.set_input_as_handled()

func _move(dir: int) -> void:
	var new_idx := clampi(_index + dir, 0, _labels.size() - 1)
	if new_idx == _index:
		return
	_set_index(new_idx)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)

func _set_index(i: int) -> void:
	_index = i
	_highlight(_index, false)
	_position_soul(_index, false)
	if _hint:
		_hint.text = OPTION_HINT[_index]

func _highlight(idx: int, _instant: bool) -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	var palette: Dictionary = tm.get_palette() if tm and tm.has_method("get_palette") else {}
	var sel: Color = palette.get("selected", Color(0, 1, 0, 1))
	var dim: Color = palette.get("dim", Color(0, 0.50196, 0, 1))

	for j in _labels.size():
		var lbl: Label = _labels[j]
		lbl.text = OPTIONS[j]
		lbl.modulate = sel if j == idx else dim

func _position_soul(idx: int, instant: bool) -> void:
	if _soul == null or _labels.is_empty():
		return
	if idx < 0 or idx >= _labels.size():
		return

	var target: Label = _labels[idx]
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		return
	# esperar layout estable (size del label y soul)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(self) or not is_instance_valid(target) or not is_instance_valid(_soul):
		return
	if not target.is_visible_in_tree():
		return

	var label_global := target.global_position
	var soul_h := _soul.size.y if _soul.size.y > 0 else 20.0
	var soul_offset := Vector2(-28, (target.size.y - soul_h) / 2.0)
	var dest_global := label_global + soul_offset
	var local_dest := dest_global - global_position

	if _soul_tween and _soul_tween.is_running():
		_soul_tween.kill()

	if instant:
		_soul.position = local_dest
	else:
		_soul_tween = create_tween()
		_soul_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_soul_tween.tween_property(_soul, "position", local_dest, 0.08)

func _update_footer() -> void:
	if _footer == null:
		return
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.1"))
	if version == "" or version == "<nil>":
		version = "0.1"

	var sm := get_node_or_null("/root/SettingsManager")
	var user: String = "anon"
	if sm and "player_name" in sm and sm.player_name != "":
		user = sm.player_name

	_footer.text = "DARKER:\\Users\\%s> v%s [LAN]    [↑][↓] MOVER  [Z] CONFIRMAR  [X] VOLVER" % [user, version]

func _confirm() -> void:
	var am2 := get_node_or_null("/root/AudioManager")
	if am2 and am2.has_method("play_sfx_ui"):
		am2.play_sfx_ui(SfxId.SELECT)

	_busy = true
	var lbl: Label = _labels[_index]
	var tm := get_node_or_null("/root/ThemeManager")
	var palette: Dictionary = tm.get_palette() if tm and tm.has_method("get_palette") else {}
	var sel: Color = palette.get("selected", Color(0, 1, 0, 1))

	var tw := create_tween()
	tw.tween_property(lbl, "modulate", Color(0.6, 0.6, 0.6, 1), 0.08)
	tw.tween_property(lbl, "modulate", sel, 0.08)
	await tw.finished

	_busy = false

	match _index:
		0:
			get_tree().change_scene_to_file("res://ui/MainMenu/scenes/PlayMode.tscn")
		1:
			get_tree().change_scene_to_file("res://ui/MainMenu/scenes/Settings.tscn")
		2:
			var am_err := get_node_or_null("/root/AudioManager")
			if am_err and am_err.has_method("play_sfx_ui"):
				am_err.play_sfx_ui(SfxId.ERROR)
			_hint.text = "EXTRAS — Próximamente"
		3:
			get_tree().quit()

func _on_back_to_original_pressed() -> void:
	push_warning("[MainMenu] BackToOriginal deprecado, Old/ conservado sin navegación")
