extends Control

enum Part { HEAD, BODY, LEGS }
enum Step { PARTS, NAME }

const HEAD_FRAMES := 8
const BODY_FRAMES := 6
const LEGS_FRAMES := 1

const HEAD_FRAME_SIZE := Vector2i(21, 22)
const BODY_FRAME_SIZE := Vector2i(20, 14)
const LEGS_FRAME_SIZE := Vector2i(28, 8)

@export var part_titles: Array[String] = ["Elige la cabeza", "Elige el torso", "Elige las piernas"]

@onready var head_rect: TextureRect = $Vessel/HeadRect
@onready var body_rect: TextureRect = $Vessel/BodyRect
@onready var legs_rect: TextureRect = $Vessel/LegsRect
@onready var part_label: Label = $PartLabel
@onready var name_prompt: Label = $NamePrompt
@onready var name_edit: LineEdit = $NameEdit
@onready var hint_label: Label = $HintLabel
@onready var continue_btn: Button = $ContinueBtn

var _part: int = Part.HEAD
var _step: int = Step.PARTS
var _frames: Array[int] = [0, 0, 0]


func _ready() -> void:
	head_rect.region_enabled = true
	body_rect.region_enabled = true
	legs_rect.region_enabled = true
	name_edit.text = SettingsManager.player_name
	_update_all()
	_set_part(Part.HEAD)


func _unhandled_input(event: InputEvent) -> void:
	if _step == Step.NAME:
		return
	if event.is_action_pressed("move_left"):
		_cycle(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("confirm"):
		_advance()
		get_viewport().set_input_as_handled()


func _apply_region(rect: TextureRect, frame_size: Vector2i, frame: int) -> void:
	var texture := rect.texture
	if texture == null:
		return
	var cols := int(texture.get_width() / frame_size.x)
	rect.region_rect = Rect2(frame_size.x * (frame % cols), 0, frame_size.x, frame_size.y)


func _update_all() -> void:
	_apply_region(head_rect, HEAD_FRAME_SIZE, _frames[Part.HEAD])
	_apply_region(body_rect, BODY_FRAME_SIZE, _frames[Part.BODY])
	_apply_region(legs_rect, LEGS_FRAME_SIZE, _frames[Part.LEGS])


func _set_part(p: int) -> void:
	_part = p
	part_label.text = part_titles[p]
	var parts: Array[TextureRect] = [head_rect, body_rect, legs_rect]
	for i in parts.size():
		parts[i].modulate = Color(1, 1, 1, 1) if i == p else Color(0.35, 0.35, 0.35, 1)


func _cycle(dir: int) -> void:
	var frame_counts: Array[int] = [HEAD_FRAMES, BODY_FRAMES, LEGS_FRAMES]
	var frame_sizes: Array[Vector2i] = [HEAD_FRAME_SIZE, BODY_FRAME_SIZE, LEGS_FRAME_SIZE]
	_frames[_part] = posmod(_frames[_part] + dir, frame_counts[_part])
	_apply_region([head_rect, body_rect, legs_rect][_part], frame_sizes[_part], _frames[_part])
	AudioManager.play_sfx_ui(SfxId.MENU_MOVE)


func _advance() -> void:
	if _step == Step.NAME:
		_confirm_name()
		return
	if _part < Part.LEGS:
		_set_part(_part + 1)
	else:
		_go_to_name()


func _go_to_name() -> void:
	_step = Step.NAME
	part_label.text = "Elige tu nombre"
	name_prompt.visible = true
	name_edit.visible = true
	hint_label.text = "Escribe tu nombre de usuario y pulsa Continuar"
	continue_btn.text = "Listo"
	name_edit.grab_focus()


func _confirm_name() -> void:
	var name_text := name_edit.text.strip_edges()
	if name_text.is_empty():
		hint_label.text = "Escribe tu nombre de usuario"
		AudioManager.play_sfx_ui(SfxId.CANT_SELECT)
		name_edit.grab_focus()
		return
	SettingsManager.player_name = name_text
	SettingsManager.vessel_data = {
		"head": _frames[Part.HEAD],
		"body": _frames[Part.BODY],
		"legs": _frames[Part.LEGS],
	}
	SettingsManager.first_launch_done = true
	SettingsManager.save_settings()
	LobbyManager.local_player_name = name_text
	AudioManager.play_sfx_ui(SfxId.SELECT)
	get_tree().change_scene_to_file("res://ui/Boot/scenes/Intro.tscn")


func _on_continue_pressed() -> void:
	_advance()


func _on_name_edit_text_submitted(_new_text: String) -> void:
	_confirm_name()
