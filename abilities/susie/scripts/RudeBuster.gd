extends AbilityBase

const PROJECTILE_SPEED: float = 1000.0

const PROJECTILE_LIFETIME: float = 2.0

const IMPACT_LIFETIME: float = 0.3


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[RudeBuster] player_node inválido.")
		return

	var hs = GameServiceLocator.get_service("HitboxService")
	if not hs:
		push_error("[RudeBuster] HitboxService no disponible.")
		return

	var tp_svc = GameServiceLocator.get_service("TPService")
	var cd = GameServiceLocator.get_service("CooldownService")

	var attacker_id: int = player_node.get_multiplayer_authority()
	var dmg: int         = int(data.base_damage * data.evo_damage_multiplier)
	var atk_type: String = data.attack_type
	var stun_dur: float  = data.stun_duration + data.evo_status_duration_bonus
	var tp_reward: float = data.tp_reward

	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(attacker_id, data.tp_cost):
			push_warning("[RudeBuster] consume_tp falló inesperadamente para peer ", attacker_id)
			return

	var hit_limit: int = 1

	var proj_dir: Vector2 = direction.normalized()
	if proj_dir == Vector2.ZERO:
		proj_dir = Vector2.RIGHT if player_node.facing_right else Vector2.LEFT

	var facing_right: bool = proj_dir.x >= 0.0
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
		"type"          : "projectile",
		"aim_mode"      : "fixed",
		"direction"     : proj_dir,
		"shape_scene"   : data.ability_scene,
		"damage"        : dmg,
		"attack_type"   : atk_type,
		"team_filter"   : "enemy",
		"hit_limit"     : hit_limit,
		"lifetime"      : PROJECTILE_LIFETIME,
		"speed"         : PROJECTILE_SPEED,
		"offset"        : 0.0,
		"impact_lifetime": IMPACT_LIFETIME,

		"on_hit": func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return

			if dmg > 0:
				var combat = GameServiceLocator.get_service("CombatMediator")
				if combat:
					combat.apply_damage(player_node, target_node, dmg, atk_type)

			if target_node.is_in_group("killer"):
				var combat = GameServiceLocator.get_service("CombatMediator")
				if combat and stun_dur > 0.0:
					combat.apply_stun(target_node, stun_dur)
				if tp_reward > 0.0 and tp_svc:
					tp_svc.add_tp_custom(attacker_id, tp_reward)

			if cd and cd.has_method("release_lock"):
				cd.release_lock(attacker_id, slot_index)
			if cd:
				cd.start(attacker_id, slot_index, data.cooldown),

		"on_end": func(hit_count: int) -> void:
			if hit_count == 0:
				if cd and cd.has_method("release_lock"):
					cd.release_lock(attacker_id, slot_index)
				if cd:
					var fail_cd: float = data.cooldown_fail if data.cooldown_fail > 0.0 else data.cooldown
					cd.start(attacker_id, slot_index, fail_cd)

			print("[RudeBuster] Proyectil expiró | golpes: ", hit_count)
	})

	print("[RudeBuster] Activado | peer: ", attacker_id,
		  " | dir: ", proj_dir,
		  " | dmg: ", dmg,
		  " | stun: ", stun_dur, "s",
		  " | tp_reward: ", tp_reward)


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return PROJECTILE_LIFETIME
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return PROJECTILE_LIFETIME
	if not sprite.sprite_frames.has_animation(anim_name):
		return PROJECTILE_LIFETIME
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return PROJECTILE_LIFETIME
	return frame_count / fps
