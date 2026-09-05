extends AbilityBase

func activate(player_node: Node, _data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not player_node.multiplayer.is_server():
		return
	var idx := slot_index if slot_index >= 0 else 4
	var cd = GameServiceLocator.cooldown
	if cd and cd.has_method("release_lock"):
		cd.release_lock(player_node.get_multiplayer_authority(), idx)
