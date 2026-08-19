# PlaceholderSymbol.gd
# Dibuja símbolos placeholder (corazón, trébol, diamante, carrusel) en un CanvasItem.
# El usuario los reemplazará por arte real; solo sirve mientras no hay texturas.
extends RefCounted
class_name PlaceholderSymbol


static func draw_symbol(c: CanvasItem, symbol: String, color: Color, size: float) -> void:
	match symbol:
		"heart":
			_draw_heart(c, color, size)
		"clover":
			_draw_clover(c, color, size)
		"carousel":
			_draw_carousel(c, color, size)
		_:
			_draw_diamond(c, color, size)


static func _draw_diamond(c: CanvasItem, color: Color, size: float) -> void:
	var pts := PackedVector2Array([
		Vector2(0, -size),
		Vector2(size * 0.72, 0),
		Vector2(0, size),
		Vector2(-size * 0.72, 0),
	])
	c.draw_colored_polygon(pts, color)


static func _draw_heart(c: CanvasItem, color: Color, size: float) -> void:
	var r := size * 0.5
	c.draw_circle(Vector2(-r * 0.6, -r * 0.35), r * 0.55, color)
	c.draw_circle(Vector2(r * 0.6, -r * 0.35), r * 0.55, color)
	var pts := PackedVector2Array([
		Vector2(-r * 1.1, 0.0),
		Vector2(r * 1.1, 0.0),
		Vector2(0.0, r * 1.25),
	])
	c.draw_colored_polygon(pts, color)


static func _draw_clover(c: CanvasItem, color: Color, size: float) -> void:
	var r := size * 0.5
	c.draw_circle(Vector2(-r * 0.55, -r * 0.55), r * 0.6, color)
	c.draw_circle(Vector2(r * 0.55, -r * 0.55), r * 0.6, color)
	c.draw_circle(Vector2(-r * 0.55, r * 0.55), r * 0.6, color)
	c.draw_circle(Vector2(r * 0.55, r * 0.55), r * 0.6, color)
	var stem := PackedVector2Array([
		Vector2(-size * 0.12, size * 0.5),
		Vector2(size * 0.12, size * 0.5),
		Vector2(0.0, size * 1.1),
	])
	c.draw_colored_polygon(stem, color)


static func _draw_carousel(c: CanvasItem, color: Color, size: float) -> void:
	# Estrella de 4 puntas (twinkle) — simboliza el carrusel.
	var pts := PackedVector2Array([
		Vector2(0, -size),
		Vector2(size * 0.18, -size * 0.18),
		Vector2(size, 0),
		Vector2(size * 0.18, size * 0.18),
		Vector2(0, size),
		Vector2(-size * 0.18, size * 0.18),
		Vector2(-size, 0),
		Vector2(-size * 0.18, -size * 0.18),
	])
	c.draw_colored_polygon(pts, color)
