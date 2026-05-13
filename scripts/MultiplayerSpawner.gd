# MultiplayerSpawner.gd
# ✅ CORREGIDO: set_character se llama con call_deferred para que el nodo
# ya esté en el árbol cuando se acceda a $AbilityComponent (nodo @onready).
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

	# NO llamar set_character aquí — el nodo aún no está en el árbol
	# y los @onready como $AbilityComponent aún no existen.
	# Se llama con call_deferred, que ejecuta en el próximo frame
	# después de que add_child() (llamado por el Spawner) haya terminado.
	player.call_deferred("set_character", char_id)

	return player
