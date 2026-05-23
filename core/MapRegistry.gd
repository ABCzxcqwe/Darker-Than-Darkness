# res://core/MapRegistry.gd
# Escanea res://Maps/ al iniciar y carga todos los MapData que encuentre.
# Convención: cada mapa vive en su propia carpeta con un map_data.tres:
#   res://Maps/NombreDelMapa/map_data.tres
#
# Se accede via: MapRegistry.get_map("forest_map")
extends Node

# { id: String → MapData }
var maps: Dictionary = {}

func _ready() -> void:
	_scan_maps()


func _scan_maps() -> void:
	var dir := DirAccess.open("res://Maps/")
	if not dir:
		push_error("[MapRegistry] No se pudo abrir res://Maps/")
		return

	dir.list_dir_begin()
	var folder := dir.get_next()

	while folder != "":
		if dir.current_is_dir() and not folder.begins_with("."):
			var path := "res://Maps/%s/map_data.tres" % folder
			if ResourceLoader.exists(path):
				var data: MapData = load(path)
				if data:
					if data.id == "":
						push_warning("[MapRegistry] '", folder, "' tiene id vacío — ignorando.")
					elif maps.has(data.id):
						push_warning("[MapRegistry] ID duplicado '", data.id,
								"' en '", folder, "' — ignorando.")
					else:
						maps[data.id] = data
						print("[MapRegistry] ✓ '", folder, "' cargado (id: '", data.id, "')")
				else:
					push_warning("[MapRegistry] No se pudo cargar: ", path)
			else:
				push_warning("[MapRegistry] '", folder, "' no tiene map_data.tres — ignorando.")
		folder = dir.get_next()

	dir.list_dir_end()
	print("[MapRegistry] Total mapas cargados: ", maps.size())


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
