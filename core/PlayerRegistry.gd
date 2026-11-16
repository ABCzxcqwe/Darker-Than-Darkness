extends Node
## Facade de compatibilidad para consumidores viejos.
##
## El registro real vive en `PlayerLifecycleManager` (reescritura de red).
## Se mantiene este autoload para abilities/UI que todavía llaman
## `PlayerRegistry.get_player()`.

func register(peer_id: int, player_node: Node) -> void:
	PlayerLifecycleManager.register_node(peer_id, player_node)


func unregister(peer_id: int) -> void:
	var node := PlayerLifecycleManager.get_player(peer_id)
	if node != null:
		PlayerLifecycleManager.unregister_player(peer_id, node)


func get_player(peer_id: int) -> Node:
	return PlayerLifecycleManager.get_player(peer_id)


func has_player(peer_id: int) -> bool:
	return PlayerLifecycleManager.has_player(peer_id)


func get_all_players() -> Array:
	return PlayerLifecycleManager.get_all_players()


func get_all_peer_ids() -> Array:
	return PlayerLifecycleManager.get_all_peer_ids()
