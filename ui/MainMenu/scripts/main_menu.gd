extends Control
## Mock MainMenu fiel Deltarune Ch1 — sandbox visual.
## No modifica menu_base ni MainMenu existente. Solo usa AudioManager + Settings existentes para SFX.
## Controles: W/S o Up/Down, Enter/Space/Z para confirmar, Esc/X para salir.
## Heart (Soul.png) se anima con tween y sigue la opción seleccionada.

const FONT_MAIN := preload("res://Fonts/deltarune font.ttf")
const SOUL_TEX := preload("res://sprites/Soul.png")

# Opciones visibles en el mock (solo visual, no navega a escenas reales)
const OPTIONS := ["JUGAR", "OPCIONES", "EXTRAS", "SALIR"]
const OPTION_HINT := ["Jugar", "Configuración", "Extras (proximamente)", "Cerrar juego"]

@onready var _labels: Array[Label] = []
@onready var _soul: TextureRect = $SoulCursor
@onready var _box: PanelContainer = $CenterContainer/DeltaruneBox
@onready var _hint: Label = $CenterContainer/DeltaruneBox/Margin/VBox/HintLabel
@onready var _title: Label = $CenterContainer/DeltaruneBox/Margin/VBox/Title

var _index := 0
var _busy := false

func _ready() -> void:
	# Ocultar fallback debug Old/ si existe
	var btn := get_node_or_null("BackToOriginal")
	if btn:
		btn.visible = false
		btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.focus_mode = Control.FOCUS_NONE
	# Construir referencias a labels de opciones
	var menu_vbox := $CenterContainer/DeltaruneBox/Margin/VBox/MenuList
	for c in menu_vbox.get_children():
		if c is Label:
			_labels.append(c)
	_highlight(_index, true)
	_position_soul(_index, true)
	_update_footer()
	# Música menú via MapMusicPlayer (bus Map Music) sin superposición — parche mínimo AudioManager menu_drone
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_menu_drone"):
		am.play_menu_drone()
	elif am and am.has_method("change_audio_state"):
		var tm := get_node_or_null("/root/ThemeManager")
		var path: String = tm.get_music_path() if tm and tm.has_method("get_music_path") else "res://ui/Boot/scenes/AUDIO_DRONE.wav"
		var s := load(path) as AudioStream
		if s:
			if "loop" in s:
				s.loop = true
			am.map_music_player.stream = s
			am.change_audio_state("menu_drone")
	# Focus para gamepad/teclado
	grab_focus()

func _exit_tree() -> void:
	# No detener aquí: dejar que PlayMode/Settings mantenga drone hasta ingame (setup_map_audio lo reemplaza)
	pass

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

func _highlight(idx: int, instant: bool) -> void:
	for j in _labels.size():
		var lbl: Label = _labels[j]
		if j == idx:
			lbl.modulate = Color(0, 1, 0, 1)
			lbl.text = "    " + OPTIONS[j]
		else:
			lbl.modulate = Color(0, 0.50196081, 0, 1)
			lbl.text = "" + OPTIONS[j]

func _position_soul(idx: int, instant: bool) -> void:
	if _soul == null or _labels.is_empty():
		return
	if idx < 0 or idx >= _labels.size():
		return
	var target: Label = _labels[idx]
# Convertir posición del label a global y colocar soul a la izquierda del texto
	# Usamos posición relativa al CenterContainer
	await get_tree().process_frame
	var label_global := target.global_position
	var soul_offset := Vector2(-28, (target.size.y - _soul.size.y) / 2.0)
	var dest := label_global + soul_offset
# Convertir a posición local del root Control
	var local_dest := dest - global_position
	if instant:
		_soul.position = local_dest
	else:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_soul, "position", local_dest, 0.08)

func _update_footer() -> void:
	var footer: Label = get_node_or_null("Footer") as Label
	if footer == null:
		return
	var version: String = str(ProjectSettings.get_setting("application/config/version"))
	if version == "" or version == "<nil>":
		version = "0.1"
	var sm := get_node_or_null("/root/SettingsManager")
	var user: String = "anon"
	if sm and sm.player_name != "":
		user = sm.player_name
	# Prompt terminal + build + solo teclado retro
	footer.text = "DARKER:\\Users\\%s> v%s [LAN]   [↑][↓] MOVER  [Z] CONFIRMAR  [X] VOLVER" % [user, version]

func _confirm() -> void:
	var am2 := get_node_or_null("/root/AudioManager")
	if am2 and am2.has_method("play_sfx_ui"):
		am2.play_sfx_ui(SfxId.SELECT)
	_busy = true
	var lbl: Label = _labels[_index]
	# Flash amarillo como Deltarune
	var tw := create_tween()
	tw.tween_property(lbl, "modulate", Color(0.6, 0.6, 0.6, 1), 0.08)
	tw.tween_property(lbl, "modulate", Color(0, 1, 0, 1), 0.08)
	await tw.finished
	_busy = false
	match _index:
		0:
			get_tree().change_scene_to_file("res://ui/MainMenu/scenes/PlayMode.tscn")
			return
		1:
			get_tree().change_scene_to_file("res://ui/MainMenu/scenes/Settings.tscn")
			return
		2:
			var am_err := get_node_or_null("/root/AudioManager")
			if am_err and am_err.has_method("play_sfx_ui"):
				am_err.play_sfx_ui(SfxId.ERROR)
			_hint.text = "EXTRAS — Próximamente"
			return
		3:
			get_tree().quit()

func _on_back_to_original_pressed() -> void:
	# Deprecado — Old/ conservado solo como fallback, botón oculto
	push_warning("[MainMenu] BackToOriginal deprecado, Old/ conservado sin navegación")
	return
