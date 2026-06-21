extends AbilityBase

const DOUBLE_HEAL_MULTIPLIER: float = 2.0


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[HealPrayer] player_node inválido.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	var target_node: Node = _resolve_target(player_node, caster_id)
	if not is_instance_valid(target_node):
		return

	var target_peer_id: int = target_node.get_multiplayer_authority()

	if target_node.get("health_state") == "dead":
		return

	var health_svc = GameServiceLocator.get_service("HealthService")
	if not health_svc:
		push_error("[HealPrayer] HealthService no disponible.")
		return

	if not health_svc.is_alive(target_peer_id):
		return

	var tp_svc = GameServiceLocator.get_service("TPService")
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			return

	var base_heal: int = data.base_heal if data.base_heal > 0 else 40
	var final_heal: int = base_heal
	var is_double: bool = false

	var lms_svc = GameServiceLocator.get_service("LMSService")
	if lms_svc and lms_svc.is_lms_active():
		var lms_survivor = lms_svc.get_active_survivor()
		if lms_survivor and lms_survivor.get_multiplayer_authority() == caster_id:
			var threshold: float = data.scaling_base_value if data and "scaling_base_value" in data else 0.35
			if randf() < threshold:
				final_heal = int(base_heal * DOUBLE_HEAL_MULTIPLIER)
				is_double = true

	health_svc.heal(target_node, final_heal)

	var cd_svc = GameServiceLocator.get_service("CooldownService")
	if cd_svc:
		if cd_svc.has_method("release_lock"):
			cd_svc.release_lock(caster_id, slot_index)
		cd_svc.start(caster_id, slot_index, data.cooldown)

	player_node.get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if is_instance_valid(player_node):
			var combat = GameServiceLocator.get_service("CombatMediator")
			if combat:
				combat.apply_root(player_node, 0.001)
	)

	print("[HealPrayer] Curación aplicada | caster: ", caster_id,
		  " | objetivo: ", target_peer_id, " | HP: ", final_heal,
		  " | Double Heal: ", is_double)


func _resolve_target(player_node: Node, caster_id: int) -> Node:
	if pending_target_peer > 0 and pending_target_peer != caster_id:
		var target = player_node.get_tree().root.find_child(str(pending_target_peer), true, false)
		if is_instance_valid(target) and target.is_in_group("survivor"):
			return target
		return null

	return player_node
