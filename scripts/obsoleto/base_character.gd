#extends Node2D
#
#class_name BaseCharacter
#
#@onready var spawner = $MultiplayerSpawner
#@onready var spawn_point = $SpawnPoint
#
## Diccionario de recursos CharacterData
#var character_library = {
#	"kris": preload("res://scenes/Character/Kris/KrisData.tres"),
#	"susie": preload("res://scenes/Character/Susie/susie.tres"),
#	"killer_base": preload("res://scenes/Character/Susie/susie.tres")
#}
#
#func _ready():
#	if multiplayer.is_server():
#		spawner.spawn_path = get_path()
#		spawner.spawn_function = _spawn_character
#		await get_tree().create_timer(0.5).timeout
#		spawn_players()
#
#func _spawn_character(peer_id: int) -> Node:
#	print("Spawneando personaje para peer_id: ", peer_id)
#	
#	var player_info = NetworkManager.players.get(peer_id)
#	if not player_info:
#		push_error("No se encontró info para peer_id: ", peer_id)
#		return null
#	
#	# Obtener el CharacterData según el rol
#	var data: CharacterData
#	if player_info["role"] == "killer":
#		data = character_library["killer_base"]
#	else:
#		var key = player_info.get("selected_character", "kris")
#		data = character_library.get(key, character_library["kris"])
#	
#	if not data:
#		push_error("No se encontró CharacterData para: ", player_info)
#		return null
#	
#	# ✅ Usar data.scene (la propiedad correcta)
#	if not data.scene:
#		push_error("CharacterData no tiene scene asignada para: ", data.name)
#		return null
#	
#	var new_char = data.scene.instantiate()
#	new_char.name = str(peer_id)
#	new_char.global_position = spawn_point.global_position
#	
#	# Pasar los datos al personaje
#	if new_char.has_method("setup_character"):
#		new_char.setup_character(data)
#	
#	print("Personaje creado: ", data.name, " para peer_id: ", peer_id)
#	return new_char
#
#func spawn_players():
#	for peer_id in NetworkManager.players:
#		print("Solicitando spawn para peer_id: ", peer_id)
#		spawner.spawn(peer_id)
#
