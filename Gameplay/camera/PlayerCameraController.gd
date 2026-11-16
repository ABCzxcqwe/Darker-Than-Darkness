class_name PlayerCameraController
extends RefCounted
## Lógica visual de cámara del jugador (mouse peek y zoom).
##
## No crea ni posee nodos: CameraRig le pasa el PCam y el target. Se mantiene
## separado para poder testear/ajustar sin tocar el rig.

const PEEK_DISTANCE_SCALE := 500.0
const BLIND_ZOOM_MULTIPLIER := 1.4


static func apply_character(rig: CameraRig, target: Node) -> void:
	if rig == null:
		return
	var data: CharacterData = null
	if target is Player:
		data = (target as Player).character_data

	if data == null:
		rig.set_zoom_profile(
			CameraRig.DEFAULT_ZOOM_BASE,
			CameraRig.DEFAULT_ZOOM_SPRINT,
			CameraRig.DEFAULT_ZOOM_SPEED,
			CameraRig.DEFAULT_SMOOTH_SPEED
		)
		rig.set_peek_profile(
			CameraRig.DEFAULT_PEEK_AMOUNT,
			CameraRig.DEFAULT_PEEK_LIMIT
		)
		return

	rig.set_zoom_profile(
		data.camera_zoom_base,
		data.camera_zoom_sprint,
		data.camera_zoom_speed,
		data.camera_smooth_speed
	)
	rig.set_peek_profile(
		data.camera_mouse_peek_amount,
		data.camera_mouse_peek_limit
	)


static func update(rig: CameraRig, target: Node2D, delta: float) -> void:
	if rig == null or target == null or not is_instance_valid(target):
		return

	rig.set_follow_offset(_calc_peek(rig, target))
	rig.set_zoom(_calc_zoom(rig, target), delta)


static func _calc_peek(rig: CameraRig, target: Node2D) -> Vector2:
	if rig.mode != "play" or rig.peek_limit <= 0.0 or rig.peek_amount <= 0.0:
		return Vector2.ZERO
	if not target is Player:
		return Vector2.ZERO

	var player := target as Player
	var input_component := player.input_component
	if input_component == null:
		return Vector2.ZERO

	var aim_pos: Vector2 = input_component.get_aim_position(player.global_position, rig.peek_limit)
	var delta := aim_pos - player.global_position
	if delta.length_squared() < 0.0001:
		return Vector2.ZERO
	var distance := clampf(delta.length() / PEEK_DISTANCE_SCALE, 0.0, 1.0)
	return delta.normalized() * distance * rig.peek_amount * rig.peek_limit


static func _calc_zoom(rig: CameraRig, target: Node2D) -> float:
	match rig.mode:
		"spectate":
			return rig.spectate_zoom
		"hub":
			return rig.zoom_base
		_:
			pass

	if target is Player:
		var player := target as Player
		if player._vision_scale < 1.0:
			return rig.zoom_base * BLIND_ZOOM_MULTIPLIER
		if player.movement_component and player.movement_component.is_sprinting():
			return rig.zoom_sprint
	return rig.zoom_base
