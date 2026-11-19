extends Node2D

## Dibuja solo el asta (cola) de la Lanza de King.
## Vive como hijo de LanzaProjectile con z_as_relative = false y z_index bajo,
## para que el asta pase por detrás de los jugadores mientras la cabeza
## (dibujada por el proyectil) queda por delante.

const LANZA_TEX := preload("uid://ksj6jcxhc5yk")


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var parent := get_parent()
	if parent == null:
		return

	var o: Vector2 = parent.origin - parent.global_position
	var dist := o.length()
	if dist < 8.0:
		return

	var dir := -o.normalized()
	var seg_w: float = LANZA_TEX.get_width()
	var seg_h: float = LANZA_TEX.get_height()

	# Mismo eje que la cabeza: +X apunta hacia la punta.
	draw_set_transform(Vector2.ZERO, dir.angle(), Vector2.ONE)

	var step: float = seg_w * 0.9
	var x: float = dist - seg_w * 0.5
	while x > 0.0:
		draw_texture_rect(LANZA_TEX,
			Rect2(-x - seg_w * 0.5, -seg_h * 0.5, seg_w, seg_h), false)
		x -= step

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
