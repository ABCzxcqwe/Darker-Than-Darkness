extends Control

@export var lines: Array[String] = [
	"Darker Than Darkness",
	"En la oscuridad, el miedo se vuelve cazador.",
	"Reúne a tus amigos... o escapa de ellos.",
	"Un juego de rol asimétrico.",
]
@export var line_time: float = 3.0
@export var fade_time: float = 0.6

@onready var center_label: Label = $CenterLabel

var _idx := -1
var _done := false


func _ready() -> void:
	_next()


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("confirm") or event.is_action_pressed("ui_cancel"):
		_skip()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_skip()
		get_viewport().set_input_as_handled()


func _next() -> void:
	if _done:
		return
	_idx += 1
	if _idx >= lines.size():
		_finish()
		return
	center_label.text = lines[_idx]
	center_label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(center_label, "modulate:a", 1.0, fade_time)
	tween.tween_interval(line_time)
	tween.tween_property(center_label, "modulate:a", 0.0, fade_time)
	tween.finished.connect(_next)


func _skip() -> void:
	_done = true
	_finish()


func _finish() -> void:
	get_tree().change_scene_to_file("res://ui/Boot/scenes/LegalNotice.tscn")
