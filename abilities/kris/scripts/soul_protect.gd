extends AbilityBase

const DURATION: float = 5.0
const SHARE_PCT: float = 0.5
const ANIM_FALLBACK: float = 1.6


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	var tp_svc = GameServiceLocator.get_service("TPService")
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			return

	var target_peer_id: int = pending_target_peer
	if target_peer_id <= 0 or target_peer_id == caster_id:
		return

	var combat = GameServiceLocator.get_service("CombatMediator")
	if not combat:
		return

	# Play action animation first (root is already active from prepare phase)
	var anim_dur := _get_anim_duration(player_node, data.action_animation)

	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, slot_index, player_node.facing_right)

	player_node.get_tree().create_timer(anim_dur).timeout.connect(
		func() -> void:
			if not is_instance_valid(player_node):
				return

			if player_node.state != 2 or player_node.active_ability_slot != slot_index:
				return

			combat.remove_root(player_node)

			combat.register_protection(target_peer_id, caster_id,
				combat.ProtectionType.DAMAGE_SHARE, { "share_pct": SHARE_PCT })
			combat.register_protection(target_peer_id, caster_id,
				combat.ProtectionType.DEATH_SHIELD, {})

			var cd_svc = GameServiceLocator.get_service("CooldownService")
			var expire_timer := player_node.get_tree().create_timer(DURATION)
			expire_timer.timeout.connect(func() -> void:
				if not is_instance_valid(player_node):
					return
				combat.unregister_protection(target_peer_id, caster_id,
					combat.ProtectionType.DAMAGE_SHARE)
				combat.unregister_protection(target_peer_id, caster_id,
					combat.ProtectionType.DEATH_SHIELD)

				if cd_svc:
					if cd_svc.has_method("release_lock"):
						cd_svc.release_lock(caster_id, slot_index)
					cd_svc.start(caster_id, slot_index, data.cooldown)

				print("[SoulProtect] Proteccion expirada para ", target_peer_id)
			)

			player_node.rpc("_sync_cancel_ability")

			print("[SoulProtect] Kris(", caster_id, ") protege a ", target_peer_id,
				  " por ", DURATION, "s | comparte ", SHARE_PCT * 100, "% del daño")
	)


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
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
