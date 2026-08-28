extends "res://ui/Old/scripts/settings_section.gd"
## Sub-sección Controles: rebinding por dispositivo (Teclado/Mando),
## captura de teclas, reset y deadzone de sticks.
## Escena propia: ui/MainMenu/scenes/SettingsControls.tscn

const DEVICE_MOUSE := InputService.InputDevice.MOUSE
const DEVICE_GAMEPAD := InputService.InputDevice.GAMEPAD

const ACTION_NAMES := {
	"move_up": "Mover arriba",
	"move_down": "Mover abajo",
	"move_left": "Mover izquierda",
	"move_right": "Mover derecha",
	"ability_0": "Ataque básico",
	"ability_1": "Habilidad 1",
	"ability_2": "Habilidad 2",
	"ability_3": "Habilidad 3",
	"ability_4": "Habilidad 4",
	"interact": "Interactuar",
	"run": "Correr",
	"emote_toggle": "Abrir emotes",
	"confirm": "Confirmar (disparo)",
}

@onready var _deadzone_slider: HSlider = $VBox/DeadzoneRow/DeadzoneSlider
@onready var _tab_key_label: Label = $VBox/Tabs/TabKeyLabel
@onready var _tab_pad_label: Label = $VBox/Tabs/TabPadLabel
@onready var _rows_box: VBoxContainer = $VBox/RowsBox
@onready var _status_label: Label = $VBox/StatusLabel
@onready var _reset_all_btn: Button = $VBox/ActionsRow/ResetAllButton
@onready var _back_btn: Button = $VBox/ActionsRow/BackButton

var _tab := DEVICE_MOUSE
var _capturing_action := ""
var _capturing := false
var _row_buttons: Array[Button] = []
var _row_actions: Array[String] = []
var _restore_focus_action := ""


func _ready() -> void:
	_deadzone_slider.value = InputService.stick_deadzone
	_deadzone_slider.value_changed.connect(func(v): InputService.set_stick_deadzone(v))

	_tab_key_label.gui_input.connect(_on_tab_input.bind(true))
	_tab_pad_label.gui_input.connect(_on_tab_input.bind(false))

	_reset_all_btn.pressed.connect(_on_reset_all_pressed)
	_back_btn.pressed.connect(_go_back)

	_update_tab_labels()
	_refresh_rows()


func _on_tab_input(event: InputEvent, is_key: bool) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_tab(DEVICE_MOUSE if is_key else DEVICE_GAMEPAD)
		_mark_input_handled()


func _set_tab(tab: int) -> void:
	if _tab == tab or _capturing:
		return
	_tab = tab
	AudioManager.play_sfx_ui(SfxId.MENU_MOVE)
	_update_tab_labels()
	_refresh_rows()


func _update_tab_labels() -> void:
	_tab_key_label.modulate = Color.WHITE if _tab == DEVICE_MOUSE else Color(0.6, 0.6, 0.6, 1)
	_tab_pad_label.modulate = Color.WHITE if _tab == DEVICE_GAMEPAD else Color(0.6, 0.6, 0.6, 1)


func _rebindable_actions() -> Array[String]:
	var src: Array = InputService.REBINDABLE_KEYBOARD if _tab == DEVICE_MOUSE else InputService.REBINDABLE_GAMEPAD
	var list: Array[String] = []
	for a in src:
		list.append(a)
	return list


func _refresh_rows() -> void:
	for child in _rows_box.get_children():
		child.queue_free()
	_row_buttons.clear()
	_row_actions = _rebindable_actions()

	for action in _row_actions:
		var row := Button.new()
		row.custom_minimum_size = Vector2(400, 34)
		var name_text: String = ACTION_NAMES.get(action, action)
		var label: String = InputService.get_action_label(action, _tab)
		row.text = "%s   [%s]" % [name_text, label]
		row.pressed.connect(_on_row_pressed.bind(action))
		_rows_box.add_child(row)
		_row_buttons.append(row)

	# Reasignar foco (conserva índice aproximado)
	var focus_items: Array[Control] = []
	focus_items.append(_deadzone_slider)
	for row in _row_buttons:
		focus_items.append(row)
	focus_items.append(_reset_all_btn)
	focus_items.append(_back_btn)
	var restore_idx := -1
	if _restore_focus_action != "":
		restore_idx = _row_actions.find(_restore_focus_action)
		_restore_focus_action = ""
	if restore_idx >= 0:
		set_focus_index(restore_idx + 1)
	else:
		set_focus_index(_focus_idx)
	_setup_focus(focus_items)
	if _focus_idx > 0 and _focus_idx < focus_items.size():
		set_focus_index(_focus_idx)


func _on_row_pressed(action: String) -> void:
	if _capturing:
		return
	_start_capture(action)


func _start_capture(action: String) -> void:
	_capturing = true
	_capturing_action = action
	_status_label.text = "Presiona una tecla / botón… (Esc cancelar)"
	_mark_input_handled()


func _stop_capture() -> void:
	_capturing = false
	_capturing_action = ""
	_status_label.text = "◄ ► cambiar pestaña · Aceptar rebindear · Esc cancelar"


func _input(event: InputEvent) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	if _capturing:
		if event.is_action_pressed("menu_cancel"):
			_stop_capture()
			vp.set_input_as_handled()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			_apply_captured(event)
			return
		if event is InputEventMouseButton and event.pressed:
			_apply_captured(event)
			return
		if event is InputEventJoypadButton and event.pressed:
			_apply_captured(event)
			return
		return
	super._input(event)


func _apply_captured(event: InputEvent) -> void:
	var device := _device_of(event)
	if device == -1:
		_mark_input_handled()
		return
	if _tab == DEVICE_MOUSE and device != DEVICE_MOUSE:
		_mark_input_handled()
		return
	if _tab == DEVICE_GAMEPAD and device != DEVICE_GAMEPAD:
		_mark_input_handled()
		return
	var result := InputService.rebind(_capturing_action, event)
	match result:
		InputService.RebindResult.OK:
			_status_label.text = "Rebind hecho para %s." % ACTION_NAMES.get(_capturing_action, _capturing_action)
			_restore_focus_action = _capturing_action
			_stop_capture()
			_refresh_rows()
		InputService.RebindResult.CONFLICT:
			var conflict := InputService.get_conflicting_action(_capturing_action, event)
			var conflict_name: String = ACTION_NAMES.get(conflict, conflict)
			_status_label.text = "Conflicto con \"%s\". Presiona otra tecla/botón." % conflict_name
		_:
			_status_label.text = "Acción no soportada para este dispositivo."
	_mark_input_handled()


func _device_of(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouseButton:
		return DEVICE_MOUSE
	if event is InputEventJoypadButton:
		return DEVICE_GAMEPAD
	return -1


func _on_reset_all_pressed() -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	InputService.reset_all()
	_refresh_rows()
	_status_label.text = "Controles restablecidos a los predeterminados."


func _mark_input_handled() -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()


# ── Navegación: izquierda/derecha cambia de pestaña (salvo en el slider) ──
func _nav_horizontal(dir: int) -> bool:
	var cur := _focused()
	if cur == _deadzone_slider:
		return super._nav_horizontal(dir)
	_set_tab(DEVICE_MOUSE if _tab == DEVICE_GAMEPAD else DEVICE_GAMEPAD)
	return true
