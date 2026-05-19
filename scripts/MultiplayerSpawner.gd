# res://scripts/MultiplayerSpawner.gd
extends MultiplayerSpawner

const PLAYER_SCENE := preload("res://Characters/player.tscn")

func _ready() -> void:
	spawn_function = _custom_spawn


func _custom_spawn(data: Array) -> Node:
	var id: int      = data[0]
	var char_id: int = data[1]

	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id)

	# 1. Carga Dinámica del CharacterData (Estilo CharacterRegistry)
	# Construimos la ruta asumiendo la convención de carpetas por ID: res://Characters/ID/data.tres
	var character_path := "res://Characters/%d/data.tres" % char_id
	var char_data: CharacterData = null

	if ResourceLoader.exists(character_path):
		char_data = load(character_path) as CharacterData
	else:
		push_error("[Spawner] No se encontró el recurso data.tres en la ruta: " + character_path)

	# 2. Buscar el mapa actual en el árbol a través de World
	var world_node = get_tree().root.find_child("World", true, false)
	if world_node and "current_map_node" in world_node and world_node.current_map_node:
		var map = world_node.current_map_node as BaseMap
		
		if char_data:
			if char_data.team == "killer":
				player.global_position = map.get_random_killer_spawn()
			else:
				player.global_position = map.get_random_survivor_spawn()
			print("[Spawner] Personaje asignado al bando '%s'. Spawn asignado en: %s" % [char_data.team, player.global_position])
		else:
			# Respaldo de emergencia si falló la carga del recurso
			player.global_position = map.get_random_survivor_spawn()
	else:
		push_error("[Spawner] Imposible posicionar al jugador. World o current_map_node no están listos.")

	# Se mantiene la inicialización diferida para los componentes @onready del player
	player.call_deferred("set_character", char_id)

	return player
