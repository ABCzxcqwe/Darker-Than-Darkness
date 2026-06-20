extends AbilityBase

const DIAMOND_COUNT: int = 10
const AOE_RADIUS: float = 1000.0
const DIAMOND_SPEED: float = 100.0
const DIAMOND_LIFETIME: float = 2.0
const SPAWN_INTERVAL: float = 0.1


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	var tp_svc = GameServiceLocator.get_service("TPService")
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			return

	var proj_dir: Vector2 = direction.normalized()
	if proj_dir == Vector2.ZERO:
		proj_dir = Vector2.RIGHT if player_node.facing_right else Vector2.LEFT

	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, slot_index, player_node.facing_right)

	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	var _anim_dur: float = 0.3
	if sprite and sprite.sprite_frames and data.action_animation != "" and sprite.sprite_frames.has_animation(data.action_animation):
		_anim_dur = sprite.sprite_frames.get_frame_count(data.action_animation) / sprite.sprite_frames.get_animation_speed(data.action_animation)

	var target_range: float = data.range_ if data.range_ > 0.0 else 500.0
	var target_center: Vector2 = player_node.global_position + proj_dir * target_range
	var spawn_altitude = DIAMOND_SPEED * DIAMOND_LIFETIME * 0.5

	var hs = GameServiceLocator.get_service("HitboxService")
	var cmbt = GameServiceLocator.get_service("CombatMediator")
	var pn := player_node
	var cid := caster_id
	var d := data

	for i in range(DIAMOND_COUNT):
		pn.get_tree().create_timer(i * SPAWN_INTERVAL).timeout.connect(
			func():
				_spawn_diamond(pn, cid, d, hs, cmbt, target_center, spawn_altitude)
		)

	var cd = GameServiceLocator.get_service("CooldownService")
	if cd:
		if cd.has_method("release_lock"):
			cd.release_lock(caster_id, slot_index)
		cd.start(caster_id, slot_index, data.cooldown)

	print("[DiamondRain] Invocada | peer: ", caster_id, " | centro: ", target_center)


func _spawn_diamond(pn: Node, cid: int, d: AbilityData, hs: Node, cmbt: Node, target_center: Vector2, altitude: float) -> void:
	if not is_instance_valid(pn) or not hs:
		return

	var offset_x = randf_range(-AOE_RADIUS, AOE_RADIUS)
	var offset_y = randf_range(-AOE_RADIUS, AOE_RADIUS)
	var spawn_pos = target_center + Vector2(offset_x, offset_y - altitude)

	var config = {
		"attacker_id": cid,
		"attacker_node": pn,
		"type": "projectile",
		"aim_mode": "fixed",
		"direction": Vector2.DOWN,
		"shape_scene": d.ability_scene,
		"damage": d.base_damage,
		"attack_type": d.attack_type,
		"hit_limit": 1,
		"team_filter": "enemy",
		"lifetime": DIAMOND_LIFETIME,
		"speed": DIAMOND_SPEED,
		"offset": 0.0,
		"impact_lifetime": 0.3,
		"on_hit": func(target_node: Node) -> void:
			if is_instance_valid(target_node) and cmbt:
				cmbt.apply_damage(pn, target_node, d.base_damage, d.attack_type)
	}

	var hitbox = hs.create(config)
	if hitbox:
		hitbox.global_position = spawn_pos
