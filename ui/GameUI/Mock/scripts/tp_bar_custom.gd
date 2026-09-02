extends Control
## TpBarCustom — Barra TP horizontal paralelogramo 340x38
## Más grande, separada del panel, sin fondo propio, bordes negros.
## Muestra TP a la izquierda y puntos actuales/max a la derecha (fuera de la barra).
## Ticks por coste real (AbilityData.tp_cost) con forma slanted.

@onready var _progress: ProgressBar = $VBoxContainer/HBoxContainer/BgPanel/BarRoot/TpProgress
@onready var _overlay: Control = $VBoxContainer/HBoxContainer/BgPanel/BarRoot/SegmentOverlay
@onready var _cost_markers: Control = $VBoxContainer/HBoxContainer/BgPanel/BarRoot/CostMarkers
@onready var _tp_label: Label = $VBoxContainer/HBoxContainer/TpTag
@onready var _points_label: Label = $VBoxContainer/PointsLabel
@onready var _bg_panel: PanelContainer = $VBoxContainer/HBoxContainer/BgPanel
@onready var _bar_root: Control = $VBoxContainer/HBoxContainer/BgPanel/BarRoot

const COLOR_NORMAL: Color = Color(0.816, 0.592, 0.0, 1.0)
const COLOR_MAX: Color = Color(1.0, 0.871, 0.0, 1.0)
const COLOR_TICK: Color = Color(0.55, 0.55, 0.55, 1.0)
const COLOR_COST: Color = Color(1.0, 0.92, 0.3, 1.0)
const COLOR_COST_READY: Color = Color(1.0, 1.0, 1.0, 1.0)
const BG_COLOR: Color = Color(0.3808012, 0.052263863, 0, 1.0)
const BORDER_COLOR: Color = Color(0, 0, 0, 1)
const SKEW: float = 14.0
const STAR_TEX: Texture2D = preload("res://ui/GameUI/Scenes/star.png")

var _peer_id: int = -1
var _max_tp: float = 100.0
var _current_tp: float = 0.0
var _costs: Array[float] = []
var _cost_ready: Array[bool] = []
var _pulse_tween: Tween = null
var _fill_lerp_tween: Tween = null
var _display_value: float = 0.0
var _fill_color: Color = COLOR_NORMAL
var _dynamic_overrides: Dictionary = {}
var _star_display_x: Array[float] = []
var _star_tweens: Array[Tween] = []

@export var pulse_when_full: bool = true
@export var show_cost_ticks: bool = true
@export var anim_speed: float = 0.18


func _ready() -> void:
	custom_minimum_size = Vector2(430, 100)
	size = Vector2(430, 100)
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
	_dynamic_overrides.clear()
	_star_display_x.clear()
	_star_tweens.clear()
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
		if relay.has_signal("ability_slot_updated") and not relay.ability_slot_updated.is_connected(_on_ability_slot_updated):
			relay.ability_slot_updated.connect(_on_ability_slot_updated)
	var tp_svc: Node = GameServiceLocator.get_service("TPService") if GameServiceLocator.has_method("get_service") else null
	if tp_svc and tp_svc.has_method("get_tp_for_peer"):
		var cached: float = tp_svc.get_tp_for_peer(_peer_id)
		if cached > 0:
			_update_ui(cached, true)


func _get_effective_cost(slot: Resource, idx: int) -> float:
	var base: float = float(slot.tp_cost) if slot and "tp_cost" in slot else 0.0
	if _dynamic_overrides.has(idx):
		return float(_dynamic_overrides[idx])
	if not multiplayer.is_server():
		return base
	var svc: Node = GameServiceLocator.get_service("AbilityStateService") if GameServiceLocator.has_method("get_service") else null
	if svc == null:
		svc = GameServiceLocator.ability_state
	if svc and svc.has_method("get_dynamic_tp_cost"):
		var dyn: float = svc.get_dynamic_tp_cost(_peer_id, idx)
		if dyn > 0.001:
			return dyn
	return base


func _refresh_costs() -> void:
	var old_costs: Array[float] = _costs.duplicate()
	var old_display: Array[float] = _star_display_x.duplicate()
	_costs.clear()
	_cost_ready.clear()
	var player := _find_player(_peer_id)
	var char_data: Resource = null
	if player and "character_data" in player and player.character_data:
		char_data = player.character_data
		var slots: Array = char_data.ability_slots if "ability_slots" in char_data else []
		for idx in slots.size():
			var slot: Resource = slots[idx]
			if slot == null:
				continue
			var cost: float = _get_effective_cost(slot, idx)
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
	# Inicializar o animar posiciones de estrellas
	_sync_star_display(old_costs, old_display)
	if _cost_markers:
		_cost_markers.queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


func _sync_star_display(old_costs: Array[float], old_display: Array[float]) -> void:
	# Asegurar tamaño
	if _star_display_x.size() != _costs.size():
		# Si cambió cantidad, reinicializar sin tween
		_star_display_x.resize(_costs.size())
		_star_tweens.resize(_costs.size())
		for i in _costs.size():
			var r: float = clampf(_costs[i] / _max_tp, 0.0, 1.0) if _max_tp > 0 else 0.0
			var w: float = _get_bar_width()
			var target_x: float = (SKEW + (w - SKEW) * r + (w - SKEW) * r) * 0.5
			_star_display_x[i] = target_x
		return
	# Animar cada estrella 0.20s CUBIC_OUT si cambió
	for i in _costs.size():
		var r: float = clampf(_costs[i] / _max_tp, 0.0, 1.0) if _max_tp > 0 else 0.0
		var w: float = _get_bar_width()
		var target_x: float = (SKEW + (w - SKEW) * r + (w - SKEW) * r) * 0.5
		var from_x: float = old_display[i] if i < old_display.size() else target_x
		if old_costs.is_empty() or i >= old_costs.size():
			_star_display_x[i] = target_x
			continue
		if is_equal_approx(from_x, target_x):
			_star_display_x[i] = target_x
			continue
		if i < _star_tweens.size() and _star_tweens[i] and _star_tweens[i].is_valid():
			_star_tweens[i].kill()
		var idx: int = i
		var tw: Tween = create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v: float) -> void:
			_star_display_x[idx] = v
			if _cost_markers: _cost_markers.queue_redraw()
		, from_x, target_x, 0.20)
		_star_tweens[idx] = tw


func _get_bar_width() -> float:
	if _bar_root and _bar_root.size.x > 2:
		return _bar_root.size.x
	if _overlay and _overlay.size.x > 2:
		return _overlay.size.x
	return 200.0


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


func _on_dynamic_cost_changed(slot_index: int, cost: float) -> void:
	_dynamic_overrides[slot_index] = cost
	_refresh_costs()
	_update_markers_ready_state()
	if _cost_markers:
		_cost_markers.queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


func _on_ability_slot_updated(slot_index: int, tp_cost: float, _cooldown: float, _stage: int) -> void:
	_dynamic_overrides[slot_index] = tp_cost
	_refresh_costs()
	_update_markers_ready_state()
	if _cost_markers:
		_cost_markers.queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


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
		s = _bar_root.size if _bar_root else Vector2(200, 40)
		if s.x < 2: s = Vector2(200, 40)
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
	for i in _costs.size():
		var display_x: float
		if i < _star_display_x.size():
			display_x = _star_display_x[i]
		else:
			var r2: float = clampf(_costs[i] / _max_tp, 0.0, 1.0) if _max_tp > 0 else 0.0
			var top2: float = SKEW + (w - SKEW) * r2
			var bottom2: float = (w - SKEW) * r2
			display_x = (top2 + bottom2) * 0.5
		var ready: bool = _cost_ready[i] if i < _cost_ready.size() else false
		var col: Color = COLOR_COST_READY if ready else COLOR_COST
		if STAR_TEX:
			var tex_size := Vector2(12, 12)
			var pos := Vector2(display_x - tex_size.x * 0.5, -10)
			_cost_markers.draw_texture_rect(STAR_TEX, Rect2(pos, tex_size), false, col)
		else:
			var diamond := PackedVector2Array([
				Vector2(display_x, 1),
				Vector2(display_x + 4, 5),
				Vector2(display_x, 9),
				Vector2(display_x - 4, 5)
			])
			_cost_markers.draw_colored_polygon(diamond, col)
			if ready:
				_cost_markers.draw_circle(Vector2(display_x, 5), 1.3, Color.WHITE)


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
		if relay.has_signal("ability_slot_updated") and relay.ability_slot_updated.is_connected(_on_ability_slot_updated):
			relay.ability_slot_updated.disconnect(_on_ability_slot_updated)
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	if _fill_lerp_tween and _fill_lerp_tween.is_valid():
		_fill_lerp_tween.kill()
	for tw in _star_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_star_tweens.clear()
