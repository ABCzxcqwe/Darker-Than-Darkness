extends Marker2D
class_name MapSpawnPoint

@export var spawn_id: String = ""

## Pool de escenas para spawn aleatorio (futuro: items, objetos, efectos)
@export var spawn_pool: Array[PackedScene] = []

func spawn_random() -> Node:
	if spawn_pool.is_empty():
		return null
	var scene: PackedScene = spawn_pool[randi() % spawn_pool.size()]
	var instance := scene.instantiate()
	instance.global_position = global_position
	return instance

func spawn_index(index: int) -> Node:
	if index < 0 or index >= spawn_pool.size():
		return null
	var scene: PackedScene = spawn_pool[index]
	var instance := scene.instantiate()
	instance.global_position = global_position
	return instance
