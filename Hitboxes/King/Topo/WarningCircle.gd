extends Node2D

var radius: float = 90.0:
	set(v):
		radius = v
		queue_redraw()
var duration: float = 1.0
var _time: float = 0.0

const SIGNAL_TEX := preload("res://Characters/King/assets/Sprites/señal.png")


func _ready() -> void:
	# Visible en todos los peers, lógica ligera — no necesita authority
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	# Pulso como AoEIndicator
	var alpha := 0.35 + sin(_time * 6.0) * 0.2
	modulate.a = clampf(alpha, 0.15, 0.65)
	queue_redraw()
	if multiplayer.is_server() and _time >= duration:
		queue_free()


func _draw() -> void:
	if SIGNAL_TEX:
		var sz := SIGNAL_TEX.get_size()
		if sz.x <= 0.0 or sz.y <= 0.0:
			draw_circle(Vector2.ZERO, radius, Color(1, 0.9, 0.2, 0.25))
			return
		var scale_factor := (radius * 2.0) / maxf(sz.x, sz.y)
		if scale_factor <= 0.0 or not is_finite(scale_factor):
			scale_factor = 1.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale_factor)
		draw_texture(SIGNAL_TEX, -sz * 0.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_circle(Vector2.ZERO, radius, Color(1, 0.9, 0.2, 0.25))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, Color(1, 0.95, 0.5, 0.8), 3.0)
