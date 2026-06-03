extends AbilityBase

const DURATION: float = 3.0
const REDUCTION_PCT: float = 0.3


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	var tp_svc = GameServiceLocator.get_service("TPService")
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			return

	var combat = GameServiceLocator.get_service("CombatMediator")
	if not combat:
		return

	combat.register_protection(caster_id, caster_id,
		combat.ProtectionType.DAMAGE_REDUCE, { "reduction_pct": REDUCTION_PCT })
	combat.register_protection(caster_id, caster_id,
		combat.ProtectionType.DEATH_SHIELD, {})

	var cd_svc = GameServiceLocator.get_service("CooldownService")
	var timer := player_node.get_tree().create_timer(DURATION)
	timer.timeout.connect(func() -> void:
		combat.unregister_protection(caster_id, caster_id,
			combat.ProtectionType.DAMAGE_REDUCE)
		combat.unregister_protection(caster_id, caster_id,
			combat.ProtectionType.DEATH_SHIELD)

		if cd_svc:
			if cd_svc.has_method("release_lock"):
				cd_svc.release_lock(caster_id, slot_index)
			cd_svc.start(caster_id, slot_index, data.cooldown)

		print("[Determination] Proteccion expirada para ", caster_id)
	)

	print("[Determination] Kris(", caster_id, ") activa determinacion por ", DURATION,
		  "s | reduce daño ", REDUCTION_PCT * 100, "%")
