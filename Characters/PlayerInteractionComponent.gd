class_name PlayerInteractionComponent
extends Node

var player: CharacterBody2D = null

var is_spectator: bool = false


func initialize(body: CharacterBody2D) -> void:
	player = body


# ── Revive helpers ─────────────────────────────────────────────────────

func find_closest_revivable_target(revive_range: float) -> Node:
	var closest: Node = null
	var closest_dist: float = revive_range + 1.0
	for p in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if p == player: continue
		if not p.is_in_group(GroupNames.SURVIVOR): continue
		if p.health_state != "downed": continue
		var dist := player.global_position.distance_to(p.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = p
	return closest


func get_self_on_server() -> Node:
	return PlayerRegistry.get_player(player.get_multiplayer_authority())


# ── Corpse ─────────────────────────────────────────────────────────────

func disable_corpse() -> void:
	if not _disable_collisions():
		push_error("[PlayerInteraction] fallo al desactivar colisiones.")


func _disable_collisions() -> bool:
	var success := true
	if not player.is_inside_tree():
		push_error("[PlayerInteraction] nodo no en el árbol.")
		return false

	if player.has_node("CollisionShape2D"):
		var world_shape = player.get_node("CollisionShape2D")
		if world_shape.has_method("set_deferred"):
			world_shape.set_deferred("disabled", true)
		else:
			push_error("[PlayerInteraction] CollisionShape2D no soporta set_deferred.")
			success = false
	else:
		push_error("[PlayerInteraction] CollisionShape2D no encontrado.")
		success = false

	if player.has_node("Hurtbox/CollisionShape2D"):
		var hurtbox_shape = player.get_node("Hurtbox/CollisionShape2D")
		if hurtbox_shape.has_method("set_deferred"):
			hurtbox_shape.set_deferred("disabled", true)
		else:
			push_error("[PlayerInteraction] Hurtbox/CollisionShape2D no soporta set_deferred.")
			success = false
	else:
		push_error("[PlayerInteraction] Hurtbox/CollisionShape2D no encontrado.")
		success = false

	player.set_deferred("collision_layer", 0)
	player.set_deferred("collision_mask", 0)

	return success


func get_corpse_container() -> Node:
	var parent = player.get_parent()
	if not parent:
		parent = get_tree().current_scene
	if not parent:
		return get_tree().root
	var container := parent.find_child("CorpseContainer", true, false)
	if not container:
		container = Node2D.new()
		container.name = "CorpseContainer"
		parent.add_child(container)
	return container
