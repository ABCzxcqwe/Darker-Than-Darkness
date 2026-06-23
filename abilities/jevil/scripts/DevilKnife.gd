extends AbilityBase


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	var tp_svc = GameServiceLocator.get_service("TPService")
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			return

	var combat = GameServiceLocator.get_service("CombatMediator")
	if combat:
		combat.apply_root(player_node, 2.0)

	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, slot_index, player_node.facing_right)

	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	var anim_dur: float = 0.3
	if sprite and sprite.sprite_frames and data.action_animation != "" and sprite.sprite_frames.has_animation(data.action_animation):
		anim_dur = sprite.sprite_frames.get_frame_count(data.action_animation) / sprite.sprite_frames.get_animation_speed(data.action_animation)

	var cd = GameServiceLocator.get_service("CooldownService")
	if cd and cd.has_method("release_lock"):
		cd.release_lock(caster_id, slot_index)

	var pn := player_node
	var d := data
	var cid := caster_id
	var sid := slot_index

	player_node.get_tree().create_timer(anim_dur).timeout.connect(
		func():
			_on_anim_timer(pn, d, cid, sid, direction)
	)


func _on_anim_timer(player_node: Node, data: AbilityData, caster_id: int, slot_index: int, direction: Vector2) -> void:
	if not is_instance_valid(player_node):
		return

	var combat = GameServiceLocator.get_service("CombatMediator")
	if combat:
		combat.remove_root(player_node)

	var proj_dir: Vector2 = direction.normalized()
	if proj_dir == Vector2.ZERO:
		proj_dir = Vector2.RIGHT if player_node.facing_right else Vector2.LEFT

	var hs = GameServiceLocator.get_service("HitboxService")
	if hs:
		hs.create({
			"attacker_id": caster_id,
			"attacker_node": player_node,
			"type": "projectile",
			"aim_mode": "fixed",
			"direction": proj_dir,
			"shape_scene": data.ability_scene,
			"damage": data.base_damage,
			"attack_type": data.attack_type,
			"hit_limit": 0,
			"team_filter": "enemy",
			"detect_walls": true,
			"lifetime": data.projectile_lifetime if data.projectile_lifetime > 0 else 2.0,
			"speed": data.projectile_speed if data.projectile_speed > 0 else 600.0,
			"offset": data.range_,
			"impact_lifetime": 0.3,
			"on_hit": func(target_node: Node) -> void:
				if is_instance_valid(target_node):
					var cmbt = GameServiceLocator.get_service("CombatMediator")
					if cmbt:
						cmbt.apply_damage(player_node, target_node, data.base_damage, data.attack_type)
					if target_node.is_in_group("killer") and data.stun_duration > 0.0:
						var combat_stun = GameServiceLocator.get_service("CombatMediator")
						if combat_stun:
							combat_stun.apply_stun(target_node, data.stun_duration)
		})

	var cd = GameServiceLocator.get_service("CooldownService")
	if cd:
		cd.start(caster_id, slot_index, data.cooldown)

	player_node.rpc("_sync_cancel_ability")

	print("[DevilKnife] Lanzado | peer: ", caster_id, " | dir: ", proj_dir)
