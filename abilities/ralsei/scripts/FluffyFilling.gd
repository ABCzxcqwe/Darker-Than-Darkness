extends AbilityBase


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	push_warning("[FluffyFilling] Habilidad no implementada.")

	if is_instance_valid(player_node):
		var caster_id: int = player_node.get_multiplayer_authority()
		var cd_svc = GameServiceLocator.get_service("CooldownService")
		if cd_svc and cd_svc.has_method("release_lock"):
			cd_svc.release_lock(caster_id, slot_index)
		if cd_svc:
			cd_svc.start(caster_id, slot_index, data.cooldown if data else 1.0)
