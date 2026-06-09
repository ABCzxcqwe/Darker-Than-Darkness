# res://core/MapRegistry.gd
# Carga la base de datos central de mapas desde un archivo .tres único.
# Se accede via: MapRegistry.get_map("id_del_mapa")
extends Node

const DB_PATH := "res://Maps/WorldDatabase.tres"

# { id: String → MapData }
var maps: Dictionary = {}

func _ready() -> void:
	_load_database()


func _load_database() -> void:
	if not ResourceLoader.exists(DB_PATH):
		push_error("[MapRegistry] CRÍTICO: No existe la base de datos en: " + DB_PATH)
		return

	var db: WorldDatabase = load(DB_PATH) as WorldDatabase
	if not db:
		push_error("[MapRegistry] CRÍTICO: El archivo en path no es un WorldDatabase válido.")
		return

	maps.clear()

	for data in db.map_list:
		if not data:
			push_warning("[MapRegistry] Se encontró un slot vacío (null) en la lista de la base de datos.")
			continue

		if data.id == "":
			push_warning("[MapRegistry] '", data.resource_path.get_file(), "' tiene id vacío — ignorando.")
		elif maps.has(data.id):
			push_warning("[MapRegistry] ID duplicado '", data.id, "' — ignorando.")
		else:
			maps[data.id] = data
			print("[MapRegistry] ✓ '", data.display_name, "' cargado (id: '", data.id, "')")

	print("[MapRegistry] Total mapas cargados desde archivo único: ", maps.size())


# ── API pública ────────────────────────────────────────────────────────

func get_map(id: String) -> MapData:
	if not maps.has(id):
		push_warning("[MapRegistry] No existe mapa con id '", id, "'")
		return null
	return maps[id]

func get_all() -> Array:
	return maps.values()

func has_map(id: String) -> bool:
	return maps.has(id)
