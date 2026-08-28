extends Control
## Clase base para menús: navegación por `menu_*` (W/S/A/D + flechas + DPAD +
## stick izq + A/B) con bucle de foco, sonidos y helpers de Layout.
## Subclases: construyen su UI y llaman `_setup_focus(items)`.

## Ruta por defecto al volver de una sub-sección de Opciones.
const SETTINGS_HUB_PATH := "res://ui/Old/scenes/Settings.tscn"

var _focus_items: Array[Control] = []
var _focus_idx := 0

## Cuando false, este menú ignora el input (p. ej. menú de pausa cerrado
## o una sub-sección de Opciones tapada por el hub).
var _menu_enabled := true

## Throttle para evitar repetición mientras se mantiene el stick/tecla.
var _nav_last := {}

const NAV_REPEAT_MS := 220


func _input(event: InputEvent) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	if not _menu_enabled:
		return
	if _focused_editable_text(event):
		return
	if _handle_menu_action(event):
		vp.set_input_as_handled()


# ── API para subclases ────────────────────────────────────────────────

## Aplica estilo de foco, conecta focus_entered y fija el foco inicial.
func _setup_focus(items: Array[Control], initial := 0) -> void:
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color(0.114, 0.114, 0.114, 1)
	focus_style.border_color = Color.WHITE
	focus_style.border_width_left = 3
	focus_style.border_width_top = 3
	focus_style.border_width_right = 3
	focus_style.border_width_bottom = 3
	focus_style.set_corner_radius_all(3)
	focus_style.set_expand_margin_all(5)
	_focus_items = items
	for i in _focus_items.size():
		var callable := _update_focus.bind(i)
		if _focus_items[i].focus_entered.is_connected(callable):
			_focus_items[i].focus_entered.disconnect(callable)
		_focus_items[i].focus_entered.connect(callable)
		_focus_items[i].add_theme_stylebox_override("focus", focus_style)
	set_focus_index(initial)


func set_focus_index(i: int) -> void:
	if _focus_items.is_empty():
		return
	_focus_idx = clampi(i, 0, _focus_items.size() - 1)
	if is_instance_valid(_focus_items[_focus_idx]):
		_focus_items[_focus_idx].grab_focus()


func set_menu_enabled(v: bool) -> void:
	_menu_enabled = v


func restore_focus() -> void:
	set_focus_index(_focus_idx)


## Hook de cancelación. Devuelve true si el menú lo manejó.
func _on_menu_cancel() -> bool:
	return false


## Aceptar sobre un LineEdit editable: fija el texto (deja de tipear).
## Aceptar sobre un Button: dispara su señal pressed.
func _accept_action() -> bool:
	var cur := _focused()
	if cur == null:
		return false
	if cur is Button or cur is BaseButton:
		cur.emit_signal("pressed")
		return true
	if cur is LineEdit or cur is TextEdit:
		cur.editable = not cur.editable
		return true
	if cur is CheckBox:
		cur.button_pressed = not cur.button_pressed
		return true
	return false


# ── Internos ──────────────────────────────────────────────────────────

func _update_focus(i: int) -> void:
	_focus_idx = i


func _focused() -> Control:
	if _focus_items.is_empty():
		return null
	if _focus_idx < 0 or _focus_idx >= _focus_items.size():
		return null
	return _focus_items[_focus_idx]


## Si el foco está en un campo de texto editable, dejamos pasar la tecla
## (para que pueda tipear) salvo que sea una acción de navegación explícita.
func _focused_editable_text(event: InputEvent) -> bool:
	var cur := _focused()
	if cur is LineEdit or cur is TextEdit:
		if cur.editable and (event is InputEventKey or event is InputEventScreenTouch):
			if event is InputEventKey and (event.is_action_pressed("menu_cancel") \
					or event.is_action_pressed("menu_accept")):
				return false
			return true
	return false


func _handle_menu_action(event: InputEvent) -> bool:
	if event.is_action_pressed("menu_up"):
		if not _nav_throttle("up"):
			return false
		return _move_focus(-1)
	if event.is_action_pressed("menu_down"):
		if not _nav_throttle("down"):
			return false
		return _move_focus(1)
	if event.is_action_pressed("menu_left"):
		if not _nav_throttle("left"):
			return false
		return _nav_horizontal(-1)
	if event.is_action_pressed("menu_right"):
		if not _nav_throttle("right"):
			return false
		return _nav_horizontal(1)
	if event.is_action_pressed("menu_accept"):
		if not _nav_throttle("accept"):
			return false
		return _accept_action()
	if event.is_action_pressed("menu_cancel"):
		if not _nav_throttle("cancel"):
			return false
		return _on_menu_cancel()
	return false


func _nav_throttle(key: String) -> bool:
	var now := Time.get_ticks_msec()
	if _nav_last.has(key) and now - _nav_last[key] < NAV_REPEAT_MS:
		return false
	_nav_last[key] = now
	return true


func _move_focus(dir: int) -> bool:
	var new_idx := _focus_idx + dir
	if new_idx < 0 or new_idx >= _focus_items.size():
		return false
	_focus_idx = new_idx
	_focus_items[new_idx].grab_focus()
	AudioManager.play_sfx_ui(SfxId.MENU_MOVE)
	return true


## Izquierda/derecha: ajusta el control de valor enfocado (slider, opción, checkbox).
func _nav_horizontal(dir: int) -> bool:
	var cur := _focused()
	if cur == null:
		return false
	if cur is HSlider:
		var slider: HSlider = cur
		slider.value = clampf(slider.value + dir * slider.step, slider.min_value, slider.max_value)
		return true
	if cur is OptionButton:
		var opt: OptionButton = cur
		var new_sel := clampi(opt.selected + dir, 0, opt.item_count - 1)
		if new_sel != opt.selected:
			opt.select(new_sel)
			opt.item_selected.emit(new_sel)
		return true
	if cur is CheckBox:
		cur.button_pressed = not cur.button_pressed
		return true
	return false


## Helper de back para sub-secciones: cambia a una escena de menú.
func _go_back_to(path: String) -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	call_deferred("_change_scene", path)


## Helper estándar: volver al hub de Opciones.
func _back_to_settings_hub() -> void:
	_go_back_to(SETTINGS_HUB_PATH)


func _change_scene(path: String) -> void:
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file(path)
