# res://game/MultiplayerSpawner.gd
extends MultiplayerSpawner

const PLAYER_SCENE := preload("uid://csh822kwn5s2e")

func _ready() -> void:
	spawn_function = _custom_spawn


func _custom_spawn(data: Array) -> Node:
	var id: int      = data[0]
	var char_id: int = data[1]

	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id)

	player.set_character(char_id)

	# Posicionar según el rol (el mapa ya está cargado cuando se spawnea)
	var player_role := "survivor"
	if NetworkManager.players.has(id):
		player_role = NetworkManager.players[id].get("assigned_role", "survivor")

	var world_node = get_tree().root.find_child("World", true, false)
	if world_node and world_node.current_map_node:
		var map = world_node.current_map_node as BaseMap
		if player_role == "killer":
			player.global_position = map.get_random_killer_spawn()
		else:
			player.global_position = map.get_random_survivor_spawn()
		print("[Spawner] Peer %d spawneado como '%s' en: %s" % [id, player_role, player.global_position])
	else:
		push_warning("[Spawner] current_map_node no disponible para posicionar peer %d" % id)

	return player
