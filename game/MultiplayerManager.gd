# res://game/MultiplayerManager.gd
extends Node

const WORLD_SCENE := preload("uid://dy3ln7lsee4qh")
var world_instance: Node = null

func _ready():
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	LobbyManager.player_left.connect(_on_player_left)

func start_game(player_characters: Dictionary, _map_name: String):
	world_instance = WORLD_SCENE.instantiate()
	world_instance.set_meta("player_characters", player_characters)
	add_child(world_instance)

func cleanup():
	if world_instance:
		world_instance.queue_free()
		world_instance = null
	# Desconectar señales para que no disparen después de limpiar
	if NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.server_disconnected.disconnect(_on_server_disconnected)
	if LobbyManager.player_left.is_connected(_on_player_left):
		LobbyManager.player_left.disconnect(_on_player_left)

func _on_player_left(peer_id: int):
	if multiplayer.is_server():
		_remove_player_character(peer_id)

func _unregister_player_services(peer_id: int) -> void:
	var player_node = world_instance.get_node(str(peer_id)) if world_instance and world_instance.has_node(str(peer_id)) else null
	if player_node:
		PlayerLifecycleManager.unregister_player(peer_id, player_node)
	print("[MultiplayerManager] Servicios desregistrados para peer ", peer_id)

func _remove_player_character(peer_id: int):
	if world_instance and world_instance.has_node(str(peer_id)):
		_unregister_player_services(peer_id)
		world_instance.get_node(str(peer_id)).queue_free()
		rpc("_sync_remove_player", peer_id)

@rpc("authority", "call_local", "reliable")
func _sync_remove_player(peer_id: int):
	if not multiplayer.is_server():
		if world_instance and world_instance.has_node(str(peer_id)):
			world_instance.get_node(str(peer_id)).queue_free()

func _on_server_disconnected():
	print("Servidor desconectado, limpiando...")
	cleanup()  # Limpiar el mundo localmente
