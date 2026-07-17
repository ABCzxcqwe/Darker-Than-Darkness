@tool
extends Resource
class_name EmoteData

@export var display_name: String = ""

## Icono 38x38 que se muestra en la barra de emotes
@export var icon: Texture2D

## Nombre de la animación en el SpriteFrames del personaje
@export var animation_name: String = ""

## Si true, la animación se reproduce en loop hasta cancelarse manualmente
@export var is_looping: bool = true

## Sonido que se reproduce al activar el emote (opcional)
@export var sfx: AudioStream

## Si true, el audio se reproduce en loop mientras el emote esté activo
@export var audio_loops: bool = false

## Distancia máxima a la que se escucha el emote (en píxeles)
@export_range(1.0, 5000.0) var audio_range: float = 800.0
