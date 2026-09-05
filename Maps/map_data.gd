# res://Maps/map_data.gd
extends Resource
class_name MapData

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D = null
@export var map_scene: PackedScene = null

@export_group("Audio del Mapa")
## Música de fondo estándar al iniciar la partida.
@export var map_bgm: AudioStream = null
## Punto en segundos desde donde reinicia el loop (0 = inicio). Usado para MP3/Ogg (loop_offset) y WAV (loop_begin).
@export var map_bgm_loop_start: float = 0.0
## Punto en segundos donde se corta antes del silencio final (-1 = fin real). Para WAV usa loop_end nativo; para MP3/Ogg se hace seek manual.
@export var map_bgm_loop_end: float = -1.0

## Pista que sonará cuando quede 1 minuto en el temporizador o las salidas estén abiertas.
@export var final_phase_music: AudioStream = null
@export var final_phase_loop_start: float = 0.0
@export var final_phase_loop_end: float = -1.0
