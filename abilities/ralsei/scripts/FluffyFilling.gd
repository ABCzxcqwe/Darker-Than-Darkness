extends AbilityBase

const PROJECTILE_SPEED: float = 700.0
const PROJECTILE_MAX_DISTANCE: float = 500.0
const SINE_AMPLITUDE: float = 40.0
const SINE_FREQUENCY: float = 3.0
const LIFETIME_AFTER_ARRIVAL: float = 2.0
const SPREAD_DEG: float = 15.0
const TP_PER_HIT: float = 15.0


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[FluffyFilling] player_node inválido.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	var tp_svc = GameServiceLocator.get_service("TPService")
	var cd = GameServiceLocator.get_service("CooldownService")

	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			push_warning("[FluffyFilling] consume_tp falló para peer ", caster_id)
			_release_lock_for(caster_id, slot_index)
			return

	var proj_dir: Vector2 = direction.normalized()
	if proj_dir == Vector2.ZERO:
		proj_dir = Vector2.RIGHT if player_node.facing_right else Vector2.LEFT

	var facing_right: bool = proj_dir.x >= 0.0
	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, slot_index, facing_right)

	var anim_dur := _get_anim_duration(player_node, data.action_animation)
	if is_instance_valid(player_node) and player_node.multiplayer.is_server():
		player_node.get_tree().create_timer(anim_dur).timeout.connect(
			func() -> void:
				if is_instance_valid(player_node):
					player_node.rpc("_sync_cancel_ability")
		)

	var world = player_node.get_tree().root.find_child("World", true, false)
	var container = world.get_node_or_null("Projectiles") if world else null
	if not container:
		push_error("[FluffyFilling] No se encontró World/Projectiles.")
		_release_lock_for(caster_id, slot_index)
		return

	var shape_scene: PackedScene = data.ability_scene
	if not shape_scene:
		push_error("[FluffyFilling] No hay ability_scene asignada.")
		_release_lock_for(caster_id, slot_index)
		return

	var spread_rad: float = deg_to_rad(SPREAD_DEG)
	var directions: Array[Vector2] = [
		proj_dir.rotated(-spread_rad),
		proj_dir,
		proj_dir.rotated(spread_rad),
	]

	var total_hits: int = 0
	var pending_projectiles: int = directions.size()

	for dir_i in directions:
		var projectile = shape_scene.instantiate()
		projectile.attacker_id = caster_id
		projectile.attacker_node = player_node
		projectile.direction = dir_i
		projectile.speed = PROJECTILE_SPEED
		projectile.max_distance = PROJECTILE_MAX_DISTANCE
		projectile.sine_amplitude = SINE_AMPLITUDE
		projectile.sine_frequency = SINE_FREQUENCY
		projectile.lifetime_after_arrival = LIFETIME_AFTER_ARRIVAL
		projectile.set_multiplayer_authority(1)

		projectile.collision_layer = 32
		projectile.collision_mask = 8 | 16

		projectile.on_hit_callback = func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return
			if not tp_svc:
				return

			var health_svc = GameServiceLocator.get_service("HealthService")
			var target_id: int = target_node.get_multiplayer_authority()
			if health_svc and not health_svc.is_alive(target_id):
				return

			if target_node.is_in_group("killer"):
				var taken: bool = tp_svc.consume_tp(target_id, TP_PER_HIT)
				if taken:
					tp_svc.add_tp_custom(caster_id, TP_PER_HIT)
					print("[FluffyFilling] Killer ", target_id, " perdió ", TP_PER_HIT, " TP | Ralsei ganó ", TP_PER_HIT, " TP")
			elif target_node.is_in_group("survivor"):
				tp_svc.add_tp_custom(target_id, TP_PER_HIT)
				print("[FluffyFilling] Aliado ", target_id, " ganó ", TP_PER_HIT, " TP")

		projectile.on_end_callback = func(hit_flag: bool) -> void:
			if hit_flag:
				total_hits += 1
			pending_projectiles -= 1
			if pending_projectiles <= 0:
				_finish_ability(caster_id, slot_index, total_hits, cd, data)

		projectile.global_position = player_node.global_position
		container.add_child(projectile, true)

	print("[FluffyFilling] Activado | peer: ", caster_id, " | dir: ", proj_dir, " | proyectiles: ", directions.size())


func _finish_ability(caster_id: int, slot_index: int, total_hits: int, cd, data: AbilityData) -> void:
	if cd:
		if cd.has_method("release_lock"):
			cd.release_lock(caster_id, slot_index)
		if total_hits > 0:
			cd.start(caster_id, slot_index, data.cooldown)
		else:
			var fail_cd: float = data.cooldown_fail if data.cooldown_fail > 0.0 else data.cooldown
			cd.start(caster_id, slot_index, fail_cd)
	print("[FluffyFilling] Finalizado | golpes totales: ", total_hits)


func _release_lock_for(peer_id: int, slot_index: int) -> void:
	var cd = GameServiceLocator.get_service("CooldownService")
	if cd and cd.has_method("release_lock"):
		cd.release_lock(peer_id, slot_index)


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return 0.5
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return 0.5
	if not sprite.sprite_frames.has_animation(anim_name):
		return 0.5
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return 0.5
	return frame_count / fps
