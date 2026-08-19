# res://core/PlayerRegistry.gd (Autoload)
# Registro central de nodos de jugador por peer_id.
# Reemplaza el patrón get_tree().root.find_child(str(peer_id)).
extends Node

var _players: Dictionary = {}

 
func register(peer_id: int, player_node: Node) -> void:
	_players[peer_id] = player_node


func unregister(peer_id: int) -> void:
	_players.erase(peer_id)


func get_player(peer_id: int) -> Node:
	return _players.get(peer_id, null)


func has_player(peer_id: int) -> bool:
	return _players.has(peer_id)


func get_all_players() -> Array:
	return _players.values()


func get_all_peer_ids() -> Array:
	return _players.keys()
