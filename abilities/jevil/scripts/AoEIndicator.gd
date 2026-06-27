extends Node2D

var radius: float = 1000.0
var blink_speed: float = 6.0
var color: Color = Color(1, 0, 0)
var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	var alpha: float = 0.3 + sin(_time * blink_speed) * 0.2
	modulate.a = clampf(alpha, 0.1, 0.5)
	queue_redraw()


func _draw() -> void:
	var fill := Color(color.r, color.g, color.b, modulate.a * 0.3)
	var outline := Color(color.r * 1.2, color.g * 1.2, color.b * 1.2, minf(modulate.a + 0.2, 1.0))
	draw_circle(Vector2.ZERO, radius, fill)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, outline, 4.0)
