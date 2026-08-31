extends Control
## TpBarCustom — Barra TP horizontal paralelogramo 340x38
## Más grande, separada del panel, sin fondo propio, bordes negros.
## Muestra TP a la izquierda y puntos actuales/max a la derecha (fuera de la barra).
## Ticks por coste real (AbilityData.tp_cost) con forma slanted.

@onready var _progress: ProgressBar = $HBoxContainer/BgPanel/BarRoot/TpProgress
@onready var _overlay: Control = $HBoxContainer/BgPanel/BarRoot/SegmentOverlay
@onready var _cost_markers: Control = $HBoxContainer/BgPanel/BarRoot/CostMarkers
@onready var _tp_label: Label = $HBoxContainer/TpTag
@onready var _points_label: Label = $HBoxContainer/PointsLabel
@onready var _bg_panel: PanelContainer = $HBoxContainer/BgPanel
@onready var _bar_root: Control = $HBoxContainer/BgPanel/BarRoot

const COLOR_NORMAL: Color = Color(0.816, 0.592, 0.0, 1.0)
const COLOR_MAX: Color = Color(1.0, 0.871, 0.0, 1.0)
const COLOR_TICK: Color = Color(0.55, 0.55, 0.55, 1.0)
const COLOR_COST: Color = Color(1.0, 0.92, 0.3, 1.0)
const COLOR_COST_READY: Color = Color(1.0, 1.0, 1.0, 1.0)
const BG_COLOR: Color = Color(0.3808012, 0.052263863, 0, 1.0)
const BORDER_COLOR: Color = Color(0, 0, 0, 1)
const SKEW: float = 14.0

var _peer_id: int = -1
var _max_tp: float = 100.0
var _current_tp: float = 0.0
var _costs: Array[float] = []
var _cost_ready: Array[bool] = []
var _pulse_tween: Tween = null
var _fill_lerp_tween: Tween = null
var _display_value: float = 0.0
var _fill_color: Color = COLOR_NORMAL

@export var pulse_when_full: bool = true
@export var show_cost_ticks: bool = true
@export var anim_speed: float = 0.18


func _ready() -> void:
	custom_minimum_size = Vector2(360, 24)
	size = Vector2(360, 24)
	if _progress:
		_progress.max_value = _max_tp
		_progress.value = 0
		_progress.show_percentage = false
		_progress.visible = false
	_update_labels()
	if _overlay:
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not _overlay.draw.is_connected(_on_overlay_draw):
			_overlay.draw.connect(_on_overlay_draw)
	if _cost_markers:
		_cost_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not _cost_markers.draw.is_connected(_on_cost_markers_draw):
			_cost_markers.draw.connect(_on_cost_markers_draw)
	if _bar_root:
		_bar_root.resized.connect(func(): 
			if _overlay: _overlay.queue_redraw()
			if _cost_markers: _cost_markers.queue_redraw()
		)
	queue_redraw()


func setup(peer_id: int, max_tp: float) -> void:
	_peer_id = peer_id
	_max_tp = max_tp if max_tp > 0 else 100.0
	_current_tp = 0.0
	_display_value = 0.0
	_fill_color = COLOR_NORMAL
	if _progress:
		_progress.max_value = _max_tp
		_progress.value = 0
	_refresh_costs()
	if _find_player(_peer_id) == null:
		await get_tree().process_frame
		_refresh_costs()
	var relay: Node = GameServiceLocator.get_client_relay()
	if relay:
		if relay.has_signal("tp_changed") and not relay.tp_changed.is_connected(_on_tp_changed):
			relay.tp_changed.connect(_on_tp_changed)
		if relay.has_signal("dynamic_tp_cost_changed") and not relay.dynamic_tp_cost_changed.is_connected(_on_dynamic_cost_changed):
			relay.dynamic_tp_cost_changed.connect(_on_dynamic_cost_changed)
	var tp_svc: Node = GameServiceLocator.get_service("TPService") if GameServiceLocator.has_method("get_service") else null
	if tp_svc and tp_svc.has_method("get_tp_for_peer"):
		var cached: float = tp_svc.get_tp_for_peer(_peer_id)
		if cached > 0:
			_update_ui(cached, true)


func _refresh_costs() -> void:
	_costs.clear()
	_cost_ready.clear()
	var player := _find_player(_peer_id)
	var char_data: Resource = null
	if player and "character_data" in player and player.character_data:
		char_data = player.character_data
		var slots: Array = char_data.ability_slots if "ability_slots" in char_data else []
		for slot in slots:
			if slot == null:
				continue
			var cost: float = float(slot.tp_cost) if "tp_cost" in slot else 0.0
			if cost <= 0.001:
				continue
			var dup := false
			for c in _costs:
				if is_equal_approx(c, cost):
					dup = true
					break
			if not dup:
				_costs.append(cost)
		_costs.sort()
	if _costs.is_empty() and show_cost_ticks:
		_costs = [_max_tp * 0.25, _max_tp * 0.5, _max_tp * 0.75]
	for i in _costs.size():
		_cost_ready.append(_current_tp >= _costs[i])
	if _cost_markers:
		_cost_markers.queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


func _find_player(peer_id: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_multiplayer_authority() == peer_id:
			return p
	return null


func _on_tp_changed(peer_id: int, current_tp: float, max_tp: float) -> void:
	if peer_id != _peer_id:
		return
	_max_tp = max_tp if max_tp > 0 else _max_tp
	if _progress:
		_progress.max_value = _max_tp
	_refresh_costs()
	_update_ui(current_tp, false)


func _on_dynamic_cost_changed(_slot_index: int, _cost: float) -> void:
	_refresh_costs()
	_update_markers_ready_state()


func _update_ui(value: float, instant: bool) -> void:
	_current_tp = clampf(value, 0.0, _max_tp)
	_update_markers_ready_state()
	var ratio: float = clampf(_current_tp / _max_tp, 0.0, 1.0) if _max_tp > 0 else 0.0
	var is_max: bool = ratio >= 0.999

	if instant or anim_speed <= 0.001:
		_display_value = _current_tp
		if _progress:
			_progress.value = _display_value
		_fill_color = COLOR_MAX if is_max else COLOR_NORMAL
		if _overlay: _overlay.queue_redraw()
		if _cost_markers: _cost_markers.queue_redraw()
	else:
		if _fill_lerp_tween and _fill_lerp_tween.is_valid():
			_fill_lerp_tween.kill()
		_fill_lerp_tween = create_tween()
		_fill_lerp_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_fill_lerp_tween.tween_method(func(v: float) -> void:
			_display_value = v
			if _progress:
				_progress.value = _display_value
			# Actualizar color durante tween también
			var r: float = clampf(_display_value / _max_tp, 0.0, 1.0) if _max_tp > 0 else 0.0
			_fill_color = COLOR_MAX if r >= 0.999 else COLOR_NORMAL
			if _overlay: _overlay.queue_redraw()
		, _display_value, _current_tp, anim_speed)

	_update_labels()

	if is_max and pulse_when_full:
		_start_pulse()
	else:
		_stop_pulse()

	if _cost_markers:
		_cost_markers.queue_redraw()


func _update_markers_ready_state() -> void:
	for i in _costs.size():
		_cost_ready[i] = _current_tp >= _costs[i]


func _update_labels() -> void:
	var is_max: bool = _current_tp >= _max_tp - 0.001
	if _points_label:
		_points_label.text = "%d/%d" % [int(_current_tp), int(_max_tp)]
		_points_label.modulate = COLOR_MAX if is_max else Color.WHITE
	if _tp_label:
		_tp_label.modulate = COLOR_MAX if is_max else Color.WHITE


func _get_bar_rect(overlay: Control) -> Rect2:
	var s: Vector2 = overlay.size
	if s.x < 2 or s.y < 2:
		s = _bar_root.size if _bar_root else Vector2(340, 20)
		if s.x < 2: s = Vector2(340, 20)
	return Rect2(Vector2.ZERO, s)


func _on_overlay_draw() -> void:
	if not _overlay:
		return
	var rect: Rect2 = _get_bar_rect(_overlay)
	var w: float = rect.size.x
	var h: float = rect.size.y
	if w <= 1 or h <= 1:
		return
	var skew: float = SKEW
	var bg_pts := PackedVector2Array([
		Vector2(skew, 0),
		Vector2(w, 0),
		Vector2(w - skew, h),
		Vector2(0, h)
	])
	# Fondo paralelogramo
	_overlay.draw_colored_polygon(bg_pts, BG_COLOR)
	# Fill paralelogramo
	var ratio: float = clampf(_display_value / _max_tp, 0.0, 1.0) if _max_tp > 0 else 0.0
	if ratio > 0.001:
		var fill_w: float = (w - skew) * ratio
		var fill_pts := PackedVector2Array([
			Vector2(skew, 0),
			Vector2(skew + fill_w, 0),
			Vector2(fill_w, h),
			Vector2(0, h)
		])
		_overlay.draw_colored_polygon(fill_pts, _fill_color)
	# Borde negro
	_overlay.draw_polyline(bg_pts + PackedVector2Array([bg_pts[0]]), BORDER_COLOR, 2.0, true)
	# Ticks slanted por coste real
	if show_cost_ticks:
		for i in _costs.size():
			var cost: float = _costs[i]
			var r: float = clampf(cost / _max_tp, 0.0, 1.0) if _max_tp > 0 else 0.0
			var top_x: float = skew + (w - skew) * r
			var bottom_x: float = (w - skew) * r
			var ready: bool = _cost_ready[i] if i < _cost_ready.size() else false
			var col: Color = COLOR_COST_READY if ready else COLOR_TICK
			# Tick slanted paralelo al borde
			_overlay.draw_line(Vector2(top_x, 1), Vector2(bottom_x, h - 1), col, 1.8)


func _on_cost_markers_draw() -> void:
	if not _cost_markers or not show_cost_ticks:
		return
	var rect: Rect2 = _get_bar_rect(_cost_markers)
	var w: float = rect.size.x
	var h: float = rect.size.y
	if w <= 1:
		return
	var skew: float = SKEW
	for i in _costs.size():
		var cost: float = _costs[i]
		var r: float = clampf(cost / _max_tp, 0.0, 1.0) if _max_tp > 0 else 0.0
		var top_x: float = skew + (w - skew) * r
		var bottom_x: float = (w - skew) * r
		var center_x: float = (top_x + bottom_x) * 0.5
		var ready: bool = _cost_ready[i] if i < _cost_ready.size() else false
		var col: Color = COLOR_COST_READY if ready else COLOR_COST
		# Diamante pequeño en borde superior del paralelogramo
		var diamond := PackedVector2Array([
			Vector2(center_x, 1),
			Vector2(center_x + 4, 5),
			Vector2(center_x, 9),
			Vector2(center_x - 4, 5)
		])
		_cost_markers.draw_colored_polygon(diamond, col)
		if ready:
			_cost_markers.draw_circle(Vector2(center_x, 5), 1.3, Color.WHITE)


func _start_pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		return
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_method(func(c: Color): _fill_color = c; if _overlay: _overlay.queue_redraw(), COLOR_MAX, Color.WHITE, 0.45)
	_pulse_tween.tween_method(func(c: Color): _fill_color = c; if _overlay: _overlay.queue_redraw(), Color.WHITE, COLOR_MAX, 0.45)


func _stop_pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	_fill_color = COLOR_MAX if _current_tp >= _max_tp - 0.001 else COLOR_NORMAL
	if _overlay: _overlay.queue_redraw()


func _exit_tree() -> void:
	var relay: Node = GameServiceLocator.get_client_relay()
	if relay:
		if relay.has_signal("tp_changed") and relay.tp_changed.is_connected(_on_tp_changed):
			relay.tp_changed.disconnect(_on_tp_changed)
		if relay.has_signal("dynamic_tp_cost_changed") and relay.dynamic_tp_cost_changed.is_connected(_on_dynamic_cost_changed):
			relay.dynamic_tp_cost_changed.disconnect(_on_dynamic_cost_changed)
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if _fill_lerp_tween and _fill_lerp_tween.is_valid():
		_fill_lerp_tween.kill()
