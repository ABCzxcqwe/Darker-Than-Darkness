# res://Maps/MapData.gd
# Resource que describe un mapa disponible en el juego.
# Convención: cada mapa vive en su propia carpeta:
#   res://Maps/NombreDelMapa/map_data.tres
#   res://Maps/NombreDelMapa/nombre_del_mapa.tscn
extends Resource
class_name MapData

# Identificador único del mapa — debe ser único entre todos los mapas.
# Se usa como clave en GameData.selected_map y MapRegistry.
# Ejemplo: "forest_map", "city_ruins", "abandoned_lab"
@export var id: String = ""

@export var display_name: String = ""
@export var icon: Texture2D = null


# Escena principal del mapa — arrastrá el .tscn desde el FileSystem
@export var map_scene: PackedScene = null
@export var map_bgm: AudioStream = null
