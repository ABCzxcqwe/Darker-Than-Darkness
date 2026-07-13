extends Node

enum ArrowType { HIT, DOWN, MAP }

const HIT_DURATION := 2.5

var _next_id: int = 0
var _server_arrows: Dictionary = {}
var _client_relay: Node


func set_client_relay(relay: Node) -> void:
	_client_relay = relay


func show_hit_indicator(player_node: Node, source_pos: Vector2, duration: float = HIT_DURATION) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := player_node.get_multiplayer_authority()
	if not _is_survivor(peer_id):
		return
	var arrow_id := _next_id
	_next_id += 1
	_server_arrows[arrow_id] = {
		"type": ArrowType.HIT,
		"filter_peer": peer_id,
		"duration": duration
	}
	_client_relay.rpc("_rpc_add_arrow", arrow_id, ArrowType.HIT, source_pos.x, source_pos.y, 0, peer_id, duration)
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
		if _server_arrows.has(arrow_id):
			_server_arrows.erase(arrow_id)


func show_down_indicator(player_node: Node) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := player_node.get_multiplayer_authority()
	if not _is_survivor(peer_id):
		return
	var arrow_id := _next_id
	_next_id += 1
	_server_arrows[arrow_id] = {
		"type": ArrowType.DOWN,
		"player_node": player_node,
		"filter_peer": peer_id
	}
	_client_relay.rpc("_rpc_add_arrow", arrow_id, ArrowType.DOWN, player_node.global_position.x, player_node.global_position.y, peer_id, peer_id, 0.0)


func remove_down_indicator(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for arrow_id in _server_arrows.keys():
		var entry = _server_arrows[arrow_id]
		if entry.get("type") == ArrowType.DOWN and entry.get("filter_peer") == peer_id:
			_server_arrows.erase(arrow_id)
			_client_relay.rpc("_rpc_remove_arrow", arrow_id)
			return


func show_map_indicator(target_pos: Vector2, duration: float = 0.0, _target_peer: int = 0) -> int:
	if not multiplayer.is_server():
		return -1
	var arrow_id := _next_id
	_next_id += 1
	_server_arrows[arrow_id] = {
		"type": ArrowType.MAP,
		"duration": duration
	}
	_client_relay.rpc("_rpc_add_arrow", arrow_id, ArrowType.MAP, target_pos.x, target_pos.y, 0, 0, duration)
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
		if _server_arrows.has(arrow_id):
			_server_arrows.erase(arrow_id)
	return arrow_id


func remove_map_indicator(arrow_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _server_arrows.has(arrow_id):
		_server_arrows.erase(arrow_id)
		_client_relay.rpc("_rpc_remove_arrow", arrow_id)

func _is_survivor(peer_id: int) -> bool:
	var player_data = LobbyManager.players.get(peer_id)
	if not player_data:
		return false
	return player_data.get("assigned_role") == "survivor"
