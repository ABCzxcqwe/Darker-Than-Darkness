# res://Maps/MapData.gd
extends Resource
class_name MapData

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D = null
@export var map_scene: PackedScene = null

@export_group("Audio del Mapa")
## Música de fondo estándar al iniciar la partida.
@export var map_bgm: AudioStream = null

## Pista que sonará cuando quede 1 minuto en el temporizador o las salidas estén abiertas.
@export var final_phase_music: AudioStream = null
