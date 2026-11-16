# res://scripts/BaseMap.gd
extends Node2D
class_name BaseMap

@onready var killer_spawns: Node2D = $SpawnPoints/KillerSpawns
@onready var survivor_spawns: Node2D = $SpawnPoints/SurvivorSpawns

## Devuelve una posición global aleatoria para el Killer de entre todos los Marker2D disponibles
func get_random_killer_spawn() -> Vector2:
	var positions := get_killer_spawn_positions()
	if not positions.is_empty():
		return positions[randi() % positions.size()]
	push_warning("[BaseMap] No se encontraron Marker2Ds en KillerSpawns. Usando origen.")
	return global_position

## Devuelve una posición global aleatoria para un Survivor de entre todos los Marker2D disponibles
func get_random_survivor_spawn() -> Vector2:
	var positions := get_survivor_spawn_positions()
	if not positions.is_empty():
		return positions[randi() % positions.size()]
	push_warning("[BaseMap] No se encontraron Marker2Ds en SurvivorSpawns. Usando origen.")
	return global_position


## Todas las posiciones de spawn del Killer, para asignar una única por jugador.
func get_killer_spawn_positions() -> Array[Vector2]:
	return _collect_spawn_positions(_resolve_spawn_container(killer_spawns, "KillerSpawns"))


## Todas las posiciones de spawn de Survivor, para asignar una única por jugador.
func get_survivor_spawn_positions() -> Array[Vector2]:
	return _collect_spawn_positions(_resolve_spawn_container(survivor_spawns, "SurvivorSpawns"))


## Si la ruta directa no existe en el mapa, la buscamos por nombre en el árbol.
func _resolve_spawn_container(container: Node2D, name_hint: String) -> Node2D:
	if container != null:
		return container
	return find_child(name_hint, true, false) as Node2D


func _collect_spawn_positions(container: Node2D) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if container == null:
		return positions
	for child in container.get_children():
		if child is Marker2D:
			positions.append((child as Marker2D).global_position)
	return positions
