# res://core/menu_backdrop.gd
# Fondo persistente de los menús. Vive por encima del clear color pero por
# debajo de la escena actual, así cambiar de menú no reinicia el fondo LIGHT.
extends Node

const LAYER := -10
const THEME_FADE_OUT := 0.45
const THEME_FADE_IN := 0.55

var _layer: CanvasLayer
var _root: Control
var _darken: ColorRect
var _current: Control
var _current_id := ""
var _attached := false
var _want_visible := false
var _transitioning := false
var _pending_id := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer = CanvasLayer.new()
	_layer.name = "MenuBackdropLayer"
	_layer.layer = LAYER
	_layer.visible = false

	_root = Control.new()
	_root.name = "MenuBackdropRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_root)

	# Overlay de oscurecido del fondo. Está por encima del fondo pero dentro
	# del CanvasLayer del backdrop (-10), así no tapa la UI de la escena (0).
	_darken = ColorRect.new()
	_darken.name = "ThemeDarken"
	_darken.color = Color(0, 0, 0, 0)
	_darken.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_darken.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_darken.z_index = 100
	_layer.add_child(_darken)

	_attach_layer.call_deferred()

	var tm := _theme_manager()
	if tm:
		if tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)
		_rebuild(str(tm.current_theme_id), false)

	set_process(true)


## Llamado por ThemeManager.apply_to_background() en el _ready de cada menú.
## Muestra el fondo antes del primer draw de la escena nueva.
func prepare_for_menu(id: String = "") -> void:
	var tm := _theme_manager()
	var want := id
	if want == "" and tm:
		want = str(tm.current_theme_id)
	if want == "":
		want = "device"

	_want_visible = true
	if _attached and is_instance_valid(_layer):
		_layer.visible = true

	# Mientras dura el cambio de tema no dejar que prepare_for_menu haga
	# un swap instantáneo: la secuencia la maneja _on_theme_changed.
	if _transitioning:
		return

	if want != _current_id or _current == null or not is_instance_valid(_current):
		_rebuild(want, false)


func _attach_layer() -> void:
	if not is_instance_valid(_layer):
		return
	if _layer.get_parent() == null:
		get_tree().root.add_child(_layer)
	_attached = true
	_layer.visible = _want_visible


func _process(_delta: float) -> void:
	if not _attached or not is_instance_valid(_layer):
		return

	var path := ""
	if get_tree().current_scene:
		path = get_tree().current_scene.scene_file_path
	if path == "":
		return

	_want_visible = path.begins_with("res://ui/MainMenu/scenes/")
	if _want_visible != _layer.visible:
		_layer.visible = _want_visible


func _on_theme_changed(id: String) -> void:
	if not _want_visible:
		_rebuild(id, false)
		return

	if _transitioning:
		_pending_id = id
		return

	var old := _current

	# Sin fondo previo (primer build): aparece directo.
	if not is_instance_valid(old):
		var first_bg := _make_bg(id)
		_root.add_child(first_bg)
		_make_mouse_ignore(first_bg)
		_current = first_bg
		_current_id = id
		return

	_transitioning = true

	# 1) Oscurecer TODO el fondo por igual con un overlay negro dentro del
	# backdrop. No usamos modulate de las capas porque el shader LIGHT
	# sobrescribe COLOR y no lo respeta.
	await _fade_darken(1.0, THEME_FADE_OUT)

	# 2) Con el fondo ya negro, cambiar la escena de fondo.
	var new_bg := _make_bg(id)
	_root.add_child(new_bg)
	_make_mouse_ignore(new_bg)
	_current = new_bg
	_current_id = id
	if is_instance_valid(old):
		old.queue_free()

	# Que el shader/textura del nuevo esté listo antes de revelarlo.
	await get_tree().process_frame
	await get_tree().process_frame

	if not is_instance_valid(new_bg):
		_transitioning = false
		await _fade_darken(0.0, THEME_FADE_IN)
		return

	# Si llegó otro tema mientras oscurecía, seguimos con el último sin
	# revelar el intermedio.
	if _pending_id != "":
		_transitioning = false
		var next_id := _pending_id
		_pending_id = ""
		_on_theme_changed(next_id)
		return

	# 3) Recién ahí revelar el fondo nuevo.
	await _fade_darken(0.0, THEME_FADE_IN)
	_transitioning = false
	if _pending_id != "":
		var next_id := _pending_id
		_pending_id = ""
		_on_theme_changed(next_id)


func _fade_darken(target: float, duration: float) -> void:
	if _darken == null:
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_darken, "color:a", target, duration)
	await tw.finished


func _theme_manager() -> Node:
	return get_node_or_null("/root/ThemeManager")


func _make_bg(id: String) -> Control:
	var tm := _theme_manager()
	var bg: Control = null

	if tm and tm.has_method("get_background_scene"):
		var scene: PackedScene = tm.get_background_scene(id)
		if scene:
			bg = scene.instantiate() as Control

	if bg == null:
		bg = ColorRect.new()
		var col := Color.BLACK
		if tm and tm.has_method("get_base_palette"):
			col = tm.get_base_palette(id).get("bg", Color.BLACK)
		elif tm and tm.has_method("get_palette"):
			col = tm.get_palette(id).get("bg", Color.BLACK)
		(bg as ColorRect).color = col

	bg.name = "ThemeBackdrop_" + id
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = 0
	bg.z_as_relative = false
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return bg


func _rebuild(id: String, _animate: bool) -> void:
	if _darken:
		_darken.color.a = 0.0

	var bg := _make_bg(id)
	_root.add_child(bg)
	_make_mouse_ignore(bg)

	var old := _current
	_current = bg
	_current_id = id

	if is_instance_valid(old):
		old.queue_free()


func _make_mouse_ignore(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in node.get_children():
		_make_mouse_ignore(c)
