extends AbilityBase

const HITBOX_LIFETIME: float = 0.3


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[AxeSlash] player_node inválido.")
		return

	var hs = GameServiceLocator.get_service("HitboxService")
	if not hs:
		push_error("[AxeSlash] HitboxService no disponible.")
		return

	var attacker_id: int = player_node.get_multiplayer_authority()
	var dmg: int         = data.base_damage
	var atk_type: String = data.attack_type
	var hit_range: float = data.range_
	var stun_dur: float  = data.stun_duration
	var tp_reward: float = data.tp_reward

	var tp_svc = GameServiceLocator.get_service("TPService")
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(attacker_id, data.tp_cost):
			return

	var cd_svc = GameServiceLocator.get_service("CooldownService")
	var facing_right: bool = direction.x >= 0.0
	var slash_dir: Vector2 = Vector2.RIGHT if facing_right else Vector2.LEFT

	var combat = GameServiceLocator.get_service("CombatMediator")
	if combat:
		combat.apply_root(player_node, HITBOX_LIFETIME)

	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, slot_index, facing_right)

	var anim_dur := _get_anim_duration(player_node, data.action_animation)
	if is_instance_valid(player_node) and player_node.multiplayer.is_server():
		player_node.get_tree().create_timer(anim_dur).timeout.connect(
			func() -> void:
				if is_instance_valid(player_node):
					player_node.rpc("_sync_cancel_ability")
		)

	hs.create({
		"attacker_id"   : attacker_id,
		"attacker_node" : player_node,
		"type"          : "slash",
		"aim_mode"      : "fixed",
		"direction"     : slash_dir,
		"shape_scene"   : data.ability_scene,
		"damage"        : dmg,
		"attack_type"   : atk_type,
		"team_filter"   : "enemy",
		"hit_limit"     : 1,
		"lifetime"      : HITBOX_LIFETIME,
		"offset"        : hit_range,

		"on_hit": func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return
			if dmg > 0 and combat:
				combat.apply_damage(player_node, target_node, dmg, atk_type)
			if target_node.is_in_group("killer"):
				if combat and stun_dur > 0.0:
					combat.apply_stun(target_node, stun_dur)
				if tp_reward > 0.0 and tp_svc:
					tp_svc.add_tp_custom(attacker_id, tp_reward)

			if cd_svc and cd_svc.has_method("release_lock"):
				cd_svc.release_lock(attacker_id, slot_index)
			if cd_svc:
				cd_svc.start(attacker_id, slot_index, data.cooldown),

		"on_end": func(_hit_count: int) -> void:
			var c = GameServiceLocator.get_service("CombatMediator")
			if c and is_instance_valid(player_node):
				c.remove_root(player_node)

			if _hit_count == 0 and cd_svc:
				if cd_svc.has_method("release_lock"):
					cd_svc.release_lock(attacker_id, slot_index)
				var fail_cd: float = data.cooldown_fail if data.cooldown_fail > 0.0 else data.cooldown
				cd_svc.start(attacker_id, slot_index, fail_cd)
	})

	print("[AxeSlash] Activado | peer: ", attacker_id,
		  " | dir: ", slash_dir, " | stun: ", stun_dur, "s")


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return HITBOX_LIFETIME
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return HITBOX_LIFETIME
	if not sprite.sprite_frames.has_animation(anim_name):
		return HITBOX_LIFETIME
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return HITBOX_LIFETIME
	return frame_count / fps
