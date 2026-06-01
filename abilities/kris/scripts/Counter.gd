extends AbilityBase


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[Counter] player_node inválido.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	var combat  = GameServiceLocator.get_service("CombatMediator")
	var cd_svc  = GameServiceLocator.get_service("CooldownService")
	var tp_svc  = GameServiceLocator.get_service("TPService")

	if not abs_svc:
		push_error("[Counter] AbilityStateService no disponible.")
		return
	if not combat:
		push_error("[Counter] CombatMediator no disponible.")
		return
	if not cd_svc:
		push_error("[Counter] CooldownService no disponible.")
		return

	if abs_svc.is_mode_active(caster_id, slot_index):
		print("[Counter] Ventana ya activa, ignorado | peer: ", caster_id)
		return

	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			return

	abs_svc.activate_mode(caster_id, slot_index, {
		"range": data.range_,
	})

	combat.apply_root(player_node, data.cooldown + 1.0)

	if data.prepare_animation != "":
		player_node.play_prepare_animation(data.prepare_animation, slot_index, player_node.facing_right)

	print("[Counter] Ventana activa | peer: ", caster_id, " | radio: ", data.range_)

	var counter_window: float = _get_anim_duration(player_node, data.prepare_animation)
	player_node.get_tree().create_timer(counter_window).timeout.connect(
		func() -> void:
			if not is_instance_valid(player_node):
				return
			if abs_svc.is_mode_active(caster_id, slot_index):
				abs_svc.deactivate_mode(caster_id, slot_index)
				combat.remove_root(player_node)
				player_node.rpc("_sync_cancel_ability")

				if cd_svc.has_method("release_lock"):
					cd_svc.release_lock(caster_id, slot_index)
				cd_svc.start(caster_id, slot_index, data.cooldown)
				print("[Counter] Ventana expiró sin golpe | peer: ", caster_id)
	)


func try_intercept(target: Node, attacker: Node, data: AbilityData, slot_index: int) -> bool:
	if not is_instance_valid(target):
		return false

	var caster_id: int = target.get_multiplayer_authority()

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if not abs_svc or not abs_svc.is_mode_active(caster_id, slot_index):
		return false

	abs_svc.deactivate_mode(caster_id, slot_index)

	var combat = GameServiceLocator.get_service("CombatMediator")
	var cd_svc = GameServiceLocator.get_service("CooldownService")
	var tp_svc = GameServiceLocator.get_service("TPService")

	if combat:
		combat.remove_root(target)

	var mode_data: Dictionary = abs_svc.get_mode_data(caster_id, slot_index)
	var counter_range: float  = mode_data.get("range", data.range_ if data else 120.0)
	var killer_in_range: bool = false

	if is_instance_valid(attacker):
		var dist: float = target.global_position.distance_to(attacker.global_position)
		killer_in_range = dist <= counter_range

	if killer_in_range:
		if data and data.stun_duration > 0.0 and combat:
			combat.apply_stun(attacker, data.stun_duration)

		if data and data.tp_reward > 0.0 and tp_svc:
			tp_svc.add_tp_custom(caster_id, data.tp_reward)

		if data and data.action_animation != "":
			target.play_ability_animation(
				data.action_animation, slot_index, target.facing_right
			)
			var anim_dur: float = _get_anim_duration_static(target, data.action_animation)
			target.get_tree().create_timer(anim_dur).timeout.connect(
				func() -> void:
					if is_instance_valid(target):
						target.rpc("_sync_cancel_ability")
			)
		else:
			target.rpc("_sync_cancel_ability")
	else:
		target.rpc("_sync_cancel_ability")

	if cd_svc:
		if cd_svc.has_method("release_lock"):
			cd_svc.release_lock(caster_id, slot_index)
		cd_svc.start(caster_id, slot_index, data.cooldown)

	return true


const _ANIM_FALLBACK: float = 2.0

func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return _ANIM_FALLBACK
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return _ANIM_FALLBACK
	if not sprite.sprite_frames.has_animation(anim_name):
		return _ANIM_FALLBACK
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return _ANIM_FALLBACK
	return frame_count / fps


static func _get_anim_duration_static(player_node: Node, anim_name: String) -> float:
	const FALLBACK: float = 2.0
	if anim_name == "":
		return FALLBACK
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return FALLBACK
	if not sprite.sprite_frames.has_animation(anim_name):
		return FALLBACK
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return FALLBACK
	return frame_count / fps
