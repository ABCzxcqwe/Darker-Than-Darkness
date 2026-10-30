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


## Prepara un SoulCursor de menú: guarda su padre original y lo oculta
## hasta que se coloque por primera vez. Así no se ve el flash en (0,0).
static func init_soul(soul: Control) -> void:
	if not is_instance_valid(soul):
		return
	soul.set_meta("menu_soul_root", soul.get_parent())
	soul.set_meta("menu_soul_gen", 0)
	soul.set_meta("menu_soul_placed", false)
	soul.mouse_filter = Control.MOUSE_FILTER_IGNORE
	soul.visible = false


## Mueve el SoulCursor a `target` esperando a que el layout esté listo.
## `inside_button` lo reparenta dentro del botón (estilo Deltarune).
## La primera colocación es instantánea para evitar el salto desde (0,0).
static func move_soul(soul: Control, target: Control, instant: bool = false,
		gap: float = 12.0, inside_button: bool = false) -> void:
	if not is_instance_valid(soul) or not is_instance_valid(target):
		return

	var gen: int = int(soul.get_meta("menu_soul_gen", 0)) + 1
	soul.set_meta("menu_soul_gen", gen)

	var tree := soul.get_tree()
	if tree == null:
		return

	# Un frame siempre: los contenedores actualizan posiciones al final del frame.
	await tree.process_frame
	if not is_instance_valid(soul) or not is_instance_valid(target):
		return
	if int(soul.get_meta("menu_soul_gen", 0)) != gen:
		return

	for _i in 3:
		if not is_instance_valid(target):
			return
		if target.is_visible_in_tree() and target.size.x > 0.0 and target.size.y > 0.0:
			break
		await tree.process_frame
		if not is_instance_valid(soul) or not is_instance_valid(target):
			return
		if int(soul.get_meta("menu_soul_gen", 0)) != gen:
			return

	if not target.is_visible_in_tree():
		return

	var old_tw = soul.get_meta("menu_soul_tween") if soul.has_meta("menu_soul_tween") else null
	if old_tw is Tween and old_tw.is_valid():
		old_tw.kill()
	soul.set_meta("menu_soul_tween", null)

	var root: Node = soul.get_meta("menu_soul_root", soul.get_parent())
	if root == null or not is_instance_valid(root):
		root = soul.get_parent()

	var soul_size := soul.size
	if soul_size.x <= 0.0:
		soul_size.x = 20.0
	if soul_size.y <= 0.0:
		soul_size.y = 20.0

	var use_inside: bool = inside_button and target is Button
	var first := not bool(soul.get_meta("menu_soul_placed", false))
	soul.set_meta("menu_soul_placed", true)

	if use_inside:
		if soul.get_parent() != target:
			soul.reparent(target, false)
		var inside_pos := Vector2(12.0, maxf(0.0, (target.size.y - soul_size.y) * 0.5))
		inside_pos.x = clampf(inside_pos.x, 6.0, maxf(6.0, target.size.x - soul_size.x - 6.0))
		soul.visible = true
		if instant or first:
			soul.position = inside_pos
		else:
			var tw := soul.create_tween()
			tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.tween_property(soul, "position", inside_pos, 0.08)
			soul.set_meta("menu_soul_tween", tw)
		return

	if soul.get_parent() != root:
		soul.reparent(root, false)

	var target_rect := target.get_global_rect()
	var dest := Vector2(
		target_rect.position.x - soul_size.x - gap,
		target_rect.position.y + (target_rect.size.y - soul_size.y) * 0.5
	)
	soul.visible = true
	if instant or first:
		soul.global_position = dest
	else:
		var tw2 := soul.create_tween()
		tw2.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw2.tween_property(soul, "global_position", dest, 0.08)
		soul.set_meta("menu_soul_tween", tw2)
