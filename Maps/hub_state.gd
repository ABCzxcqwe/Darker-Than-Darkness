# res://Network/session/hub_state.gd
class_name HubState
extends Node
## RPC de posición/orientación de los avatares del hub (sin MultiplayerSynchronizer).

var _session: Node


func setup(session: Node) -> void:
	_session = session


## Llamado por el HubAvatar local. El servidor retransmite a todos.
func submit(pos: Vector2, flip: bool) -> void:
	if not _session.is_active():
		return
	if multiplayer.is_server():
		_apply_hub_state.rpc(multiplayer.get_unique_id(), pos, flip)
	else:
		rpc_id(LobbyManager.server_peer_id, "_submit_hub_state", pos, flip)


@rpc("any_peer", "unreliable_ordered")
func _submit_hub_state(pos: Vector2, flip: bool) -> void:
	if not _session.is_active() or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not _session.avatars.has_avatar(sender):
		return
	if not pos.is_finite():
		return
	if pos.distance_to(_session.get_hub_spawn_position()) > 3000.0:
		return
	_apply_hub_state.rpc(sender, pos, flip)


@rpc("authority", "unreliable_ordered", "call_local")
func _apply_hub_state(peer_id: int, pos: Vector2, flip: bool) -> void:
	if not _session.is_active():
		return
	_session.avatars.apply_remote_state(peer_id, pos, flip)
