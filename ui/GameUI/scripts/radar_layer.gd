extends Control

enum ArrowType { HIT, DOWN, MAP }

const COLORS := {
	ArrowType.HIT: Color(1.0, 0.65, 0.0),
	ArrowType.DOWN: Color(1.0, 0.0, 0.0),
	ArrowType.MAP: Color(1.0, 1.0, 1.0),
}

# Aumenta/reduce estos valores para cambiar el tamaño de la flecha de borde
const ARROW_LENGTH := 24.0
const ARROW_WIDTH := 14.0

# Tamaño del marcador visible en pantalla (▼ sobre la cabeza)
const MARKER_SIZE := 10.0

const MARGIN := 24.0
const MARKER_OFFSET_Y := -60.0

var _arrows: Dictionary = {}
var _my_id: int = 0
var _my_team: String = "survivor"


func setup(my_id: int, my_team: String) -> void:
	_my_id = my_id
	_my_team = my_team
	var svc = GameServiceLocator.get_service("RadarService")
	if svc:
		if svc.arrow_spawned.is_connected(_on_arrow_spawned):
			return
		svc.arrow_spawned.connect(_on_arrow_spawned)
		svc.arrow_despawned.connect(_on_arrow_despawned)


func _on_arrow_spawned(arrow_id: int, type: int, target_pos: Vector2, track_peer: int, filter_peer: int, duration: float) -> void:
	if type == ArrowType.HIT and _my_team != "survivor":
		return
	if type == ArrowType.DOWN and _my_team != "survivor":
		return
	if _my_id > 0 and filter_peer == _my_id:
		return
	_arrows[arrow_id] = {
		"type": type,
		"target_pos": target_pos,
		"track_peer": track_peer,
		"filter_peer": filter_peer,
		"timer": duration if duration > 0.0 else -1.0,
		"color": COLORS.get(type, Color.WHITE),
	}
	queue_redraw()


func _on_arrow_despawned(arrow_id: int) -> void:
	_arrows.erase(arrow_id)
	queue_redraw()


func _process(delta: float) -> void:
	var changed := false
	for arrow_id in _arrows.keys():
		var entry = _arrows[arrow_id]
		if entry["timer"] > 0.0:
			entry["timer"] -= delta
			if entry["timer"] <= 0.0:
				_arrows.erase(arrow_id)
				changed = true
				continue
		if entry["track_peer"] > 0:
			var player = _find_player(entry["track_peer"])
			if player:
				entry["target_pos"] = player.global_position
			else:
				_arrows.erase(arrow_id)
				changed = true
	if changed:
		queue_redraw()
	queue_redraw()


func _draw() -> void:
	var screen_size = get_viewport_rect().size
	if screen_size == Vector2.ZERO:
		return
	var center = screen_size * 0.5
	var screen_rect := Rect2(Vector2.ZERO, screen_size)

	for entry in _arrows.values():
		var cam = get_viewport().get_camera_2d()
		if not cam:
			continue
		var screen_pos = cam.get_canvas_transform() * entry["target_pos"]

		if screen_rect.has_point(screen_pos):
			var marker_pos := Vector2(screen_pos.x, screen_pos.y + MARKER_OFFSET_Y)
			_draw_down_marker(marker_pos, entry["color"])
		else:
			var dir = screen_pos - center
			if dir.length_squared() < 1.0:
				continue
			dir = dir.normalized()
			var edge_pos = _edge_intersection(center, dir, screen_size)
			_draw_edge_arrow(edge_pos, dir.angle(), entry["color"])


func _edge_intersection(center: Vector2, dir: Vector2, screen_size: Vector2) -> Vector2:
	var half: Vector2 = screen_size * 0.5 - Vector2(MARGIN, MARGIN)
	var s: float = abs(dir.x) + abs(dir.y)
	if s < 0.001:
		return center
	var t_x: float = half.x / max(abs(dir.x), 0.001)
	var t_y: float = half.y / max(abs(dir.y), 0.001)
	var t: float = min(t_x, t_y)
	return center + dir * t


func _draw_edge_arrow(pos: Vector2, angle: float, color: Color) -> void:
	var half_len := ARROW_LENGTH * 0.5
	var half_wid := ARROW_WIDTH * 0.5
	var tip = Vector2(half_len, 0.0)
	var base_left = Vector2(-half_len, -half_wid)
	var base_right = Vector2(-half_len, half_wid)
	var notch = Vector2(-half_len * 0.5, 0.0)

	var cos_a = cos(angle)
	var sin_a = sin(angle)

	var pts := PackedVector2Array()
	pts.resize(4)
	pts[0] = pos + _rotated(tip, cos_a, sin_a)
	pts[1] = pos + _rotated(base_left, cos_a, sin_a)
	pts[2] = pos + _rotated(notch, cos_a, sin_a)
	pts[3] = pos + _rotated(base_right, cos_a, sin_a)
	draw_polygon(pts, PackedColorArray([color, color, color, color]))


func _draw_down_marker(pos: Vector2, color: Color) -> void:
	var s := MARKER_SIZE
	var top_left := Vector2(-s, -s)
	var top_right := Vector2(s, -s)
	var bottom := Vector2(0.0, s)
	var notch := Vector2(0.0, -s * 0.5)

	var pts := PackedVector2Array()
	pts.resize(4)
	pts[0] = pos + top_left
	pts[1] = pos + top_right
	pts[2] = pos + notch
	pts[3] = pos + bottom
	draw_polygon(pts, PackedColorArray([color, color, color, color]))


static func _rotated(v: Vector2, cos_a: float, sin_a: float) -> Vector2:
	return Vector2(v.x * cos_a - v.y * sin_a, v.x * sin_a + v.y * cos_a)


func _find_player(peer_id: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_multiplayer_authority() == peer_id:
			return p
	return null
