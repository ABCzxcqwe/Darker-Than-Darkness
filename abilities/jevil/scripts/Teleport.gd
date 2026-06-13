extends AbilityBase

const MAX_TELEPORTS: int = 3
const TELEPORT_DELAY: float = 0.4
const TIME_BETWEEN_TELEPORTS: float = 1.0
const PIKE_IMPACT_LIFETIME: float = 0.3

# Duración máxima de la habilidad completa para el root:
# 3 × (0.2 espera + 0.4 ataque) + 2 × 1.0 entre teleports = 3.8s
# Se usa un margen holgado para que el root no expire antes que la habilidad.
const ROOT_DURATION: float = 5.0

# Evita que el RefCounted sea recolectado mientras la habilidad está activa.
static var _keep_alive: Array = []

var _active: bool = false
var _teleports_done: int = 0
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _current_target: Node = null
var _hs = null
var _cd_svc = null
var _tp_svc = null
var _combat = null


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	_player_node = player_node
	_caster_id = player_node.get_multiplayer_authority()
	_data = data
	_slot_index = slot_index
	_active = true
	_teleports_done = 0

	_tp_svc = GameServiceLocator.get_service("TPService")
	if data.tp_cost > 0.0 and _tp_svc:
		if not _tp_svc.consume_tp(_caster_id, data.tp_cost):
			return

	_cd_svc = GameServiceLocator.get_service("CooldownService")
	_hs = GameServiceLocator.get_service("HitboxService")
	_combat = GameServiceLocator.get_service("CombatMediator")

	if _combat:
		_combat.apply_root(_player_node, ROOT_DURATION)
		if not _combat.stun_applied.is_connected(_on_jevil_stunned):
			_combat.stun_applied.connect(_on_jevil_stunned)
		if not _combat.damage_dealt.is_connected(_on_jevil_damaged):
			_combat.damage_dealt.connect(_on_jevil_damaged)

	# Pausar el Synchronizer para que el cliente no sobreescriba
	# la posición del servidor durante los teleports.
	var sync = _player_node.get_node_or_null("Synchronizer")
	if sync:
		sync.set_process(false)
		sync.set_physics_process(false)

	print("[Teleport] Activado | caster: ", _caster_id, " | slot: ", _slot_index)
	_keep_alive.append(self)
	_run()


func _run() -> void:
	while _active and _teleports_done < MAX_TELEPORTS:
		if not _find_and_prepare():
			break
		if not await _do_teleport():
			break
		if not await _do_attack():
			break
		_teleports_done += 1
		print("[Teleport] Ataque completado ", _teleports_done, "/", MAX_TELEPORTS)
		if _teleports_done < MAX_TELEPORTS:
			if not await _wait(TIME_BETWEEN_TELEPORTS):
				return
	_finish()


func _find_and_prepare() -> bool:
	if not _active or not is_instance_valid(_player_node):
		_finish()
		return false

	_current_target = _find_random_target()
	if not _current_target:
		print("[Teleport] No hay target vivo, terminando.")
		_finish()
		return false

	print("[Teleport] Teleport ", _teleports_done + 1, "/", MAX_TELEPORTS, " → ", _current_target.name)
	return true


func _do_teleport() -> bool:
	_set_visible(false)

	if not await _wait(0.2):
		_set_visible(true)
		return false

	if not _active or not is_instance_valid(_player_node) or not is_instance_valid(_current_target):
		print("[Teleport] Cancelado en _do_teleport (nodo inválido)")
		_set_visible(true)
		return false

	var spawn_dist: float = _data.range_ if _data and _data.range_ > 0 else 100.0
	var target_pos: Vector2 = _current_target.global_position
	var jevil_pos: Vector2 = _player_node.global_position
	var dir_to_target: Vector2 = (target_pos - jevil_pos).normalized()
	if dir_to_target == Vector2.ZERO:
		dir_to_target = Vector2.RIGHT

	var desired_pos: Vector2 = target_pos - dir_to_target * spawn_dist
	var safe_pos: Vector2 = _find_safe_position(desired_pos, target_pos, dir_to_target)
	_player_node.global_position = safe_pos
	_player_node.facing_right = dir_to_target.x >= 0.0
	_player_node.rpc("_sync_server_position", safe_pos)

	print("[Teleport] Teletransportado a ", safe_pos, " (deseado: ", desired_pos, ")")
	_set_visible(true)

	if _data and _data.prepare_animation != "":
		_player_node.play_prepare_animation(_data.prepare_animation, _slot_index, _player_node.facing_right)
	return true


func _find_safe_position(desired: Vector2, target_pos: Vector2, dir_to_target: Vector2) -> Vector2:
	var space_state = _player_node.get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(target_pos, desired)
	query.collision_mask = 1
	query.exclude = [_player_node, _current_target]

	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return desired

	var margin: float = 35.0
	var hit_pos: Vector2 = result.position
	var dist_to_target: float = target_pos.distance_to(hit_pos)

	if dist_to_target < margin * 2:
		return desired

	return hit_pos + dir_to_target * margin


func _do_attack() -> bool:
	if not await _wait(TELEPORT_DELAY):
		return false
	if not _active or not is_instance_valid(_player_node) or not is_instance_valid(_current_target):
		print("[Teleport] Cancelado en _do_attack (nodo inválido)")
		return false

	_spawn_pikes()
	return true


func _wait(delay: float) -> bool:
	var tree = _player_node.get_tree() if is_instance_valid(_player_node) else null
	if not tree:
		return false
	await tree.create_timer(delay).timeout
	return _active


func _spawn_pikes() -> void:
	if not _hs or not is_instance_valid(_player_node) or not is_instance_valid(_current_target):
		return

	var dir_to_target: Vector2 = (_current_target.global_position - _player_node.global_position).normalized()
	if dir_to_target == Vector2.ZERO:
		dir_to_target = Vector2.RIGHT

	var arc_angle_deg: float = _data.arc_angle if _data and _data.arc_angle > 0 else 60.0
	var pike_count: int = _data.projectile_count if _data and _data.projectile_count > 0 else 4
	var pike_speed: float = _data.projectile_speed if _data and _data.projectile_speed > 0 else 300.0
	var pike_lifetime: float = _data.projectile_lifetime if _data and _data.projectile_lifetime > 0 else 2.0
	var pike_max_range: float = _data.projectile_max_range if _data else 0.0
	var damage: int = _data.base_damage if _data else 10

	var start_angle: float = -arc_angle_deg / 2.0
	var step: float = arc_angle_deg / (pike_count - 1) if pike_count > 1 else 0.0

	for i in range(pike_count):
		var angle_deg: float = start_angle + step * i
		var pike_dir: Vector2 = dir_to_target.rotated(deg_to_rad(angle_deg))

		_hs.create({
			"attacker_id": _caster_id,
			"attacker_node": _player_node,
			"type": "projectile",
			"aim_mode": "fixed",
			"direction": pike_dir,
			"shape_scene": _data.ability_scene,
			"damage": damage,
			"attack_type": _data.attack_type if _data else "normal",
			"hit_limit": 1,
			"team_filter": "enemy",
			"lifetime": pike_lifetime,
			"speed": pike_speed,
			"hitbox_max_range": pike_max_range,
			"impact_lifetime": PIKE_IMPACT_LIFETIME,
			"detect_walls": true,
			"offset": 0.0,
			"on_hit": func(target_node: Node) -> void:
				if is_instance_valid(target_node) and is_instance_valid(_player_node) and _combat:
					_combat.apply_damage(_player_node, target_node, damage, _data.attack_type if _data else "normal")
		})

	if _data and _data.action_animation != "" and is_instance_valid(_player_node):
		_player_node.play_ability_animation(_data.action_animation, _slot_index, _player_node.facing_right)


func _find_random_target():
	if not is_instance_valid(_player_node):
		return null
	var tree = _player_node.get_tree()
	if not tree:
		return null
	var survivors = tree.get_nodes_in_group("survivor")
	var alive := []
	for s in survivors:
		if is_instance_valid(s):
			var hp_svc = GameServiceLocator.get_service("HealthService")
			if hp_svc and hp_svc.is_alive(s.get_multiplayer_authority()):
				alive.append(s)
	if alive.is_empty():
		return null
	return alive[randi() % alive.size()]


func _on_jevil_stunned(target_id: int, _duration: float) -> void:
	if target_id != _caster_id or not _active:
		return
	print("[Teleport] Cancelado por stun")
	_finish()


func _on_jevil_damaged(_attacker_id: int, target_id: int, _final_damage: int, _attack_type: String) -> void:
	if target_id != _caster_id or not _active:
		return
	print("[Teleport] Cancelado por daño")
	_finish()


func _set_visible(v: bool) -> void:
	if is_instance_valid(_player_node):
		_player_node.visible = v


func _finish() -> void:
	if not _active:
		return
	_active = false

	print("[Teleport] Finalizando | slot: ", _slot_index)

	_set_visible(true)

	if _combat and is_instance_valid(_player_node):
		_combat.remove_root(_player_node)

	# Forzar posición final en el cliente y reactivar el Synchronizer.
	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_server_position", _player_node.global_position)
		var sync = _player_node.get_node_or_null("Synchronizer")
		if sync:
			sync.set_process(true)
			sync.set_physics_process(true)

	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
		_cd_svc.start(_caster_id, _slot_index, _data.cooldown if _data else 10.0)

	if is_instance_valid(_player_node):
		_player_node._sync_cancel_ability.rpc()

	if _combat:
		if _combat.stun_applied.is_connected(_on_jevil_stunned):
			_combat.stun_applied.disconnect(_on_jevil_stunned)
		if _combat.damage_dealt.is_connected(_on_jevil_damaged):
			_combat.damage_dealt.disconnect(_on_jevil_damaged)

	_keep_alive.erase(self)
