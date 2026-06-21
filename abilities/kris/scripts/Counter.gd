extends AbilityBase

const COUNTER_WINDOW: float = 3.0
const ANIM_FALLBACK: float = 2.0


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[Counter] player_node inválido.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	var combat = GameServiceLocator.get_service("CombatMediator")
	if not combat:
		push_error("[Counter] CombatMediator no disponible.")
		return

	var hs = GameServiceLocator.get_service("HitboxService")
	if not hs:
		push_error("[Counter] HitboxService no disponible.")
		return

	var cd = GameServiceLocator.get_service("CooldownService")
	if not cd:
		push_error("[Counter] CooldownService no disponible.")
		return

	var tp_svc = GameServiceLocator.get_service("TPService")
	var abs_svc = GameServiceLocator.get_service("AbilityStateService")

	if abs_svc and abs_svc.is_mode_active(caster_id, slot_index):
		print("[Counter] Ventana ya activa, ignorado | peer: ", caster_id)
		return

	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			return

	combat.apply_root(player_node, COUNTER_WINDOW + 2.0)
	player_node.rpc("_sync_effect", "free_look", true)

	if abs_svc:
		abs_svc.activate_mode(caster_id, slot_index, {
			"range": data.range_,
		})

	if data.prepare_animation != "":
		player_node.play_prepare_animation(data.prepare_animation, slot_index, player_node.facing_right)

	if is_instance_valid(player_node) and player_node.multiplayer.is_server():
		AudioManager.play_sfx_networked.rpc(SfxId.GRAB, player_node.global_position.x, player_node.global_position.y)

	hs.create({
		"attacker_id"   : caster_id,
		"attacker_node" : player_node,
		"type"          : "area",
		"aim_mode"      : "origin",
		"shape_scene"   : data.ability_scene,
		"team_filter"   : "enemy",
		"hit_limit"     : 0,
		"lifetime"      : COUNTER_WINDOW,

		"on_end": func(_hit_count: int) -> void:
			if not is_instance_valid(player_node):
				return

			if abs_svc and abs_svc.is_mode_active(caster_id, slot_index):
				combat.remove_root(player_node)
				abs_svc.deactivate_mode(caster_id, slot_index)

				if cd.has_method("release_lock"):
					cd.release_lock(caster_id, slot_index)
				cd.start(caster_id, slot_index, data.cooldown)

				player_node.rpc("_sync_effect", "free_look", false)
				player_node.rpc("_sync_cancel_ability")
	})

	print("[Counter] Ventana activa | peer: ", caster_id,
		  " | radio: ", data.range_, " | ventana: ", COUNTER_WINDOW, "s")


func try_intercept(target: Node, attacker: Node, data: AbilityData, slot_index: int) -> bool:
	if not is_instance_valid(target):
		return false

	var caster_id: int = target.get_multiplayer_authority()
	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if not abs_svc or not abs_svc.is_mode_active(caster_id, slot_index):
		return false

	if not is_instance_valid(attacker):
		return false

	abs_svc.deactivate_mode(caster_id, slot_index)
	target.rpc("_sync_effect", "free_look", false)

	var combat = GameServiceLocator.get_service("CombatMediator")
	var cd_svc = GameServiceLocator.get_service("CooldownService")
	var tp_svc = GameServiceLocator.get_service("TPService")

	if combat:
		combat.remove_root(target)

	var dist: float = target.global_position.distance_to(attacker.global_position)
	var counter_range: float = data.range_ if data else 120.0
	var in_range: bool = dist <= counter_range

	if in_range and combat:
		var dmg: int = int(data.base_damage * data.evo_damage_multiplier) if data else 0
		if dmg > 0:
			combat.apply_damage(target, attacker, dmg, data.attack_type if data else "normal")

		if is_instance_valid(target) and target.multiplayer.is_server():
			AudioManager.play_sfx_networked.rpc(SfxId.HIT, target.global_position.x, target.global_position.y)

		var is_killer: bool = attacker.is_in_group("killer")
		if not is_killer and attacker.get("character_data"):
			is_killer = attacker.character_data.team == "killer"

		if is_killer:
			var stun_dur: float = (data.stun_duration + data.evo_status_duration_bonus) if data else 0.0
			if stun_dur > 0.0:
				combat.apply_stun(attacker, stun_dur)

		if data and data.tp_reward > 0.0 and tp_svc:
			tp_svc.add_tp_custom(caster_id, data.tp_reward)

	if cd_svc:
		if cd_svc.has_method("release_lock"):
			cd_svc.release_lock(caster_id, slot_index)
		cd_svc.start(caster_id, slot_index, data.cooldown if data else 25.0)

	if in_range and data and data.action_animation != "":
		target.play_ability_animation(data.action_animation, slot_index, target.facing_right)
		var anim_dur: float = _get_anim_duration_static(target, data.action_animation)
		target.get_tree().create_timer(anim_dur).timeout.connect(
			func() -> void:
				if is_instance_valid(target):
					target.rpc("_sync_cancel_ability")
		)
	else:
		target.rpc("_sync_cancel_ability")

	return true


static func _get_anim_duration_static(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return ANIM_FALLBACK
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return ANIM_FALLBACK
	if not sprite.sprite_frames.has_animation(anim_name):
		return ANIM_FALLBACK
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return ANIM_FALLBACK
	return frame_count / fps


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	return _get_anim_duration_static(player_node, anim_name)
