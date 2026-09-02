extends AbilityBase

const PROJECTILE_SPEED: float = 700.0
const PROJECTILE_MAX_DISTANCE: float = 500.0
const SINE_AMPLITUDE: float = 40.0
const SINE_FREQUENCY: float = 3.0
const LIFETIME_AFTER_ARRIVAL: float = 2.0
const TP_PER_HIT: float = 15.0
const FIRE_INTERVAL: float = 0.5
const CAST_BUFFER: float = 0.3
const COOLDOWN_BASE: float = 12.0
const COOLDOWN_PER_MINE: float = 1.5
const SLOW_MAGNITUDE: float = 0.5
const SLOW_DURATION: float = 3.0

static var _projectile_container: Node = null

var _caster_id: int = -1
var _slot_index: int = -1
var _total_hits: int = 0
var _pending_projectiles: int = 0
var _fired_count: int = 0
var _active: bool = false
var _tp_svc
var _cd_svc
var _data: AbilityData
var _player_node: Node
var _container: Node
var _shape_scene: PackedScene
var _fire_dir: Vector2 = Vector2.RIGHT


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[FluffyFilling] player_node inválido.")
		return

	_player_node = player_node
	_caster_id = player_node.get_multiplayer_authority()
	_slot_index = slot_index
	_tp_svc = GameServiceLocator.tp
	_cd_svc = GameServiceLocator.cooldown
	_data = data
	_active = true
	_total_hits = 0
	_fired_count = 0
	_pending_projectiles = _get_projectile_count(data)

	if data.tp_cost > 0.0 and _tp_svc:
		if not _tp_svc.consume_tp(_caster_id, data.tp_cost):
			push_warning("[FluffyFilling] consume_tp falló para peer ", _caster_id)
			_release_lock_for(_caster_id, _slot_index)
			return

	var proj_dir: Vector2 = direction.normalized()
	if proj_dir == Vector2.ZERO:
		proj_dir = Vector2.RIGHT if player_node.facing_right else Vector2.LEFT

	var facing_right: bool = proj_dir.x >= 0.0
	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, _slot_index, facing_right)

	_fire_dir = proj_dir

	if is_instance_valid(player_node) and player_node.multiplayer.is_server():
		player_node.rpc("_sync_effect", "free_look", true)

	var combat = GameServiceLocator.combat_mediator
	var anim_dur := _get_anim_duration(player_node, data.action_animation)
	var projectile_count: int = _get_projectile_count(data)
	var total_cast: float = anim_dur + FIRE_INTERVAL * (projectile_count - 1) + CAST_BUFFER
	if combat:
		combat.apply_root(_player_node, total_cast)

	_container = _get_container(player_node)
	_shape_scene = data.ability_scene
	if not _container or not _shape_scene:
		push_error("[FluffyFilling] No se encontró container o shape_scene.")
		_release_lock_for(_caster_id, _slot_index)
		return

	if is_instance_valid(player_node) and player_node.multiplayer.is_server():
		player_node.get_tree().create_timer(total_cast).timeout.connect(
			func() -> void:
				_end_cast()
		)

		var fire_start: float = anim_dur * 0.3
		for i in range(projectile_count):
			player_node.get_tree().create_timer(fire_start + FIRE_INTERVAL * i).timeout.connect(
				func():
					_fire_shot()
			)

	print("[FluffyFilling] Activado | peer: ", _caster_id, " | dir: ", proj_dir)


func _fire_shot() -> void:
	if not _active or not is_instance_valid(_player_node) or _fired_count >= _pending_projectiles:
		return
	if not _container or not _shape_scene:
		return

	var dir: Vector2 = _fire_dir
	if is_instance_valid(_player_node) and _player_node._latest_aim_dir != Vector2.ZERO:
		dir = _player_node._latest_aim_dir

	var projectile = _shape_scene.instantiate()
	projectile.attacker_id = _caster_id
	projectile.attacker_node = _player_node
	projectile.direction = dir
	projectile.speed = PROJECTILE_SPEED
	projectile.max_distance = PROJECTILE_MAX_DISTANCE
	projectile.sine_amplitude = SINE_AMPLITUDE
	projectile.sine_frequency = SINE_FREQUENCY
	projectile.lifetime_after_arrival = LIFETIME_AFTER_ARRIVAL
	projectile.set_multiplayer_authority(_player_node.get_tree().get_multiplayer().get_unique_id())

	projectile.collision_layer = 32
	projectile.collision_mask = 8 | 16

	projectile.on_hit_callback = _on_projectile_hit
	projectile.on_end_callback = _on_projectile_end
	projectile.slow_magnitude = SLOW_MAGNITUDE
	projectile.slow_duration = SLOW_DURATION
	projectile.mine_tp_amount = TP_PER_HIT

	projectile.global_position = _player_node.global_position
	_container.add_child(projectile, true)

	_fired_count += 1
	print("[FluffyFilling] Disparo ", _fired_count, "/", _pending_projectiles, " | dir: ", dir)


func _end_cast() -> void:
	if not _active or not is_instance_valid(_player_node):
		return
	_active = false

	var combat = GameServiceLocator.combat_mediator
	if combat:
		combat.remove_root(_player_node)

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_effect", "free_look", false)
		_player_node.rpc("_sync_cancel_ability")

	print("[FluffyFilling] Cast finalizado")


func _on_projectile_hit(target_node: Node) -> void:
	if not is_instance_valid(target_node):
		return
	if not _tp_svc:
		return

	var health_svc = GameServiceLocator.health
	var target_id: int = target_node.get_multiplayer_authority()

	if health_svc and not health_svc.is_alive(target_id):
		return

	if target_node.is_in_group("killer"):
		var taken: bool = _tp_svc.consume_tp(target_id, TP_PER_HIT)
		if taken:
			_tp_svc.add_tp_custom(_caster_id, TP_PER_HIT)
			var combat = GameServiceLocator.combat_mediator
			if combat:
				combat.apply_slow(target_node, SLOW_DURATION, SLOW_MAGNITUDE)
	elif target_node.is_in_group("survivor"):
		_tp_svc.add_tp_custom(target_id, TP_PER_HIT)


func _on_projectile_end(hit_flag: bool) -> void:
	if hit_flag:
		_total_hits += 1
	_pending_projectiles -= 1
	if _pending_projectiles <= 0:
		_finish_ability()


func _finish_ability() -> void:
	_active = false
	if not _data:
		push_warning("[FluffyFilling] _data es null en _finish_ability")
		return

	var combat = GameServiceLocator.combat_mediator
	if combat:
		combat.remove_root(_player_node)

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_effect", "free_look", false)
		_player_node.rpc("_sync_cancel_ability")

	var active_mines := _count_active_mines()
	var cd := COOLDOWN_BASE + COOLDOWN_PER_MINE * active_mines

	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
		_cd_svc.start(_caster_id, _slot_index, cd)

	print("[FluffyFilling] Finalizado | hits: ", _total_hits, " | minas activas: ", active_mines, " | cooldown: ", cd, "s")


func _count_active_mines() -> int:
	var tree = _player_node.get_tree() if is_instance_valid(_player_node) else null
	if not tree:
		return 0
	var count := 0
	for mine in tree.get_nodes_in_group("fluffy_mines"):
		if is_instance_valid(mine):
			var attacker_id = mine.get("attacker_id") if "attacker_id" in mine else -1
			if attacker_id == _caster_id:
				count += 1

	return count


func _release_lock_for(peer_id: int, slot_index: int) -> void:
	var cd = GameServiceLocator.cooldown
	if cd and cd.has_method("release_lock"):
		cd.release_lock(peer_id, slot_index)


func _get_projectile_count(data: AbilityData) -> int:
	if data and data.projectile_count > 0:
		return data.projectile_count
	return 1


func _get_container(player_node: Node) -> Node:
	if not is_instance_valid(_projectile_container):
		var world = player_node.get_tree().root.find_child("World", true, false)
		_projectile_container = world.get_node_or_null("Projectiles") if world else null
	return _projectile_container


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
