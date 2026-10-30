# res://abilities/ralsei/HealPrayer/HealingField.gd
# Visual del área de rezo de Ralsei. Es puramente cosmético:
# el servidor corre los ticks y el daño; este nodo solo dibuja y se autolimpia.
extends Node2D

@export var radius: float = 220.0
@export var duration: float = 4.3

var _elapsed := 0.0


func _ready() -> void:
	z_as_relative = false
	z_index = 0
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_elapsed / maxf(duration, 0.01), 0.0, 1.0)
	var fade := 1.0 - t * 0.55
	var pulse := 0.5 + 0.5 * sin(_elapsed * TAU * 1.4)
	var line_a := (0.45 + 0.25 * pulse) * fade
	var inner_a := (0.20 + 0.18 * pulse) * fade

	draw_circle(Vector2.ZERO, radius, Color(0.15, 0.9, 0.45, 0.06 * fade))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64,
		Color(0.25, 1.0, 0.55, line_a), 3.0, true)
	draw_arc(Vector2.ZERO, radius * 0.72, 0.0, TAU, 64,
		Color(0.25, 1.0, 0.55, inner_a), 2.0, true)
