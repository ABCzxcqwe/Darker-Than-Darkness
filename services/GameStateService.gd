# GameStateService.gd
# Servicio que indica si hay una partida activa.
# Es el primero que se consulta en AbilityRouter, HitboxService, etc.
# Se activa cuando el World termina de cargar y se desactiva al destruirse.
extends Node

var _in_game: bool = false


func _ready() -> void:
	# El World ya está cargado cuando este nodo existe,
	# así que la partida está activa desde el momento en que se instancia.
	_in_game = true
	print("[GameStateService] Partida activa.")


func _exit_tree() -> void:
	# El World se está destruyendo — la partida terminó.
	_in_game = false
	print("[GameStateService] Partida terminada.")


## Devuelve true si hay una partida en curso.
func is_in_game() -> bool:
	return _in_game
