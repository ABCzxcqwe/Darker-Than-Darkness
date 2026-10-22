# res://core/menu_utils.gd
# Helpers compartidos para saber si hay algún menú abierto.
class_name MenuUtils
extends RefCounted


## True si algún nodo del grupo GAME_MENU está abierto.
## `exclude` permite ignorar el menú que hace la consulta.
static func is_any_menu_open(tree: SceneTree, exclude: Node = null) -> bool:
	if tree == null:
		return false
	for menu in tree.get_nodes_in_group(GroupNames.GAME_MENU):
		if menu == exclude:
			continue
		if menu.has_method("is_open") and menu.is_open():
			return true
	return false
