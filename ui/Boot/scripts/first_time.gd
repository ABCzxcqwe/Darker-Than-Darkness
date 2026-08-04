extends Control

enum Part { HEAD, BODY, LEGS }
enum Phase { CINEMATIC, COLOR, HEAD, BODY, LEGS, CONFIRM, NAME, READY }

const CINEMATIC_LINES: Array[String] = [
	"¿ESTAS AHI?",
	"¿ESTAMOS CONECTADOS?",
	"EXCELENTE.",
	"VERDADERAMENTE EXCELENTE.",
	"AHORA.",
	"COMENCEMOS.",
]

const PART_TITLES: Array[String] = ["ELIGE LA CABEZA DE TU PREFERENCIA", "ELIGE EL TORSO DE TU PREFERENCIA", "ELIGE LAS PIERNAS DE TU PREFERENCIA"]

const COLOR_NAMES: Array[String] = ["ROJO", "NARANJA", "AMARILLO", "VERDE", "CYAN", "AZUL", "PURPURA", "ROSA"]
const COLOR_VALUES: Array[Color] = [
	Color(1, 0.15, 0.15),
	Color(1, 0.55, 0.1),
	Color(1, 0.9, 0.1),
	Color(0.2, 0.9, 0.2),
	Color(0.2, 0.9, 0.9),
	Color(0.25, 0.5, 1),
	Color(0.7, 0.3, 1),
	Color(1, 0.45, 0.75),
]

@onready var head_sprite: Sprite2D = $Vessel/HeadSprite
@onready var body_sprite: Sprite2D = $Vessel/BodySprite
@onready var legs_sprite: Sprite2D = $Vessel/LegsSprite

@onready var cinematic_overlay: ColorRect = $CinematicOverlay
@onready var cinematic_label: Label = $CinematicOverlay/CinematicLabel

@onready var color_panel: Control = $ColorPanel
@onready var color_name_label: Label = $ColorPanel/ColorNameLabel

@onready var hud_panel: Control = $HudPanel
@onready var part_label: Label = $HudPanel/PartLabel
@onready var hint_label: Label = $HudPanel/HintLabel
@onready var continue_btn: Button = $HudPanel/ContinueBtn

@onready var confirm_panel: Control = $ConfirmPanel
@onready var confirm_yes_btn: Button = $ConfirmPanel/YesBtn
@onready var confirm_no_btn: Button = $ConfirmPanel/NoBtn

@onready var name_panel: Control = $NamePanel
@onready var name_prompt: Label = $NamePanel/NamePrompt
@onready var name_edit: LineEdit = $NamePanel/NameEdit

@onready var ready_panel: Control = $ReadyPanel
@onready var ready_name_label: Label = $ReadyPanel/NameLabel
@onready var ready_yes_btn: Button = $ReadyPanel/YesBtn
@onready var ready_no_btn: Button = $ReadyPanel/NoBtn

var _phase: int = Phase.CINEMATIC
var _part: int = Part.HEAD
var _color_idx: int = 0
var _frames: Array[int] = [0, 0, 0]
var _targets: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _cinematic_skip := false
var _finished := false


func _ready() -> void:
	for sprite: Sprite2D in _sprites():
		sprite.frame = 0
	for i in Part.size():
		_targets[i] = _sprites()[i].position
		_sprites()[i].position = Vector2.ZERO
	_sprites()[Part.HEAD].visible = false
	_sprites()[Part.BODY].visible = false
	_sprites()[Part.LEGS].visible = false
	name_edit.text = SettingsManager.player_name
	_start_cinematic()


func _unhandled_input(event: InputEvent) -> void:
	match _phase:
		Phase.CINEMATIC:
			if _is_skip(event):
				_skip_cinematic()
				get_viewport().set_input_as_handled()
		Phase.COLOR:
			if event.is_action_pressed("move_left"):
				_cycle_color(-1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("move_right"):
				_cycle_color(1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("confirm"):
				_confirm_color()
				get_viewport().set_input_as_handled()
		Phase.HEAD, Phase.BODY, Phase.LEGS:
			if event.is_action_pressed("move_left"):
				_cycle(-1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("move_right"):
				_cycle(1)
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("confirm"):
				_advance()
				get_viewport().set_input_as_handled()
		Phase.CONFIRM:
			if event.is_action_pressed("confirm"):
				_enter_name()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_cancel"):
				_back_to_legs()
				get_viewport().set_input_as_handled()
		Phase.NAME:
			pass
		Phase.READY:
			if event.is_action_pressed("confirm"):
				_finish()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_cancel"):
				_back_to_confirm()
				get_viewport().set_input_as_handled()


func _sprites() -> Array:
	return [head_sprite, body_sprite, legs_sprite]


func _is_skip(event: InputEvent) -> bool:
	return event.is_action_pressed("confirm") \
		or event.is_action_pressed("ui_cancel") \
		or (event is InputEventMouseButton and event.pressed)


func _start_cinematic() -> void:
	_phase = Phase.CINEMATIC
	cinematic_overlay.modulate.a = 1.0
	cinematic_overlay.visible = true
	hud_panel.visible = false
	_play_cinematic()


func _play_cinematic() -> void:
	for line: String in CINEMATIC_LINES:
		if _cinematic_skip:
			return
		cinematic_label.text = ""
		for i in range(line.length() + 1):
			if _cinematic_skip:
				return
			cinematic_label.text = line.substr(0, i)
			await get_tree().create_timer(0.045).timeout
		if _cinematic_skip:
			return
		await get_tree().create_timer(0.7).timeout
	if _cinematic_skip:
		return
	_end_cinematic()


func _skip_cinematic() -> void:
	_cinematic_skip = true
	_end_cinematic()


func _end_cinematic() -> void:
	if _phase != Phase.CINEMATIC:
		return
	_cinematic_skip = true
	var tw := create_tween()
	tw.tween_property(cinematic_overlay, "modulate:a", 0.0, 1.0)
	tw.finished.connect(func() -> void:
		cinematic_overlay.visible = false
	)
	_enter_color()


func _enter_color() -> void:
	_phase = Phase.COLOR
	_color_idx = 0
	color_panel.visible = true
	_update_color_label()


func _update_color_label() -> void:
	color_name_label.text = COLOR_NAMES[_color_idx]
	color_name_label.modulate = COLOR_VALUES[_color_idx]


func _cycle_color(dir: int) -> void:
	_color_idx = posmod(_color_idx + dir, COLOR_NAMES.size())
	_update_color_label()
	AudioManager.play_sfx_ui(SfxId.MENU_MOVE)


func _confirm_color() -> void:
	SettingsManager.favorite_color = COLOR_NAMES[_color_idx]
	color_panel.visible = false
	AudioManager.play_sfx_ui(SfxId.SELECT)
	_enter_parts(Phase.HEAD)


func _enter_parts(phase: int) -> void:
	_phase = phase
	_part = phase - Phase.HEAD
	if phase == Phase.HEAD:
		_show_part(Part.HEAD)
	part_label.text = PART_TITLES[_part]
	hud_panel.visible = true
	_update_hint()


func _update_hint() -> void:
	hint_label.text = "A/D para cambiar  ·  Espacio para continuar"


func _cycle(dir: int) -> void:
	var sprite: Sprite2D = _sprites()[_part]
	if sprite.hframes < 2:
		return
	_frames[_part] = posmod(_frames[_part] + dir, sprite.hframes)
	sprite.frame = _frames[_part]
	AudioManager.play_sfx_ui(SfxId.MENU_MOVE)


func _advance() -> void:
	if _part < Part.LEGS:
		_slide_to_final(_part)
		_part += 1
		_phase = Phase.HEAD + _part
		part_label.text = PART_TITLES[_part]
		_show_part(_part)
		_update_hint()
	else:
		_slide_to_final(_part)
		_enter_confirm()


func _slide_to_final(p: int) -> void:
	var sprite: Sprite2D = _sprites()[p]
	var tw := create_tween()
	tw.tween_property(sprite, "position", _targets[p], 0.7) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT)


func _show_part(p: int) -> void:
	var sprite: Sprite2D = _sprites()[p]
	sprite.visible = true
	sprite.position = Vector2.ZERO
	sprite.frame = _frames[p]


func _enter_confirm() -> void:
	_phase = Phase.CONFIRM
	hud_panel.visible = false
	confirm_panel.visible = true
	confirm_yes_btn.grab_focus()
	AudioManager.play_sfx_ui(SfxId.SELECT)


func _back_to_legs() -> void:
	confirm_panel.visible = false
	_enter_parts(Phase.LEGS)


func _enter_name() -> void:
	_phase = Phase.NAME
	confirm_panel.visible = false
	name_panel.visible = true
	name_edit.grab_focus()
	AudioManager.play_sfx_ui(SfxId.SELECT)


func _confirm_name() -> void:
	var name_text := name_edit.text.strip_edges()
	if name_text.is_empty():
		AudioManager.play_sfx_ui(SfxId.CANT_SELECT)
		name_prompt.modulate = Color(0.95, 0.845, 0.0, 1.0)
		var tw := create_tween()
		tw.tween_property(name_prompt, "modulate", Color(1, 1, 1, 1), 0.6)
		name_edit.grab_focus()
		return
	SettingsManager.player_name = name_text
	name_panel.visible = false
	ready_panel.visible = true
	ready_name_label.text = name_text
	_phase = Phase.READY
	ready_yes_btn.grab_focus()
	AudioManager.play_sfx_ui(SfxId.SELECT)


func _back_to_confirm() -> void:
	ready_panel.visible = false
	confirm_panel.visible = true
	_phase = Phase.CONFIRM
	confirm_yes_btn.grab_focus()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	SettingsManager.vessel_data = {
		"head": _frames[Part.HEAD],
		"body": _frames[Part.BODY],
		"legs": _frames[Part.LEGS],
	}
	SettingsManager.first_launch_done = true
	SettingsManager.save_settings()
	LobbyManager.local_player_name = SettingsManager.player_name
	AudioManager.play_sfx_ui(SfxId.SELECT)
	get_tree().change_scene_to_file("res://ui/Boot/scenes/Intro.tscn")


func _on_continue_pressed() -> void:
	_advance()


func _on_name_edit_text_submitted(_new_text: String) -> void:
	_confirm_name()


func _on_confirm_yes_pressed() -> void:
	_enter_name()


func _on_confirm_no_pressed() -> void:
	_back_to_legs()


func _on_ready_yes_pressed() -> void:
	_finish()


func _on_ready_no_pressed() -> void:
	_back_to_confirm()
