class_name PlayerInteractionComponent
extends Node

var player: CharacterBody2D = null

var is_spectator: bool = false
var _follow_target: Node = null
var _spectator_mode: int = 0
@export var free_cam_speed: float = 400.0
var _spectator_camera: Camera2D = null


func get_follow_target() -> Node:
	return _follow_target


func initialize(body: CharacterBody2D) -> void:
	player = body
	_spectator_camera = player.get_node_or_null("Camera2D")


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


# ── Spectator ──────────────────────────────────────────────────────────

func prepare_spectator_mode() -> void:
	if is_spectator:
		return
	is_spectator = true
	if not player.is_multiplayer_authority():
		return

	var vision := player.get_node_or_null("Vision")
	if vision:
		vision.notify_spectator_mode()

	if player.has_node("Synchronizer"):
		player.get_node("Synchronizer").enabled = false

	player.set_process_input(true)
	player.set_physics_process(true)
	if _spectator_camera:
		_spectator_camera.enabled = true
		_spectator_camera.position_smoothing_speed = 10.0

	_spectator_mode = 0
	cycle_target(1)


func handle_spectator_input(event: InputEvent) -> void:
	if event.is_action_pressed("spec_next"):
		cycle_target(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("spec_prev"):
		cycle_target(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("spec_toggle"):
		_spectator_mode = 1 - _spectator_mode
		if _spectator_mode == 0:
			cycle_target(1)
		get_viewport().set_input_as_handled()


func cycle_target(direction: int) -> void:
	var alive := []
	for p in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if p == player or not is_instance_valid(p):
			continue
		if p.health_state == "alive":
			alive.append(p)
	if alive.is_empty():
		_follow_target = null
		return

	if _follow_target == null or not is_instance_valid(_follow_target):
		_follow_target = alive[0] if direction > 0 else alive[-1]
	else:
		var idx := alive.find(_follow_target)
		if idx == -1:
			_follow_target = alive[0]
		else:
			idx = (idx + direction) % alive.size()
			_follow_target = alive[idx]


func update_spectator_camera(delta: float) -> void:
	if not _spectator_camera:
		return
	if _spectator_mode == 0:
		if _follow_target and is_instance_valid(_follow_target) and _follow_target.health_state == "alive":
			_spectator_camera.offset = _follow_target.global_position - player.global_position
		else:
			cycle_target(1)
	else:
		var dir := Input.get_vector("spec_left", "spec_right", "spec_up", "spec_down")
		if dir.length() > 0.1:
			_spectator_camera.offset += dir * free_cam_speed * delta


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
