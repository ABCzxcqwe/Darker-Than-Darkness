# res://Network/session/match_scene_manager.gd
class_name MatchSceneManager
extends Node
## Dueño del ciclo de vida del `World` dentro de `Main.tscn`.
##
## `MatchCoordinator.current_game_manager` es la instancia de Main.tscn; este
## script crea/libera el World hijo. No duplica la referencia: la jerarquía es
## MatchCoordinator -> Main.tscn (MatchSceneManager) -> World.

const TAG := "MatchSceneManager"

var world_instance: Node = null


func _ready() -> void:
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	LobbyManager.player_left.connect(_on_player_left)


func start_game(player_characters: Dictionary, _map_name: String, local_view_mode: String = "play") -> void:
	var packed := load(NetScenes.WORLD_UID) as PackedScene
	if packed == null:
		NetLog.error(TAG, "No se pudo cargar el World (%s)." % NetScenes.WORLD_UID)
		return

	world_instance = packed.instantiate()
	world_instance.set_meta("player_characters", player_characters)
	world_instance.set_meta("local_view_mode", local_view_mode)

	# La partida vive en el área lejana de Session para que el hub y el mapa
	# coexistan. Main.tscn es un Node (sin transform), así que el World se cuelga
	# del MatchArea del hub.
	var hub := get_tree().get_first_node_in_group(NetScenes.HUB_SESSION_GROUP)
	if hub and hub.has_method("get_match_root"):
		var match_root: Node = hub.get_match_root()
		if match_root:
			match_root.add_child(world_instance)
			return
	add_child(world_instance)


func get_world_instance() -> Node:
	return world_instance if is_instance_valid(world_instance) else null


func cleanup() -> void:
	if is_instance_valid(world_instance):
		world_instance.queue_free()
	world_instance = null

	if NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.server_disconnected.disconnect(_on_server_disconnected)
	if LobbyManager.player_left.is_connected(_on_player_left):
		LobbyManager.player_left.disconnect(_on_player_left)


func _on_player_left(peer_id: int) -> void:
	if multiplayer.is_server():
		_remove_player_character(peer_id)


func _unregister_player_services(peer_id: int) -> void:
	var valid_world := get_world_instance()
	var player_node = (
		valid_world.get_node(str(peer_id))
		if valid_world and valid_world.has_node(str(peer_id))
		else null
	)
	if player_node:
		PlayerLifecycleManager.unregister_player(peer_id, player_node)
	NetLog.debug(TAG, "Servicios desregistrados para peer %d." % peer_id)


func _remove_player_character(peer_id: int) -> void:
	var valid_world := get_world_instance()
	if valid_world and valid_world.has_node(str(peer_id)):
		_unregister_player_services(peer_id)
		valid_world.get_node(str(peer_id)).queue_free()
		rpc("_sync_remove_player", peer_id)


@rpc("authority", "call_local", "reliable")
func _sync_remove_player(peer_id: int) -> void:
	if multiplayer.is_server():
		return
	var valid_world := get_world_instance()
	if valid_world and valid_world.has_node(str(peer_id)):
		valid_world.get_node(str(peer_id)).queue_free()


func _on_server_disconnected() -> void:
	NetLog.info(TAG, "Servidor desconectado; limpiando mundo local.")
	cleanup()
