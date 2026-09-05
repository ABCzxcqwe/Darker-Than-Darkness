extends "res://ui/Old/scripts/menu_base.gd"
## Base para sub-secciones de Opciones.
## Cada sub-sección es una ESCENA propia (settings_*.tscn) que ocupa toda la
## pantalla; al navegar entramos con change_scene_to_file desde el hub y
## volvemos con _go_back() (sin superponer UI entre escenas).


## Volver al hub de Opciones.
func _go_back() -> void:
	_go_back_to(SETTINGS_HUB_PATH)


func _on_menu_cancel() -> bool:
	_go_back()
	return true