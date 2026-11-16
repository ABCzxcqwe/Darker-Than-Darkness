extends Node
## Facade de compatibilidad para el código viejo del proyecto.
##
## La fuente única de estado es `SessionState`. `GameData` se conserva como
## autoload para no romper AudioManager/tests/UI que todavía leen
## `GameData.selected_map`.

var selected_character: int = 0

var selected_map: String:
	get:
		return SessionState.selected_map
	set(value):
		SessionState.selected_map = value

var active_map_id: String:
	get:
		return SessionState.active_map_id
	set(value):
		SessionState.active_map_id = value
