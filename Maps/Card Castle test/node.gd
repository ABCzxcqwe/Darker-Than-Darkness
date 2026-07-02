@tool
extends Node

# Script de UN SOLO USO. Instrucciones:
# 1. Creá un Node vacío en Castle.tscn (cualquier lugar), asignale este script.
# 2. Ajustá el path de abajo si "Colision" no es hijo directo de la raíz.
# 3. Guardá la escena (Ctrl+S) - el _ready se ejecuta en el editor y crea los occluders.
# 4. Verificá que los LightOccluder2D se crearon correctamente dentro de "Colision".
# 5. BORRÁ este nodo/script de la escena, ya cumplió su función.

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	var colision_node = get_node("../Colision")
	if not colision_node:
		push_error("No se encontró el nodo 'Colision'. Ajustá el path.")
		return

	var count := 0
	for child in colision_node.get_children():
		if child is CollisionPolygon2D:
			var base_name = child.name + "_Occluder"
			# Evita duplicados si corrés esto de nuevo: borra los previos de este child
			for existing in colision_node.get_children():
				if existing is LightOccluder2D and existing.name.begins_with(base_name):
					existing.queue_free()

			# Descompone el polígono (puede ser cóncavo/complejo) en partes convexas simples
			var convex_parts: Array = Geometry2D.decompose_polygon_in_convex(child.polygon)

			if convex_parts.is_empty():
				push_warning("No se pudo descomponer: " + child.name)
				continue

			for i in range(convex_parts.size()):
				var occluder = LightOccluder2D.new()
				occluder.name = base_name + "_%d" % i
				occluder.position = child.position
				occluder.scale = child.scale

				var occ_polygon = OccluderPolygon2D.new()
				occ_polygon.polygon = convex_parts[i]
				occluder.occluder = occ_polygon

				colision_node.add_child(occluder)
				occluder.owner = get_tree().edited_scene_root
				count += 1

	print("Occluders generados: ", count)
