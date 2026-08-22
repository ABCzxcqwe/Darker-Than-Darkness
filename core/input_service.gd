extends Node

## Servicio global de input (autoload).
## Fuente única de: dispositivo activo (MOUSE/GAMEPAD/TOUCH), etiquetas
## humanizadas de acciones, deadzone de sticks y rebinding persistido en
## la sección [input] de settings.cfg.

signal device_changed(device: int)

enum InputDevice { MOUSE, GAMEPAD, TOUCH }

enum RebindResult { OK, CONFLICT, UNSUPPORTED }

const SETTINGS_SECTION := "input"
const KEYBOARD_KEY := "keyboard"
const GAMEPAD_KEY := "gamepad"
const DEADZONE_KEY := "stick_deadzone"

const DEFAULT_DEADZONE := 0.2

## Acciones rebindeables por clase de dispositivo.
## Los ejes (aim_*, run/move_* del pad, menu_*, spec_*) quedan fuera.
const REBINDABLE_KEYBOARD := [
	"move_up", "move_down", "move_left", "move_right",
	"ability_0", "ability_1", "ability_2", "ability_3", "ability_4",
	"interact", "run", "emote_toggle", "confirm",
]
const REBINDABLE_GAMEPAD := [
	"ability_0", "ability_1", "ability_2", "ability_3", "ability_4",
	"interact", "emote_toggle", "confirm",
]

## Acciones cuyo deadzone del InputMap se mantiene sincronizada con stick_deadzone.
const DEADZONE_ACTIONS := [
	"move_up", "move_down", "move_left", "move_right",
	"aim_up", "aim_down", "aim_left", "aim_right",
	"menu_up", "menu_down", "menu_left", "menu_right",
]

var current_device: int = InputDevice.MOUSE:
	set(value):
		if value != current_device:
			current_device = value
			device_changed.emit(current_device)

var stick_deadzone: float = DEFAULT_DEADZONE

var _keyboard_bindings: Dictionary = {}
var _gamepad_bindings: Dictionary = {}
var _default_events: Dictionary = {}


func _ready() -> void:
	if DisplayServer.is_touchscreen_available():
		current_device = InputDevice.TOUCH
	_snapshot_defaults()
	_load_bindings()
	_apply_bindings()
	_apply_stick_deadzone()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		current_device = InputDevice.GAMEPAD
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		current_device = InputDevice.MOUSE
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		current_device = InputDevice.TOUCH


# ─── Labels ───────────────────────────────────────────────────────────

## Etiqueta humanizada de una acción para un dispositivo dado.
func get_action_label(action: String, device: int = current_device) -> String:
	if device == InputDevice.TOUCH:
		return "TOQUE"
	if not InputMap.has_action(action):
		return "-"
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "-"
	if device == InputDevice.GAMEPAD:
		for e in events:
			if e is InputEventJoypadButton:
				return _joypad_button_label(e.button_index)
		for e in events:
			if e is InputEventJoypadMotion:
				return _joypad_axis_label(e.axis)
		return "-"
	for e in events:
		if e is InputEventKey:
			return OS.get_keycode_string(e.physical_keycode)
	for e in events:
		if e is InputEventMouseButton:
			return "M%d" % e.button_index
	return "-"


## Etiqueta del slot de emote (1-4 en teclado, DPAD en mando).
func get_emote_label(slot: int, device: int = current_device) -> String:
	if device == InputDevice.TOUCH:
		return "TOQUE"
	if device == InputDevice.GAMEPAD:
		match slot:
			0: return "DP-UP"
			1: return "DP-RIGHT"
			2: return "DP-DOWN"
			3: return "DP-LEFT"
	return str(slot + 1)


# ─── Rebinding ────────────────────────────────────────────────────────

func is_rebindable(action: String, device: int) -> bool:
	return action in (REBINDABLE_KEYBOARD if device == InputDevice.MOUSE else REBINDABLE_GAMEPAD)


func rebind(action: String, event: InputEvent) -> int:
	var device := _device_of_event(event)
	if device == -1 or not InputMap.has_action(action):
		return RebindResult.UNSUPPORTED
	if not is_rebindable(action, device):
		return RebindResult.UNSUPPORTED
	var conflict := _find_conflict(action, event, device)
	if conflict != "":
		return RebindResult.CONFLICT
	_apply_binding(action, event, device)
	_save_bindings()
	return RebindResult.OK


func get_conflicting_action(action: String, event: InputEvent) -> String:
	var device := _device_of_event(event)
	if device == -1:
		return ""
	return _find_conflict(action, event, device)


func reset_action(action: String) -> void:
	var had := action in _keyboard_bindings or action in _gamepad_bindings
	if not had:
		return
	_keyboard_bindings.erase(action)
	_gamepad_bindings.erase(action)
	_restore_default_events(action)
	_save_bindings()


func reset_all() -> void:
	var actions := _keyboard_bindings.keys() + _gamepad_bindings.keys()
	_keyboard_bindings.clear()
	_gamepad_bindings.clear()
	for action in actions:
		_restore_default_events(action)
	_save_bindings()


func set_stick_deadzone(value: float) -> void:
	stick_deadzone = clampf(value, 0.05, 1.0)
	_apply_stick_deadzone()
	_save_bindings()


# ─── Internals ────────────────────────────────────────────────────────

func _snapshot_defaults() -> void:
	for action in InputMap.get_actions():
		_default_events[action] = InputMap.action_get_events(action).duplicate()


func _load_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SettingsManager.SETTINGS_PATH) != OK:
		return
	_keyboard_bindings = cfg.get_value(SETTINGS_SECTION, KEYBOARD_KEY, {})
	_gamepad_bindings = cfg.get_value(SETTINGS_SECTION, GAMEPAD_KEY, {})
	stick_deadzone = cfg.get_value(SETTINGS_SECTION, DEADZONE_KEY, DEFAULT_DEADZONE)


func _save_bindings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsManager.SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, KEYBOARD_KEY, _keyboard_bindings)
	cfg.set_value(SETTINGS_SECTION, GAMEPAD_KEY, _gamepad_bindings)
	cfg.set_value(SETTINGS_SECTION, DEADZONE_KEY, stick_deadzone)
	cfg.save(SettingsManager.SETTINGS_PATH)


func _apply_bindings() -> void:
	for action in _keyboard_bindings:
		var event := _decode_event(_keyboard_bindings[action])
		if event and InputMap.has_action(action):
			_erase_device_events(action, InputDevice.MOUSE)
			InputMap.action_add_event(action, event)
	for action in _gamepad_bindings:
		var event := _decode_event(_gamepad_bindings[action])
		if event and InputMap.has_action(action):
			_erase_device_events(action, InputDevice.GAMEPAD)
			InputMap.action_add_event(action, event)


func _erase_device_events(action: String, device: int) -> void:
	for existing in InputMap.action_get_events(action).duplicate():
		if _device_of_event(existing) == device:
			InputMap.action_erase_event(action, existing)


func _apply_binding(action: String, event: InputEvent, device: int) -> void:
	_erase_device_events(action, device)
	InputMap.action_add_event(action, event)
	if device == InputDevice.MOUSE:
		_keyboard_bindings[action] = _encode_event(event)
	else:
		_gamepad_bindings[action] = _encode_event(event)


func _restore_default_events(action: String) -> void:
	var defaults: Array = _default_events.get(action, [])
	for existing in InputMap.action_get_events(action).duplicate():
		InputMap.action_erase_event(action, existing)
	for e in defaults:
		InputMap.action_add_event(action, e)


func _find_conflict(action: String, event: InputEvent, device: int) -> String:
	var new_sig := _event_signature(event)
	var pool: Array = REBINDABLE_KEYBOARD if device == InputDevice.MOUSE else REBINDABLE_GAMEPAD
	for other in pool:
		if other == action:
			continue
		for existing in InputMap.action_get_events(other):
			if _device_of_event(existing) == device and _event_signature(existing) == new_sig:
				return other
	return ""


func _event_signature(event: InputEvent) -> String:
	if event is InputEventKey:
		return "k%d" % event.physical_keycode
	if event is InputEventMouseButton:
		return "m%d" % event.button_index
	if event is InputEventJoypadButton:
		return "b%d" % event.button_index
	return ""


func _device_of_event(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		return InputDevice.MOUSE
	if event is InputEventJoypadButton:
		return InputDevice.GAMEPAD
	return -1


func _encode_event(event: InputEvent) -> String:
	if event is InputEventKey:
		return "key/%d" % event.physical_keycode
	if event is InputEventMouseButton:
		return "mouse/%d" % event.button_index
	if event is InputEventJoypadButton:
		return "button/%d" % event.button_index
	return ""


func _decode_event(data: String) -> InputEvent:
	var parts := data.split("/")
	if parts.size() != 2:
		return null
	match parts[0]:
		"key":
			var ke := InputEventKey.new()
			ke.physical_keycode = int(parts[1]) as Key
			return ke
		"mouse":
			var me := InputEventMouseButton.new()
			me.button_index = int(parts[1]) as MouseButton
			return me
		"button":
			var be := InputEventJoypadButton.new()
			be.button_index = int(parts[1]) as JoyButton
			return be
	return null


func _apply_stick_deadzone() -> void:
	for action in DEADZONE_ACTIONS:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, stick_deadzone)


func _joypad_button_label(button_index: int) -> String:
	match button_index:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "L1"
		JOY_BUTTON_RIGHT_SHOULDER: return "R1"
		JOY_BUTTON_DPAD_UP: return "DP-UP"
		JOY_BUTTON_DPAD_DOWN: return "DP-DOWN"
		JOY_BUTTON_DPAD_LEFT: return "DP-LEFT"
		JOY_BUTTON_DPAD_RIGHT: return "DP-RIGHT"
		JOY_BUTTON_START: return "START"
		JOY_BUTTON_BACK: return "SELECT"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
	return "BTN%d" % button_index


func _joypad_axis_label(axis: int) -> String:
	match axis:
		JOY_AXIS_LEFT_X: return "OVAL-IZQ"
		JOY_AXIS_LEFT_Y: return "OVAL-IZQ"
		JOY_AXIS_RIGHT_X: return "OVAL-DER"
		JOY_AXIS_RIGHT_Y: return "OVAL-DER"
		JOY_AXIS_TRIGGER_LEFT: return "L2"
		JOY_AXIS_TRIGGER_RIGHT: return "R2"
	return "AX%d" % axis
