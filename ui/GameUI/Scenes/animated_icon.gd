# animated_icon.gd
# Icono de personaje en la GUI. Muestra la animación universal "icon"
# de un SpriteFrames (frame único o animada), con fallback a una textura estática.
class_name AnimatedIcon
extends TextureRect

var _frames: SpriteFrames = null
var _anim_name: String = "icon"
var _elapsed: float = 0.0
var _frame_idx: int = 0
var _static_texture: Texture2D = null


func setup(frames: SpriteFrames, anim_name: String = "icon", fallback_tex: Texture2D = null) -> void:
	_static_texture = fallback_tex
	_frames = null
	_anim_name = anim_name
	_elapsed = 0.0
	_frame_idx = 0

	if frames and frames.has_animation(anim_name):
		_frames = frames
		texture = frames.get_frame_texture(anim_name, 0)
		set_process(true)
	else:
		texture = fallback_tex
		set_process(false)


func _process(delta: float) -> void:
	if _frames == null:
		return
	var frame_count := _frames.get_frame_count(_anim_name)
	if frame_count <= 0:
		return

	var loop := _frames.get_animation_loop(_anim_name)
	var speed := _frames.get_animation_speed(_anim_name)
	if speed <= 0.0:
		speed = 1.0

	_elapsed += delta * speed
	var target := int(_elapsed)
	if loop:
		_frame_idx = target % frame_count
	elif target >= frame_count:
		_frame_idx = frame_count - 1
		set_process(false)
	else:
		_frame_idx = target

	texture = _frames.get_frame_texture(_anim_name, _frame_idx)
