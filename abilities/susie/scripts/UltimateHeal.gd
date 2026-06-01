extends AbilityBase


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[UltimateHealth] player_node inválido.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	var target_node: Node = _resolve_target(player_node, caster_id)
	if not is_instance_valid(target_node):
		print("[UltimateHealth] Sin objetivo válido. Cancelado.")
		return

	var target_peer_id: int = target_node.get_multiplayer_authority()

	var tp_svc = GameServiceLocator.get_service("TPService")
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			push_warning("[UltimateHealth] consume_tp falló para peer ", caster_id)
			return

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	var heal_ratio: float = 0.0
	if abs_svc:
		heal_ratio = abs_svc.get_scaled_value(caster_id, slot_index, data)
	else:
		heal_ratio = data.scaling_base_value

	var max_hp: int = target_node.character_data.max_health if target_node.character_data else 100
	var heal_amount: int = maxi(1, int(max_hp * heal_ratio))

	var health_svc = GameServiceLocator.get_service("HealthService")
	if not health_svc:
		push_error("[UltimateHealth] HealthService no disponible.")
		return

	if not health_svc.is_alive(target_peer_id):
		print("[UltimateHealth] El objetivo está caído o muerto.")
		return

	health_svc.heal(target_node, heal_amount)

	if abs_svc:
		abs_svc.register_use(caster_id, slot_index, data)

	var cd_svc = GameServiceLocator.get_service("CooldownService")
	if cd_svc:
		if cd_svc.has_method("release_lock"):
			cd_svc.release_lock(caster_id, slot_index)
		if abs_svc:
			var dynamic_cd: float = abs_svc.get_dynamic_cooldown(caster_id, slot_index)
			cd_svc.start(caster_id, slot_index, dynamic_cd)
		else:
			cd_svc.start(caster_id, slot_index, data.cooldown)

	var use_count: int = abs_svc.get_use_count(caster_id, slot_index) if abs_svc else 0
	print("[UltimateHealth] Curación aplicada | caster: ", caster_id,
		  " | objetivo: ", target_peer_id, " | uso #", use_count,
		  " | ratio: ", "%.1f" % (heal_ratio * 100), "%",
		  " | HP: ", heal_amount)


func _resolve_target(player_node: Node, caster_id: int) -> Node:
	if pending_target_peer > 0 and pending_target_peer != caster_id:
		var target = player_node.get_tree().root.find_child(str(pending_target_peer), true, false)
		if is_instance_valid(target) and target.is_in_group("survivor"):
			return target
		return null

	return player_node
