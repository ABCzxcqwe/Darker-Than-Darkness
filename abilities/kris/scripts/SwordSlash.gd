extends MeleeAbilityBase

func _get_config(data: AbilityData) -> Dictionary:
	return {
		"hitbox_lifetime": 0.5,
		"initial_hitbox_damage": 0,
		"damage_multiplier": data.evo_damage_multiplier,
		"stun_duration_bonus": data.evo_status_duration_bonus,
		"sfx": SfxId.HIT,
	}

func _execute(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int, cfg: Dictionary) -> void:
	super._execute(player_node, data, direction, slot_index, cfg)
	if player_node.character_data and player_node.character_data.id == 5 and player_node.multiplayer.is_server():
		player_node.get_tree().create_timer(0.5).timeout.connect(
			func():
				if is_instance_valid(player_node):
					var relay = GameServiceLocator.get_client_relay()
					if is_instance_valid(relay):
						relay.rpc("_rpc_camera_shake", 20.0, 1.5)
		)
