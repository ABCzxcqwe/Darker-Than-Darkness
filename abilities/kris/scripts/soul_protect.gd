extends AbilityBase

const DURATION: float = 10.0
const SHARE_PCT: float = 0.5


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

	var health_svc = GameServiceLocator.get_service("HealthService")
	if not health_svc:
		return

	health_svc.register_protection(target_peer_id, caster_id,
		health_svc.ProtectionType.DAMAGE_SHARE, { "share_pct": SHARE_PCT })

	var cd_svc = GameServiceLocator.get_service("CooldownService")
	var timer := player_node.get_tree().create_timer(DURATION)
	timer.timeout.connect(func() -> void:
		if health_svc:
			health_svc.unregister_protection(target_peer_id, caster_id,
				health_svc.ProtectionType.DAMAGE_SHARE)

		if cd_svc:
			if cd_svc.has_method("release_lock"):
				cd_svc.release_lock(caster_id, slot_index)
			cd_svc.start(caster_id, slot_index, data.cooldown)

		print("[SoulProtect] Proteccion expirada para ", target_peer_id)
	)

	print("[SoulProtect] Kris(", caster_id, ") protege a ", target_peer_id,
		  " por ", DURATION, "s | comparte ", SHARE_PCT * 100, "% del daño")
