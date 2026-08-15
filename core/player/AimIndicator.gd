class_name AimIndicator
extends Node2D

const DEFAULT_RANGE: float = 120.0
const COLOR_IDLE: Color = Color(1, 1, 1, 0.85)
const COLOR_AIMING: Color = Color(1, 0.87, 0.0, 0.95)

var _player: Node2D = null
var _is_aiming: bool = false


func _ready() -> void:
	_player = get_parent()
	z_index = 50
	set_process(_player != null and _player.is_multiplayer_authority())


func _process(_delta: float) -> void:
	if not _player or not is_instance_valid(_player):
		visible = false
		return
	if not _player.is_multiplayer_authority():
		visible = false
		return

	# Menú de pausa abierto: ocultar retícula y restaurar el cursor.
	var menu := get_tree().get_first_node_in_group(GroupNames.GAME_MENU)
	if menu and menu.has_method("is_open") and menu.is_open():
		visible = false
		_restore_mouse()
		return

	if _player.health_state != "alive" or _player.interaction.is_spectator:
		visible = false
		_restore_mouse()
		return

	var input_component = _player.get("input_component")
	if not input_component:
		visible = false
		_restore_mouse()
		return

	_is_aiming = _player.get("aiming_slot") >= 0 or _player.active_effects.has("free_look")
	match int(input_component.current_device):
		PlayerInputComponent.InputDevice.MOUSE:
			visible = _is_aiming
			if visible:
				global_position = _player.get_global_mouse_position()
			_set_mouse_hidden(visible)
		PlayerInputComponent.InputDevice.GAMEPAD:
			visible = true
			global_position = input_component.get_aim_position(_player.global_position, DEFAULT_RANGE)
			_restore_mouse()
		PlayerInputComponent.InputDevice.TOUCH:
			visible = input_component.is_virtual_aim_active()
			if visible:
				global_position = input_component.get_aim_position(_player.global_position, DEFAULT_RANGE)
			_restore_mouse()

	queue_redraw()


func _draw() -> void:
	var color := COLOR_AIMING if _is_aiming else COLOR_IDLE
	draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 24, color, 2.0)
	draw_line(Vector2(-14, 0), Vector2(-7, 0), color, 2.0)
	draw_line(Vector2(7, 0), Vector2(14, 0), color, 2.0)
	draw_line(Vector2(0, -14), Vector2(0, -7), color, 2.0)
	draw_line(Vector2(0, 7), Vector2(0, 14), color, 2.0)
	draw_circle(Vector2.ZERO, 1.5, color)


func _restore_mouse() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_mouse_hidden(hidden: bool) -> void:
	var target := Input.MOUSE_MODE_HIDDEN if hidden else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != target:
		Input.mouse_mode = target