extends Control

## Joystick táctil simple y reutilizable.
## Emite `changed(value)` con un vector en [-1, 1] por eje.
## Soporta touch multitáctil y mouse (para probar en desktop con F8).

signal changed(value: Vector2)

@export var radius: float = 70.0
@export var knob_ratio: float = 0.38
@export var deadzone: float = 0.15
@export var base_color: Color = Color(1, 1, 1, 0.10)
@export var ring_color: Color = Color(1, 1, 1, 0.30)
@export var knob_color: Color = Color(1, 1, 1, 0.38)

var _value: Vector2 = Vector2.ZERO
var _touch_index: int = -1
var _mouse_active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if not visible and (_touch_index != -1 or _mouse_active):
		reset_value()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.canceled:
			if event.index == _touch_index:
				_touch_index = -1
				_reset()
			return
		if event.pressed and _touch_index == -1 and _inside(event.position):
			_touch_index = event.index
			_update(event.position)
			accept_event()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			_reset()
			accept_event()
		return

	if event is InputEventScreenDrag and event.index == _touch_index:
		_update(event.position)
		accept_event()
		return

	if event is InputEventMouseButton and not OS.has_feature("mobile"):
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed and _inside(event.position):
			_mouse_active = true
			_update(event.position)
			accept_event()
		elif not event.pressed and _mouse_active:
			_mouse_active = false
			_reset()
			accept_event()
		return

	if event is InputEventMouseMotion and _mouse_active and not OS.has_feature("mobile"):
		_update(event.position)


## Godot documenta `InputEventScreenTouch.position` en coordenadas del
## viewport, mientras que los eventos de mouse llegan en coordenadas locales
## del control. Normalizamos ambos casos.
func _to_local(pos: Vector2) -> Vector2:
	if Rect2(Vector2.ZERO, size).has_point(pos):
		return pos
	return pos - global_position


func _inside(pos: Vector2) -> bool:
	return _to_local(pos).distance_to(size * 0.5) <= maxf(radius, 1.0)


func _update(pos: Vector2) -> void:
	var center := size * 0.5
	var v := (_to_local(pos) - center) / maxf(radius, 1.0)
	if v.length() > 1.0:
		v = v.normalized()
	elif v.length() < deadzone:
		v = Vector2.ZERO
	_value = v
	changed.emit(_value)
	queue_redraw()


func _reset() -> void:
	_value = Vector2.ZERO
	changed.emit(_value)
	queue_redraw()


## Corta el toque en curso y devuelve el stick al centro (al abrir un menú).
func reset_value() -> void:
	_touch_index = -1
	_mouse_active = false
	_reset()


func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius, base_color)
	draw_arc(center, radius, 0.0, TAU, 48, ring_color, 2.0)
	var knob := center + _value * radius
	draw_circle(knob, radius * knob_ratio, knob_color)
