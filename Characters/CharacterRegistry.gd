# res://services/CharacterRegistry.gd  (Autoload)
# Carga la base de datos central de personajes desde un archivo .tres único.
# Evita problemas de escaneo de carpetas en builds exportadas y asegura consistencia en red.
#
# Se accede via: CharacterRegistry.get_character(id)
extends Node

const DB_PATH := "res://Characters/CharacterDatabase.tres"

# { id: int → CharacterData }
var characters: Dictionary = {}

func _ready() -> void:
	_load_database()


func _load_database() -> void:
	if not ResourceLoader.exists(DB_PATH):
		push_error("[CharacterRegistry] CRÍTICO: No existe la base de datos en: " + DB_PATH)
		return

	var db: CharacterDatabase = load(DB_PATH) as CharacterDatabase
	if not db:
		push_error("[CharacterRegistry] CRÍTICO: El archivo en path no es un CharacterDatabase válido.")
		return

	characters.clear()

	for data in db.character_list:
		if not data:
			push_warning("[CharacterRegistry] Se encontró un slot vacío (null) en la lista de la base de datos.")
			continue
			
		if characters.has(data.id):
			push_warning("[CharacterRegistry] ID duplicado detectado: ", data.id, 
				" en el recurso '", data.resource_path.get_file(), "' — ignorando duplicado.")
		else:
			characters[data.id] = data
			# Extraemos el nombre de la carpeta para mantener tus logs limpios como antes
			var character_folder = data.resource_path.get_base_dir().get_file()
			print("[CharacterRegistry] ✓ '", character_folder, "' cargado desde DB (id: ", data.id, ")")

	print("[CharacterRegistry] Total personajes cargados desde archivo único: ", characters.size())


## API pública
func get_character(id: int) -> CharacterData:
	if not characters.has(id):
		push_warning("[CharacterRegistry] No existe personaje con id ", id)
		return null
	return characters[id]


func get_all() -> Array:
	return characters.values()
