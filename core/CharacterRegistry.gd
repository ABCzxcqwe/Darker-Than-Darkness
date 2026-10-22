# res://core/CharacterRegistry.gd  (Autoload)
# Carga la base de datos central de personajes desde un archivo .tres único.
# Evita problemas de escaneo de carpetas en builds exportadas y asegura consistencia en red.
#
# Catálogo separado:
#   - characters      → personajes normales (selector público, auto-selección, logros)
#   - dev_characters  → personajes de test (solo panel dev F8 en builds DEV)
#
# get_character() busca en AMBOS, para que cualquier peer pueda resolver el ID
# de un personaje dev si el servidor lo permite. Así nadie se queda sin datos.
#
# Se accede via: CharacterRegistry.get_character(id)
extends Node

const DB_PATH := "res://Characters/CharacterDatabase.tres"

# { id: int → CharacterData } — solo normales
var characters: Dictionary = {}
# { id: int → CharacterData } — solo dev_only
var dev_characters: Dictionary = {}


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
	dev_characters.clear()

	for data in db.character_list:
		if not data:
			push_warning("[CharacterRegistry] Se encontró un slot vacío (null) en la lista de la base de datos.")
			continue
		# Robustez: si el .tres tenía UID inválido, Godot crea PlaceholderText en lugar de CharacterData
		if not data is CharacterData:
			push_warning("[CharacterRegistry] Recurso corrupto/Placeholder en DB (UID inválido): ", data, " — ignorando.")
			continue
		if data.id <= 0:
			push_warning("[CharacterRegistry] ID inválido (", data.id, ") en '", data.resource_path.get_file(), "' — ignorando. Revisa CharacterData.id")
			continue
		if characters.has(data.id) or dev_characters.has(data.id):
			push_warning("[CharacterRegistry] ID duplicado detectado: ", data.id,
				" en el recurso '", data.resource_path.get_file(), "' — ignorando duplicado.")
			continue

		var character_folder = data.resource_path.get_base_dir().get_file()
		if data.dev_only:
			dev_characters[data.id] = data
			print("[CharacterRegistry] ✓ [DEV] '", character_folder, "' cargado desde DB (id: ", data.id, ")")
		else:
			characters[data.id] = data
			print("[CharacterRegistry] ✓ '", character_folder, "' cargado desde DB (id: ", data.id, ")")

	print("[CharacterRegistry] Personajes normales: ", characters.size(),
		" | Personajes dev: ", dev_characters.size(),
		" | Total: ", characters.size() + dev_characters.size())


## API pública — personajes normales
func get_all() -> Array:
	return characters.values()


## API pública — personajes de test (solo panel F8)
func get_all_dev() -> Array:
	return dev_characters.values()


## Todos los personajes, normales y dev. Para herramientas internas.
func get_all_including_dev() -> Array:
	var result: Array = characters.values()
	result.append_array(dev_characters.values())
	return result


## Busca en normales y dev. Devuelve una copia para que el llamador no mute
## el recurso compartido de la base de datos.
func get_character(id: int) -> CharacterData:
	if characters.has(id):
		return characters[id].duplicate(true)
	if dev_characters.has(id):
		return dev_characters[id].duplicate(true)
	push_warning("[CharacterRegistry] No existe personaje con id ", id)
	return null


func has_character(id: int) -> bool:
	return characters.has(id) or dev_characters.has(id)


func is_dev_only(id: int) -> bool:
	return dev_characters.has(id)


## Devuelve SIEMPRE un personaje normal válido para el bando indicado.
## Es el fallback de red: nunca devuelve un personaje dev ni el id 0.
func get_fallback(team: String = "") -> CharacterData:
	var wanted := team.to_lower().strip_edges()
	var candidates := characters.values()
	if candidates.is_empty():
		push_error("[CharacterRegistry] No hay personajes normales cargados; no se puede construir un fallback.")
		return null

	candidates.sort_custom(func(a: CharacterData, b: CharacterData) -> bool:
		return a.id < b.id
	)

	for data in candidates:
		if wanted == "" or data.team.to_lower().strip_edges() == wanted:
			return data.duplicate(true)

	# Si no hay ninguno del bando pedido, al menos devolvemos uno válido.
	push_warning("[CharacterRegistry] No hay personaje normal para el bando '", team, "'; usando fallback genérico.")
	return candidates[0].duplicate(true)


## Resuelve un ID de red. Si no existe, devuelve el fallback del bando.
## Úsalo en puntos donde un null rompería el spawn o la HUD.
func resolve_character(id: int, team_hint: String = "") -> CharacterData:
	var data := get_character(id)
	if data:
		return data
	var fallback := get_fallback(team_hint)
	if fallback:
		push_warning("[CharacterRegistry] ID ", id, " no resuelto; usando fallback '",
			fallback.display_name, "' (id ", fallback.id, ") para el bando '", team_hint, "'.")
	return fallback
