# res://scripts/BaseMap.gd
extends Node2D
class_name BaseMap

@onready var killer_spawns: Node2D = $SpawnPoints/KillerSpawns
@onready var survivor_spawns: Node2D = $SpawnPoints/SurvivorSpawns

## Devuelve una posición global aleatoria para el Killer de entre todos los Marker2D disponibles
func get_random_killer_spawn() -> Vector2:
	if killer_spawns and killer_spawns.get_child_count() > 0:
		var index := randi() % killer_spawns.get_child_count()
		var spawn_node = killer_spawns.get_child(index) as Marker2D
		if spawn_node:
			return spawn_node.global_position
	push_warning("[BaseMap] No se encontraron Marker2Ds en KillerSpawns. Usando origen.")
	return global_position

## Devuelve una posición global aleatoria para un Survivor de entre todos los Marker2D disponibles
func get_random_survivor_spawn() -> Vector2:
	if survivor_spawns and survivor_spawns.get_child_count() > 0:
		var index := randi() % survivor_spawns.get_child_count()
		var spawn_node = survivor_spawns.get_child(index) as Marker2D
		if spawn_node:
			return spawn_node.global_position
	push_warning("[BaseMap] No se encontraron Marker2Ds en SurvivorSpawns. Usando origen.")
	return global_position
