extends AbilityBase

const HITBOX_LIFETIME: float = 0.5

const ANIM_DURATION: float = 0.5


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[SwordSlash] player_node inválido.")
		return

	var combat = GameServiceLocator.get_service("CombatMediator")
	if not combat:
		push_error("[SwordSlash] CombatMediator no disponible.")
		return

	var hs = GameServiceLocator.get_service("HitboxService")
	if not hs:
		push_error("[SwordSlash] HitboxService no disponible.")
		return

	var cd = GameServiceLocator.get_service("CooldownService")
	if not cd:
		push_error("[SwordSlash] CooldownService no disponible.")
		return

	var tp_svc = GameServiceLocator.get_service("TPService")

	var attacker_id: int = player_node.get_multiplayer_authority()
	var dmg: int         = int(data.base_damage * data.evo_damage_multiplier)
	var atk_type: String = data.attack_type
	var hit_range: float = data.range_
	var stun_dur: float  = data.stun_duration + data.evo_status_duration_bonus
	var tp_reward: float = data.tp_reward
	var facing_right     = direction.x >= 0.0
	var slash_dir: Vector2 = Vector2.RIGHT if facing_right else Vector2.LEFT

	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(attacker_id, data.tp_cost):
			push_warning("[SwordSlash] consume_tp falló inesperadamente para peer ", attacker_id)
			return


	combat.apply_root(player_node, ANIM_DURATION)

	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, slot_index, facing_right)

	if is_instance_valid(player_node) and player_node.multiplayer.is_server():
		AudioManager.play_sfx_networked.rpc(17, player_node.global_position.x, player_node.global_position.y)

	var anim_dur := _get_anim_duration(player_node, data.action_animation)
	player_node.get_tree().create_timer(anim_dur).timeout.connect(
		func() -> void:
			if is_instance_valid(player_node):
				player_node.rpc("_sync_cancel_ability")
	)

	var _hit_registered := [false]

	hs.create({
		"attacker_id"   : attacker_id,
		"attacker_node" : player_node,
		"type"          : "slash",
		"aim_mode"      : "fixed",
		"direction"     : slash_dir,
		"shape_scene"   : data.ability_scene,
		"damage"        : 0,
		"attack_type"   : atk_type,
		"team_filter"   : "enemy",
		"hit_limit"     : 1,
		"lifetime"      : HITBOX_LIFETIME,
		"offset"        : hit_range,

		"on_hit": func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return

			_hit_registered[0] = true

			if dmg > 0:
				combat.apply_damage(player_node, target_node, dmg, atk_type)

			if target_node.is_in_group("killer"):
				if stun_dur > 0.0:
					combat.apply_stun(target_node, stun_dur)
				if tp_reward > 0.0 and tp_svc:
					tp_svc.add_tp_custom(attacker_id, tp_reward)

			if cd.has_method("release_lock"):
				cd.release_lock(attacker_id, slot_index)
			cd.start(attacker_id, slot_index, data.cooldown),

		"on_end": func(hit_count: int) -> void:
			if is_instance_valid(player_node):
				combat.remove_root(player_node)

			if hit_count == 0:
				if cd.has_method("release_lock"):
					cd.release_lock(attacker_id, slot_index)
				var fail_cd: float = data.cooldown_fail if data.cooldown_fail > 0.0 else data.cooldown
				cd.start(attacker_id, slot_index, fail_cd)

			print("[SwordSlash] Terminó | golpes: ", hit_count)
	})

	print("[SwordSlash] Activado | peer: ", attacker_id,
		  " | dir: ", slash_dir, " | dmg: ", dmg,
		  " | stun: ", stun_dur, "s | anim: ", data.action_animation)


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return ANIM_DURATION
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return ANIM_DURATION
	if not sprite.sprite_frames.has_animation(anim_name):
		return ANIM_DURATION
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return ANIM_DURATION
	return frame_count / fps
