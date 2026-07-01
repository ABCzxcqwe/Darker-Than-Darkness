extends Node

var _vision_overlay: ColorRect = null
var _vision_material: ShaderMaterial = null

func _ready() -> void:
	var player = get_parent()
	if not player or not player.is_multiplayer_authority():
		return
	_create_overlay()

func _exit_tree() -> void:
	if _vision_overlay:
		var canvas = _vision_overlay.get_parent()
		if canvas:
			canvas.queue_free()
		_vision_overlay = null
		_vision_material = null

func _create_overlay() -> void:
	if _vision_overlay:
		return
	var existing = get_tree().root.get_node_or_null("VisionOverlayLayer")
	if existing:
		_vision_overlay = existing.get_node("VisionOverlay")
		_vision_material = _vision_overlay.material
		return
	var canvas = CanvasLayer.new()
	canvas.layer = 90
	canvas.name = "VisionOverlayLayer"
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://core/vision_overlay.gdshader")
	var rect = ColorRect.new()
	rect.name = "VisionOverlay"
	rect.material = mat
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(rect)
	get_tree().root.add_child(canvas)
	_vision_overlay = rect
	_vision_material = mat

func _process(_delta: float) -> void:
	var player = get_parent()
	if not player or not player.is_multiplayer_authority():
		return
	if player.is_spectator:
		if _vision_overlay:
			_vision_overlay.visible = false
		return
	if _vision_overlay:
		_vision_overlay.visible = true

	var data = player.character_data
	if not data:
		return

	_update_overlay(player, data)
	_update_player_visibility(player, data)

func _update_overlay(player: Node2D, data: CharacterData) -> void:
	if not _vision_material:
		return
	var camera = get_viewport().get_camera_2d()
	if not camera:
		return
	var transform = camera.get_canvas_transform()
	var player_screen = transform * player.global_position
	var zoom_val = camera.zoom.x
	var mouse_pos = player.get_global_mouse_position()
	var facing = (mouse_pos - player.global_position).normalized()
	if facing.length() < 0.001:
		facing = Vector2.RIGHT

	_vision_material.set_shader_parameter("player_px", player_screen)
	_vision_material.set_shader_parameter("facing_dir", facing)
	_vision_material.set_shader_parameter("radius_px", data.vision_circle_radius * zoom_val)
	_vision_material.set_shader_parameter("cone_range_px", data.vision_cone_range * zoom_val)
	_vision_material.set_shader_parameter("cone_half_angle", deg_to_rad(data.vision_cone_angle * 0.5))

func _update_player_visibility(player: Node2D, data: CharacterData) -> void:
	var circle_radius = data.vision_circle_radius
	var cone_angle = data.vision_cone_angle
	var cone_range = data.vision_cone_range
	var player_pos = player.global_position
	var mouse_pos = player.get_global_mouse_position()
	var facing_dir = (mouse_pos - player_pos).normalized()
	if facing_dir.length() < 0.001:
		facing_dir = Vector2.RIGHT

	for other in get_tree().get_nodes_in_group("players"):
		if other == player:
			continue
		if not other.animated_sprite:
			continue
		var other_pos = other.global_position
		var dist = player_pos.distance_to(other_pos)
		var in_vision = false
		if dist <= circle_radius:
			in_vision = true
		elif dist <= cone_range:
			var dir_to = (other_pos - player_pos).normalized()
			var angle = rad_to_deg(acos(clamp(facing_dir.dot(dir_to), -1.0, 1.0)))
			if angle <= cone_angle * 0.5:
				in_vision = true
		other.animated_sprite.visible = in_vision
		var tag = other.get_node_or_null("NameTag")
		if tag:
			tag.visible = in_vision and dist <= 1200.0 and other.health_state == "alive"
