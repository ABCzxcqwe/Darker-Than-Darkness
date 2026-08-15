extends Node

const BASE_CIRCLE_TEXTURE_SIZE := 256
const BASE_CIRCLE_RADIUS := BASE_CIRCLE_TEXTURE_SIZE / 2.0

const BASE_CONE_TEXTURE_SIZE := 512
const BASE_CONE_RADIUS := BASE_CONE_TEXTURE_SIZE / 2.0

const WALL_COLLISION_MASK := 1
const FADE_SPEED := 4.0

var _hud: CanvasLayer = null

func _ready() -> void:
	_hud = get_tree().get_first_node_in_group("game_hud")
	var player = get_parent()
	if not player or not player.is_multiplayer_authority():
		return
	_setup_vision_lights(player)

func _setup_vision_lights(player: Node2D) -> void:
	var data = player.character_data
	if not data:
		return
	$"../VisionCircle".texture = _create_circle_light_texture(BASE_CIRCLE_TEXTURE_SIZE)
	$"../VisionCone".texture = _create_cone_light_texture(BASE_CONE_TEXTURE_SIZE, data.vision_cone_angle * 0.5)
	$"../VisionCircle".texture_scale = data.vision_circle_radius / BASE_CIRCLE_RADIUS
	$"../VisionCone".texture_scale = data.vision_cone_range / BASE_CONE_RADIUS
	$"../VisionCircle".blend_mode = Light2D.BLEND_MODE_MIX
	$"../VisionCone".blend_mode = Light2D.BLEND_MODE_MIX

func _process(_delta: float) -> void:
	var player = get_parent()
	if not player or not player.is_multiplayer_authority():
		return
	if player.interaction.is_spectator:
		$"../VisionCircle".visible = false
		$"../VisionCone".visible = false
		return
	$"../VisionCircle".visible = true
	$"../VisionCone".visible = true

	var data = player.character_data
	if not data:
		return

	_apply_vision_scale(player, data)

	var input_component = player.get("input_component")
	var facing: Vector2
	if input_component:
		facing = input_component.get_aim_direction(player.global_position)
	else:
		facing = (player.get_global_mouse_position() - player.global_position).normalized()
	if facing.length() < 0.001:
		facing = Vector2.RIGHT

	$"../VisionCone".rotation = facing.angle()

	_update_player_visibility(player, data, facing)


func _apply_vision_scale(player: Node2D, data: CharacterData) -> void:
	if Time.get_ticks_msec() >= player._vision_scale_until:
		player._vision_scale = 1.0
	var scale = player._vision_scale
	$"../VisionCircle".texture_scale = (data.vision_circle_radius / BASE_CIRCLE_RADIUS) * scale
	$"../VisionCone".texture_scale = (data.vision_cone_range / BASE_CONE_RADIUS) * scale

func _update_player_visibility(player: Node2D, data: CharacterData, facing_dir: Vector2) -> void:
	# El foco de luz (VisionCircle/Cone) y la distancia de detección comparten el mismo
	# factor de visión: los jugadores desaparecen justo al salir de la luz reducida.
	var circle_radius = data.vision_circle_radius * player._vision_scale
	var cone_angle = data.vision_cone_angle
	var cone_range = data.vision_cone_range * player._vision_scale

	for other in get_tree().get_nodes_in_group("players"):
		if other == player:
			continue
		if other.health_state == "dead":
			continue
		if not other.animated_sprite:
			continue

		# Invisible: nunca se revela por luz ni por distancia.
		if other.active_effects.has("invisibility"):
			other.animated_sprite.self_modulate.a = 0.0
			other.animated_sprite.visible = false
			if other.has_node("NameTag"):
				other.name_tag.visible = false
			continue

		var other_pos = other.global_position
		var dist = player.global_position.distance_to(other_pos)
		var in_vision = false

		if dist <= circle_radius and _has_line_of_sight(player, other):
			in_vision = true
		elif dist <= cone_range:
			var dir_to = (other_pos - player.global_position).normalized()
			var angle = rad_to_deg(acos(clamp(facing_dir.dot(dir_to), -1.0, 1.0)))
			if angle <= cone_angle * 0.5 and _has_line_of_sight(player, other):
				in_vision = true

		var target_alpha = 1.0 if in_vision else 0.0
		var current_alpha = other.animated_sprite.self_modulate.a
		var new_alpha = move_toward(current_alpha, target_alpha, FADE_SPEED * get_process_delta_time())
		other.animated_sprite.self_modulate.a = new_alpha
		other.animated_sprite.visible = new_alpha > 0.01

		if other.has_node("NameTag"):
			other.name_tag.visible = in_vision

func _has_line_of_sight(from_node: Node2D, to_node: Node2D) -> bool:
	var space_state = get_parent().get_world_2d().direct_space_state

	var from_data: CharacterData = from_node.character_data
	var to_data: CharacterData = to_node.character_data

	var from_center = from_node.global_position + _get_shape_center(from_data)
	var to_center = to_node.global_position + _get_shape_center(to_data)

	var direction = to_center - from_center
	var distance = direction.length()
	if distance < 0.001:
		return true
	direction = direction / distance

	var from_radius = _get_shape_radius(from_data, direction)
	var to_radius = _get_shape_radius(to_data, -direction)

	const EXTRA_MARGIN := 4.0

	var adjusted_from = from_center + direction * (from_radius + EXTRA_MARGIN)
	var adjusted_to = to_center - direction * (to_radius + EXTRA_MARGIN)

	if (adjusted_to - adjusted_from).length() <= EXTRA_MARGIN:
		return true

	var query = PhysicsRayQueryParameters2D.create(adjusted_from, adjusted_to)
	query.collision_mask = WALL_COLLISION_MASK
	var result = space_state.intersect_ray(query)
	return result.is_empty()


func _get_shape_center(data: CharacterData) -> Vector2:
	if not data:
		return Vector2.ZERO
	return Vector2(data.position_x, data.position_y)


func _get_shape_radius(data: CharacterData, dir: Vector2) -> float:
	if not data:
		return 8.0
	var half = Vector2(data.size_x, data.size_y) * 0.5
	var tx = INF if dir.x == 0 else half.x / abs(dir.x)
	var ty = INF if dir.y == 0 else half.y / abs(dir.y)
	return min(tx, ty)

func _create_circle_light_texture(size: int = 256) -> GradientTexture2D:
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex = GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = size
	tex.height = size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex

func _create_cone_light_texture(size: int = 512, half_angle_deg: float = 45.0) -> ImageTexture:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size / 2.0, size / 2.0)
	var max_dist = size / 2.0
	var half_angle_rad = deg_to_rad(half_angle_deg)

	for y in range(size):
		for x in range(size):
			var point = Vector2(x, y)
			var offset = point - center
			var dist = offset.length()
			if dist > max_dist:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
				continue
			var angle = abs(offset.angle())
			if angle > half_angle_rad:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
				continue
			var dist_fade = 1.0 - clamp(dist / max_dist, 0.0, 1.0)
			var angle_fade = 1.0 - smoothstep(half_angle_rad * 0.8, half_angle_rad, angle)
			img.set_pixel(x, y, Color(1, 1, 1, dist_fade * angle_fade))

	return ImageTexture.create_from_image(img)
