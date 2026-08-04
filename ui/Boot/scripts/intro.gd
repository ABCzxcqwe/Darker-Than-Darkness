extends Control

## Secuencia de introducción / "profecía" del juego.
## Arma la historia agregando elementos a "steps" desde el Inspector
## (cada uno es un recurso IntroStep con texto y/o imagen/silueta).
## Si "steps" está vacío, se usa "fallback_lines" como texto simple,
## para poder probar la escena aunque aún no tengas el contenido final.
@export var steps: Array[IntroStep] = []

@export var fallback_lines: Array[String] = ["..."]
@export var fallback_line_time: float = 3.0
@export var fallback_fade_time: float = 0.6

## Ruta de la siguiente escena al terminar (o saltar) la intro.
@export var next_scene_path: String = "res://ui/Boot/scenes/LegalNotice.tscn"

@onready var image_layer: TextureRect = $ImageLayer
@onready var center_label: Label = $CenterLabel

var _idx := -1
var _done := false
var _steps_resolved: Array[IntroStep] = []


func _ready() -> void:
	_steps_resolved = _resolve_steps()
	_next()


func _resolve_steps() -> Array[IntroStep]:
	if not steps.is_empty():
		return steps
	var resolved: Array[IntroStep] = []
	for line: String in fallback_lines:
		var step := IntroStep.new()
		step.text = line
		step.hold_time = fallback_line_time
		step.fade_time = fallback_fade_time
		resolved.append(step)
	return resolved


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("confirm") or event.is_action_pressed("ui_cancel"):
		_layer_input_handled()
		_skip()
	elif event is InputEventMouseButton and event.pressed:
		_layer_input_handled()
		_skip()
	elif event.is_action_pressed("ui_accept") and _waiting_for_input():
		_layer_input_handled()
		_advance_manual()


func _layer_input_handled() -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()


func _waiting_for_input() -> bool:
	if _done or _idx < 0 or _idx >= _steps_resolved.size():
		return false
	return _steps_resolved[_idx].hold_time <= 0.0


func _advance_manual() -> void:
	if _idx < 0 or _idx >= _steps_resolved.size():
		return
	_fade_out_and_next(_steps_resolved[_idx])


func _next() -> void:
	if _done:
		return
	_idx += 1
	if _idx >= _steps_resolved.size():
		_finish()
		return
	_play_step(_steps_resolved[_idx])


func _play_step(step: IntroStep) -> void:
	center_label.text = step.text
	center_label.modulate.a = 0.0

	image_layer.texture = step.image
	image_layer.position = step.image_offset
	image_layer.scale = step.image_scale
	# Silueta = imagen teñida de negro, animamos solo el alpha.
	var base_color := Color(0, 0, 0, 0) if step.image_as_silhouette else Color(1, 1, 1, 0)
	image_layer.modulate = base_color

	if step.sfx_id >= 0:
		AudioManager.play_sfx_ui(step.sfx_id)

	var fade_in := create_tween()
	fade_in.set_parallel(true)
	fade_in.tween_property(center_label, "modulate:a", 1.0, step.fade_time)
	if step.image:
		fade_in.tween_property(image_layer, "modulate:a", 1.0, step.fade_time)

	if step.hold_time <= 0.0:
		# Este paso espera input manual (Espacio) para avanzar.
		return

	fade_in.finished.connect(func() -> void:
		if _done or _idx >= _steps_resolved.size() or _steps_resolved[_idx] != step:
			return
		var hold_timer := get_tree().create_timer(step.hold_time)
		hold_timer.timeout.connect(func() -> void:
			if _done or _idx >= _steps_resolved.size() or _steps_resolved[_idx] != step:
				return
			_fade_out_and_next(step)
		)
	)


func _fade_out_and_next(step: IntroStep) -> void:
	var fade_out := create_tween()
	fade_out.set_parallel(true)
	fade_out.tween_property(center_label, "modulate:a", 0.0, step.fade_time)
	if step.image:
		fade_out.tween_property(image_layer, "modulate:a", 0.0, step.fade_time)
	fade_out.chain().tween_callback(_next)


func _skip() -> void:
	_done = true
	_finish()


func _finish() -> void:
	_done = true
	get_tree().change_scene_to_file(next_scene_path)
