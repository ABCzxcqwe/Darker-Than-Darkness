extends AbilityBase

func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return
	if not player_node.multiplayer.is_server():
		return

	var caster_id := player_node.get_multiplayer_authority()
	player_node.rpc("_rpc_spawn_secret_visual", caster_id)

	var heal_amt: int = data.base_heal if data.base_heal > 0 else 40

	player_node.get_tree().create_timer(1.5).timeout.connect(
		func():
			if not is_instance_valid(player_node):
				return
			var health_svc = GameServiceLocator.health
			if health_svc:
				health_svc.heal(player_node, heal_amt)
	)
