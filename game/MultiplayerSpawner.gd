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

	# 1. Obtener el rol directamente de la red (Fuente de verdad del Servidor)
	var player_role := "survivor" # Por defecto de seguridad
	if NetworkManager.players.has(id):
		player_role = NetworkManager.players[id].get("assigned_role", "survivor")
	else:
		# Si por alguna razón no está en NetworkManager, intentamos leer el recurso como respaldo
		var character_path := "res://Characters/%d/data.tres" % char_id
		if ResourceLoader.exists(character_path):
			var char_data = load(character_path) as CharacterData
			if char_data and "team" in char_data:
				player_role = char_data.team
			elif char_data and "assigned_role" in char_data:
				player_role = char_data.assigned_role

	# 2. Buscar el mapa actual en el árbol a través de World
	var world_node = get_tree().root.find_child("World", true, false)
	if world_node and "current_map_node" in world_node and world_node.current_map_node:
		var map = world_node.current_map_node as BaseMap
		
		# Asignamos la posición según el rol unificado
		if player_role == "killer":
			player.global_position = map.get_random_killer_spawn()
		else:
			player.global_position = map.get_random_survivor_spawn()
			
		print("[Spawner] Peer %d asignado al rol '%s'. Spawn en: %s" % [id, player_role, player.global_position])
	else:
		push_error("[Spawner] Imposible posicionar al jugador %d. World o current_map_node no están listos." % id)

	# Se mantiene la inicialización diferida para los componentes @onready del player
	player.call_deferred("set_character", char_id)

	return player
