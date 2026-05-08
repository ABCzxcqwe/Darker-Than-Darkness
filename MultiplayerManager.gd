extends Node

const WORLD_SCENE := preload("res://World.tscn")
var world_instance: Node = null

func _ready():
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.player_left.connect(_on_player_left)

func start_game(player_characters: Dictionary, _map_name: String):
	world_instance = WORLD_SCENE.instantiate()
	add_child(world_instance)
	if multiplayer.is_server():
		var spawner = world_instance.get_node("MultiplayerSpawner")
		if spawner:
			for peer_id in player_characters:
				var char_id = player_characters[peer_id]
				spawner.spawn([peer_id, char_id])
		else:
			print("ERROR: No se encontró MultiplayerSpawner en World")

func cleanup():
	if world_instance:
		world_instance.queue_free()
		world_instance = null
	# Desconectar señales para que no disparen después de limpiar
	if NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.server_disconnected.disconnect(_on_server_disconnected)
	if NetworkManager.player_left.is_connected(_on_player_left):
		NetworkManager.player_left.disconnect(_on_player_left)

func _on_player_left(peer_id: int):
	if multiplayer.is_server():
		_remove_player_character(peer_id)

func _remove_player_character(peer_id: int):
	if world_instance and world_instance.has_node(str(peer_id)):
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
