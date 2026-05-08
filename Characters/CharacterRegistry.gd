# CharacterRegistry.gd  (Autoload)
# Escanea res://Characters/ al iniciar y carga todos los CharacterData que encuentre.
# Convención: cada personaje vive en su propia carpeta y tiene un archivo data.tres
#   res://Characters/NombrePersonaje/data.tres
#
# Se accede via: CharacterRegistry.get_character(id)
extends Node

# { id: int → CharacterData }
var characters: Dictionary = {}

func _ready() -> void:
	_scan_characters()


func _scan_characters() -> void:
	var dir := DirAccess.open("res://Characters/")
	if not dir:
		push_error("[CharacterRegistry] No se pudo abrir res://Characters/")
		return

	dir.list_dir_begin()
	var folder := dir.get_next()

	while folder != "":
		# Ignorar archivos sueltos y carpetas ocultas
		if dir.current_is_dir() and not folder.begins_with("."):
			var path := "res://Characters/%s/data.tres" % folder
			if ResourceLoader.exists(path):
				var data: CharacterData = load(path)
				if data:
					if characters.has(data.id):
						push_warning("[CharacterRegistry] ID duplicado ", data.id,
								" en '", folder, "' — ignorando.")
					else:
						characters[data.id] = data
						print("[CharacterRegistry] ✓ '", folder, "' cargado (id: ", data.id, ")")
				else:
					push_warning("[CharacterRegistry] No se pudo cargar: ", path)
			else:
				push_warning("[CharacterRegistry] '", folder, "' no tiene data.tres, ignorando.")
		folder = dir.get_next()

	dir.list_dir_end()
	print("[CharacterRegistry] Total personajes cargados: ", characters.size())


## API pública
func get_character(id: int) -> CharacterData:
	if not characters.has(id):
		push_warning("[CharacterRegistry] No existe personaje con id ", id)
		return null
	return characters[id]

func get_all() -> Array:
	return characters.values()
