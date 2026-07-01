extends Camera2D

@export var mouse_peek_amount: float = 0.3
@export var mouse_peek_limit: float = 120.0
@export var zoom_base: float = 0.75
@export var zoom_sprint: float = 0.5
@export var zoom_speed: float = 3.0
@export var smooth_speed: float = 5.0

var _shake_intensity: float = 0.0
var _shake_remaining: float = 0.0
var _shake_duration: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = smooth_speed


func _process(delta: float) -> void:
	var parent = get_parent()
	if not parent:
		return

	if parent.is_spectator:
		offset = Vector2.ZERO
		return

	var peek := _calc_mouse_peek(parent)
	_update_shake(delta)
	offset = peek + _shake_offset
	_update_zoom(parent, delta)


func _calc_mouse_peek(parent: Node2D) -> Vector2:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var player_pos: Vector2 = parent.global_position
	var dir: Vector2 = (mouse_pos - player_pos).normalized()
	var dist: float = clamp((mouse_pos - player_pos).length() / 500.0, 0.0, 1.0)
	return dir * dist * mouse_peek_amount * mouse_peek_limit


func _update_shake(delta: float) -> void:
	if _shake_remaining > 0.0:
		var t: float = _shake_remaining / _shake_duration
		var decayed: float = _shake_intensity * t
		_shake_offset = Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * decayed
		_shake_remaining -= delta
		if _shake_remaining <= 0.0:
			_shake_remaining = 0.0
			_shake_offset = Vector2.ZERO
	else:
		_shake_offset = Vector2.ZERO


func _update_zoom(parent: Node2D, delta: float) -> void:
	var target := zoom_base
	if parent._is_sprinting:
		target = zoom_sprint
	zoom = zoom.lerp(Vector2(target, target), zoom_speed * delta)


func shake(intensity: float = 5.0, duration: float = 0.2) -> void:
	_shake_intensity = intensity
	_shake_remaining = duration
	_shake_duration = duration


func set_map_bounds(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.position.x + rect.size.x)
	limit_bottom = int(rect.position.y + rect.size.y)
