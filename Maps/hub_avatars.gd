# res://Network/session/hub_avatars.gd
class_name HubAvatars
extends Node
## Sincronización de avatares del hub (spawn/remove/visibilidad/estado remoto).

const TAG := "HubAvatars"

## Offsets fijos por peer para que los avatares no se apilen al entrar.
const SPAWN_OFFSETS: Array[Vector2] = [
	Vector2(0, 0),
	Vector2(-120, 0),
	Vector2(120, 0),
	Vector2(0, -90),
	Vector2(0, 90),
	Vector2(-120, -90),
	Vector2(120, -90),
	Vector2(-120, 90),
	Vector2(120, 90),
	Vector2(0, 170),
]

var _session: Node
var _actors: Node2D
var _hub_spawn: Marker2D
var _avatars: Dictionary = {}
var _local_avatar: Node = null
var _standalone_dummy := false
var _sync_queued := false
var _avatar_scene: PackedScene = null


func setup(session: Node) -> void:
	_session = session
	_actors = session.get_node_or_null("Actors") as Node2D
	_hub_spawn = session.get_node_or_null("HubArea/HubSpawn") as Marker2D
	_avatar_scene = load(NetScenes.HUB_AVATAR) as PackedScene


func get_local_avatar() -> Node:
	return _local_avatar if is_instance_valid(_local_avatar) else null


func get_avatar(peer_id: int) -> Node:
	var avatar = _avatars.get(peer_id, null)
	return avatar if is_instance_valid(avatar) else null


func has_avatar(peer_id: int) -> bool:
	return _avatars.has(peer_id)


func get_spawn_position(peer_id: int) -> Vector2:
	var idx: int = absi(peer_id) % SPAWN_OFFSETS.size()
	return _hub_spawn.global_position + SPAWN_OFFSETS[idx]


## No agregar/quitar nodos dentro de multiplayer.poll(): las señales del lobby
## pueden llegar en pleno _physics_process de NetworkManager.
func queue_sync() -> void:
	if not _session.is_active() or _sync_queued:
		return
	_sync_queued = true
	call_deferred("_run_sync")


func _run_sync() -> void:
	_sync_queued = false
	if not _session.is_active():
		return
	sync()
	_session.on_avatars_synced()


func sync() -> void:
	if not _session.is_active():
		return

	var ids: Array = LobbyManager.players.keys()
	ids.sort()

	# En la escena standalone (sin red y sin lobby) creamos un avatar local dummy.
	if ids.is_empty() and _avatars.is_empty() and _session.can_spawn_standalone_dummy():
		spawn_avatar(1)
		_standalone_dummy = true
		ids = [1]

	for pid in ids:
		spawn_avatar(int(pid))

	for pid in _avatars.keys():
		if LobbyManager.players.has(pid):
			continue
		if _standalone_dummy and int(pid) == 1 and LobbyManager.players.is_empty():
			continue
		remove_avatar(int(pid))
	if not LobbyManager.players.is_empty():
		_standalone_dummy = false

	_local_avatar = _avatars.get(_session.local_peer_id(), null)
	if _local_avatar and not _session.is_at_hub():
		_session.set_local_avatar_hub_visible(false)

	for pid in _avatars:
		var avatar = _avatars[pid]
		if not is_instance_valid(avatar):
			continue
		var show_avatar := LobbyManager.is_in_hub(int(pid))
		if int(pid) == _session.local_peer_id():
			show_avatar = _session.is_at_hub()
		avatar.visible = show_avatar
		avatar.refresh_name()


func spawn_avatar(peer_id: int) -> void:
	if _avatars.has(peer_id):
		return
	if _avatar_scene == null:
		NetLog.error(TAG, "No se pudo cargar HubAvatar (%s)." % NetScenes.HUB_AVATAR)
		return

	var avatar := _avatar_scene.instantiate()
	avatar.name = str(peer_id)
	avatar.set_multiplayer_authority(peer_id)
	_actors.add_child(avatar)
	avatar.global_position = get_spawn_position(peer_id)
	_avatars[peer_id] = avatar

	if peer_id == _session.local_peer_id():
		_local_avatar = avatar
		_connect_local_avatar(avatar)
		if not _session.is_at_hub():
			_session.set_local_avatar_hub_visible(false)

	avatar.visible = _session.is_at_hub() if peer_id == _session.local_peer_id() else LobbyManager.is_in_hub(peer_id)
	avatar.refresh_name()
	NetLog.debug(TAG, "Avatar creado para peer %d (local=%s)." % [
		peer_id, str(peer_id == _session.local_peer_id())
	])


func remove_avatar(peer_id: int) -> void:
	if not _avatars.has(peer_id):
		return
	var avatar = _avatars[peer_id]
	_avatars.erase(peer_id)
	if avatar == _local_avatar:
		_local_avatar = null
		_session.hide_prompt()
	if is_instance_valid(avatar):
		avatar.queue_free()


func apply_remote_state(peer_id: int, pos: Vector2, flip: bool) -> void:
	var avatar := get_avatar(peer_id)
	if avatar and avatar.has_method("apply_remote_state"):
		avatar.apply_remote_state(pos, flip)


func _connect_local_avatar(avatar: Node) -> void:
	if not avatar.has_signal("interactable_changed"):
		return
	if not avatar.interactable_changed.is_connected(_on_interactable_changed):
		avatar.interactable_changed.connect(_on_interactable_changed)
	if not avatar.interactable_cleared.is_connected(_on_interactable_cleared):
		avatar.interactable_cleared.connect(_on_interactable_cleared)
	avatar.refresh_interaction()


func _on_interactable_changed(prompt: String) -> void:
	if _session.ui and (_session.ui.is_board_open() or _session.ui.is_shop_open()):
		return
	_session.show_prompt("[Z] " + prompt)


func _on_interactable_cleared() -> void:
	_session.hide_prompt()
