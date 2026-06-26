extends AbilityBase

const FALLBACK_ANIM_DURATION: float = 1.0


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[HealPrayer] player_node inválido.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	var target_node: Node = _resolve_target(player_node, caster_id)
	if not is_instance_valid(target_node):
		_release_lock_for(caster_id, slot_index)
		return

	var target_peer_id: int = target_node.get_multiplayer_authority()

	var health_svc = GameServiceLocator.get_service("HealthService")
	if not health_svc:
		push_error("[HealPrayer] HealthService no disponible.")
		_release_lock_for(caster_id, slot_index)
		return

	if not health_svc.is_alive(target_peer_id):
		print("[HealPrayer] El objetivo está caído o muerto.")
		_release_lock_for(caster_id, slot_index)
		return

	var tp_svc = GameServiceLocator.get_service("TPService")
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			push_warning("[HealPrayer] consume_tp falló para peer ", caster_id)
			_release_lock_for(caster_id, slot_index)
			return

	var combat = GameServiceLocator.get_service("CombatMediator")
	var facing_right: bool = player_node.facing_right

	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, slot_index, facing_right)

	if is_instance_valid(player_node) and player_node.multiplayer.is_server():
		AudioManager.play_sfx_networked.rpc(SfxId.SPELLCAST, player_node.global_position.x, player_node.global_position.y)

	var anim_dur := _get_anim_duration(player_node, data.action_animation)
	player_node.get_tree().create_timer(anim_dur).timeout.connect(
		func() -> void:
			if not is_instance_valid(player_node):
				return
			if not is_instance_valid(target_node):
				_release_lock_for(caster_id, slot_index)
				return
			if not health_svc.is_alive(target_peer_id):
				_release_lock_for(caster_id, slot_index)
				return

			var base_heal: int = data.base_heal if data.base_heal > 0 else 35
			health_svc.heal(target_node, base_heal)

			if player_node.multiplayer.is_server():
				AudioManager.play_sfx_networked.rpc(SfxId.HEAL, target_node.global_position.x, target_node.global_position.y)

			var cd_svc = GameServiceLocator.get_service("CooldownService")
			if cd_svc:
				if cd_svc.has_method("release_lock"):
					cd_svc.release_lock(caster_id, slot_index)
				cd_svc.start(caster_id, slot_index, data.cooldown)

			if combat:
				combat.remove_root(player_node)

			player_node.rpc("_sync_cancel_ability")

			print("[HealPrayer] Curación aplicada | caster: ", caster_id,
				  " | objetivo: ", target_peer_id, " | HP: ", base_heal)
	)

	if combat:
		combat.apply_root(player_node, anim_dur + 0.1)


func _release_lock_for(peer_id: int, slot_index: int) -> void:
	var cd_svc = GameServiceLocator.get_service("CooldownService")
	if cd_svc and cd_svc.has_method("release_lock"):
		cd_svc.release_lock(peer_id, slot_index)


func _resolve_target(player_node: Node, caster_id: int) -> Node:
	if pending_target_peer > 0 and pending_target_peer != caster_id:
		var target = player_node.get_tree().root.find_child(str(pending_target_peer), true, false)
		if is_instance_valid(target) and target.is_in_group("survivor"):
			return target
		return null

	return player_node


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return FALLBACK_ANIM_DURATION
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return FALLBACK_ANIM_DURATION
	if not sprite.sprite_frames.has_animation(anim_name):
		return FALLBACK_ANIM_DURATION
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return FALLBACK_ANIM_DURATION
	return frame_count / fps
