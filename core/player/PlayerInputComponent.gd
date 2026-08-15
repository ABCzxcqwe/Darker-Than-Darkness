class_name PlayerInputComponent
extends Node

signal device_changed(device: int)

enum InputDevice { MOUSE, GAMEPAD, TOUCH }

const AIM_PEEK_RANGE: float = 120.0

var player: CharacterBody2D = null

## El dispositivo activo lo gestiona InputService (fuente única global).
## Este getter expone el valor y setter reenvía al servicio para compatibilidad.
var current_device: int:
	get:
		return InputService.current_device
	set(value):
		InputService.current_device = value

var _last_aim_dir: Vector2 = Vector2.RIGHT
var _virtual_aim_dir: Vector2 = Vector2.ZERO
var _virtual_aim_active: bool = false


func initialize(body: CharacterBody2D) -> void:
	player = body


func _ready() -> void:
	InputService.device_changed.connect(_forward_device_changed)


func _forward_device_changed(device: int) -> void:
	device_changed.emit(device)


func _input(event: InputEvent) -> void:
	if player and not player.is_multiplayer_authority():
		return
	# La detección de dispositivo la hace InputService global.


func get_move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## Devuelve la dirección de apuntado según el dispositivo activo.
## - Mouse: dirección hacia el cursor.
## - Mando: dirección del stick derecho (acciones aim_*).
## - Táctil: última dirección alimentada por la API virtual.
func get_aim_direction(from_global_pos: Vector2) -> Vector2:
	var dir: Vector2

	match current_device:
		InputDevice.GAMEPAD:
			dir = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
			dir = _sanitize_dir(dir)
			if dir != Vector2.ZERO:
				_last_aim_dir = dir
			else:
				dir = _last_aim_dir
		InputDevice.TOUCH:
			dir = _virtual_aim_dir
			if dir != Vector2.ZERO:
				_last_aim_dir = dir
		_:
			dir = player.get_global_mouse_position() - from_global_pos
			dir = _sanitize_dir(dir)
			if dir != Vector2.ZERO:
				_last_aim_dir = dir

	return dir


## Devuelve un punto global (mundo) usado para juguetear la cámara/retícula.
## - Mouse: la posición real del cursor.
## - Mando/táctil: from + dir * range
func get_aim_position(from_global_pos: Vector2, range_amount: float = AIM_PEEK_RANGE) -> Vector2:
	match current_device:
		InputDevice.MOUSE:
			return player.get_global_mouse_position()
		_:
			return from_global_pos + _last_aim_dir.normalized() * range_amount


## Api para futura UI táctil: el joystick virtual alimenta la dirección de apuntado.
func set_virtual_aim(dir: Vector2) -> void:
	_virtual_aim_dir = dir
	_virtual_aim_active = dir != Vector2.ZERO
	current_device = InputDevice.TOUCH


func clear_virtual_aim() -> void:
	_virtual_aim_dir = Vector2.ZERO
	_virtual_aim_active = false


func is_virtual_aim_active() -> bool:
	return _virtual_aim_active


func get_last_aim_dir() -> Vector2:
	return _last_aim_dir


## Resuelve qué slot de emote se seleccionó con el evento.
## Teclado: teclas 1-4. Mando: DPAD (arriba, derecha, abajo, izquierda).
## Devuelve -1 si el evento no selecciona ningún emote.
func resolve_emote_slot(event: InputEvent) -> int:
	if event is InputEventJoypadButton and event.pressed and not event.echo:
		match event.button_index:
			JOY_BUTTON_DPAD_UP: return 0
			JOY_BUTTON_DPAD_RIGHT: return 1
			JOY_BUTTON_DPAD_DOWN: return 2
			JOY_BUTTON_DPAD_LEFT: return 3
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: return 0
			KEY_2: return 1
			KEY_3: return 2
			KEY_4: return 3
	return -1


## Devuelve la etiqueta humanizada de una acción según el dispositivo activo.
## Ej.: "E", "A", "M1", "TOQUE". Delega en InputService (fuente única).
func get_action_label(action: String) -> String:
	return InputService.get_action_label(action, current_device)


## Etiqueta del slot de emote según el dispositivo activo.
func get_emote_label(slot: int) -> String:
	return InputService.get_emote_label(slot, current_device)


func _sanitize_dir(dir: Vector2) -> Vector2:
	var deadzone := InputService.stick_deadzone
	if dir.length_squared() < deadzone * deadzone:
		return Vector2.ZERO
	return dir.normalized()