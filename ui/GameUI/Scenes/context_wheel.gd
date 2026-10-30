# res://ui/GameUI/Scenes/context_wheel.gd
# Rueda de selección de objetivo. Se centra en la posición en pantalla del
# caster y muestra un wedget por objetivo alrededor del centro.
extends Control

signal confirmed(peer_id: int)
signal cancelled

const ITEM_SCENE := preload("res://ui/GameUI/Scenes/ContextItem.tscn")
const FONT := preload("res://Fonts/deltarune-battle-dialogue.ttf")
const RADIUS: float = 190.0
const ITEM_SIZE := Vector2(210.0, 34.0)
const TITLE_SIZE := Vector2(560.0, 34.0)
const HINT_SIZE := Vector2(640.0, 24.0)

var _items: Array = []
var _item_nodes: Array[Control] = []
var _selected := 0
var _caster: Node2D = null
var _center := Vector2.ZERO
var _open := false
var _title: Label = null
var _hint: Label = null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	set_process(false)

	_title = Label.new()
	_title.name = "WheelTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_override("font", FONT)
	_title.add_theme_font_size_override("font_size", 20)
	add_child(_title)

	_hint = Label.new()
	_hint.name = "WheelHint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_override("font", FONT)
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.modulate = Color(0.75, 0.75, 0.75, 1.0)
	add_child(_hint)


func open(title: String, options: Array, caster: Node = null) -> void:
	_items = options.duplicate(true)
	_caster = caster as Node2D
	_selected = 0
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

	_title.text = title.to_upper()
	var hint_text := tr("HUD_TARGET_HINT")
	if hint_text == "HUD_TARGET_HINT":
		hint_text = "← → ELEGIR · Z CONFIRMAR · X CANCELAR"
	_hint.text = hint_text

	_apply_theme()
	_build_items()
	_update_center()
	_reflow()
	_select(0, false)
	queue_redraw()


func cancel() -> void:
	if not _open:
		return
	_close()
	cancelled.emit()


func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false

	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		cancel()
		return true

	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and (
			event.keycode == KEY_Z or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)):
		_confirm()
		return true

	if (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up")
			or event.is_action_pressed("menu_left") or event.is_action_pressed("menu_up")):
		_select(_selected - 1)
		return true
	if (event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down")
			or event.is_action_pressed("menu_right") or event.is_action_pressed("menu_down")):
		_select(_selected + 1)
		return true

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel()
		return true

	return false


func _gui_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_LEFT:
			# Los clicks sobre un ítem los consume el ítem; esto es el fondo.
			cancel()


func _process(_delta: float) -> void:
	if not _open:
		return
	var old_center := _center
	_update_center()
	if old_center != _center:
		_reflow()
		queue_redraw()


func _build_items() -> void:
	for n in _item_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_item_nodes.clear()

	for i in _items.size():
		var opt: Dictionary = _items[i]
		var item := ITEM_SCENE.instantiate() as Control
		if item == null:
			continue
		item.anchor_left = 0.0
		item.anchor_top = 0.0
		item.anchor_right = 0.0
		item.anchor_bottom = 0.0
		item.offset_left = 0.0
		item.offset_top = 0.0
		item.offset_right = ITEM_SIZE.x
		item.offset_bottom = ITEM_SIZE.y
		item.custom_minimum_size = ITEM_SIZE
		item.size = ITEM_SIZE
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(item)

		item.setup(
			int(opt.get("peer_id", -1)),
			str(opt.get("display_name", "")),
			opt.get("frames", null),
			opt.get("icon", null),
			str(opt.get("player_name", "")),
			str(opt.get("status", ""))
		)
		_ignore_mouse_children(item)
		item.mouse_filter = Control.MOUSE_FILTER_STOP

		item.item_clicked.connect(_on_item_clicked)
		item.mouse_entered.connect(_on_item_hovered.bind(i))
		_item_nodes.append(item)


func _ignore_mouse_children(node: Node) -> void:
	for c in node.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			_ignore_mouse_children(c)


func _update_center() -> void:
	if is_instance_valid(_caster) and _caster.is_inside_tree():
		_center = _caster.get_global_transform_with_canvas().origin
	else:
		_center = get_viewport_rect().size * 0.5

	# Mantener la rueda completa dentro del viewport.
	var vp := get_viewport_rect().size
	var margin := RADIUS + ITEM_SIZE.x * 0.5 + 28.0
	if vp.x > margin * 2.0:
		_center.x = clampf(_center.x, margin, vp.x - margin)
	else:
		_center.x = vp.x * 0.5
	if vp.y > margin * 2.0:
		_center.y = clampf(_center.y, margin, vp.y - margin)
	else:
		_center.y = vp.y * 0.5

	_title.size = TITLE_SIZE
	_title.position = _center + Vector2(-TITLE_SIZE.x * 0.5, -RADIUS - 74.0)
	_hint.size = HINT_SIZE
	_hint.position = _center + Vector2(-HINT_SIZE.x * 0.5, RADIUS + 26.0)


func _reflow() -> void:
	var count := _item_nodes.size()
	if count == 0:
		return
	var step := TAU / float(count)
	for i in count:
		var angle := -PI * 0.5 + step * float(i)
		var item := _item_nodes[i]
		item.size = ITEM_SIZE
		item.position = _center + Vector2(cos(angle), sin(angle)) * RADIUS - ITEM_SIZE * 0.5
		item.pivot_offset = ITEM_SIZE * 0.5
		item.scale = Vector2(1.08, 1.08) if i == _selected else Vector2.ONE


func _select(idx: int, play_sound: bool = true) -> void:
	if _item_nodes.is_empty():
		return
	var next := posmod(idx, _item_nodes.size())
	if play_sound and next != _selected:
		var am := get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.MENU_MOVE)
	_selected = next
	for i in _item_nodes.size():
		var item := _item_nodes[i]
		if item.has_method("set_selected"):
			item.set_selected(i == _selected)
		item.scale = Vector2(1.08, 1.08) if i == _selected else Vector2.ONE
	queue_redraw()


func _on_item_hovered(idx: int) -> void:
	_select(idx, false)


func _on_item_clicked(peer_id: int) -> void:
	_confirm(peer_id)


func _confirm(peer_id: int = -1) -> void:
	if not _open:
		return
	var target := peer_id
	if target < 0:
		if _selected < 0 or _selected >= _items.size():
			return
		target = int((_items[_selected] as Dictionary).get("peer_id", -1))
	if target < 0:
		return
	_close()
	confirmed.emit(target)


func _close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	for n in _item_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_item_nodes.clear()
	_items.clear()
	_caster = null
	queue_redraw()


func _apply_theme() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	var pal: Dictionary = tm.get_palette() if tm and tm.has_method("get_palette") else {}
	var title_col: Color = pal.get("title", Color(1, 1, 1, 1))
	var hint_col: Color = pal.get("hint", Color(0.75, 0.75, 0.75, 1))
	if _title:
		_title.add_theme_color_override("font_color", title_col)
	if _hint:
		_hint.add_theme_color_override("font_color", hint_col)


func _draw() -> void:
	if not _open:
		return
	var tm := get_node_or_null("/root/ThemeManager")
	var pal: Dictionary = tm.get_palette() if tm and tm.has_method("get_palette") else {}
	var sel: Color = pal.get("selected", Color(1.0, 0.87, 0.0, 1.0))
	var dim: Color = pal.get("dim", Color(0.0, 0.5, 0.0, 1.0))

	draw_circle(_center, RADIUS + ITEM_SIZE.y * 0.8, Color(0.0, 0.0, 0.0, 0.38))
	draw_arc(_center, RADIUS, 0.0, TAU, 96, Color(dim.r, dim.g, dim.b, 0.75), 2.0, true)

	if _selected >= 0 and _selected < _item_nodes.size():
		var item := _item_nodes[_selected]
		var item_center := item.position + item.size * 0.5
		draw_line(_center, item_center, sel, 2.0, true)
		draw_circle(_center, 8.0, sel)
