# res://game/MultiplayerManager.gd
extends Node

const WORLD_SCENE := preload("uid://dy3ln7lsee4qh")
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

func _unregister_player_services(peer_id: int) -> void:
	var hs = GameServiceLocator.get_service("HealthService")
	if hs and hs.has_method("unregister"):
		hs.unregister(peer_id)
	var cd = GameServiceLocator.get_service("CooldownService")
	if cd and cd.has_method("clear_player"):
		cd.clear_player(peer_id)
	var player_node = world_instance.get_node(str(peer_id)) if world_instance and world_instance.has_node(str(peer_id)) else null
	var ss = GameServiceLocator.get_service("StatusEffectService")
	if ss and ss.has_method("unregister") and is_instance_valid(player_node):
		ss.unregister(player_node)
	var tp = GameServiceLocator.get_service("TPService")
	if tp and tp.has_method("unregister_player"):
		tp.unregister_player(peer_id)
	var evo = GameServiceLocator.get_service("EvolutionService")
	if evo and evo.has_method("unregister_player"):
		evo.unregister_player(peer_id)
	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if abs_svc and abs_svc.has_method("unregister_player"):
		abs_svc.unregister_player(peer_id)
	var stam_svc = GameServiceLocator.get_service("StaminaService")
	if stam_svc and stam_svc.has_method("unregister_player"):
		stam_svc.unregister_player(peer_id)
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
