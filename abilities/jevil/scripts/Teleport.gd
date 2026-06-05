extends AbilityBase

const MAX_TELEPORTS: int = 3
const TELEPORT_DELAY: float = 0.4
const TIME_BETWEEN_TELEPORTS: float = 1.0
const PIKE_IMPACT_LIFETIME: float = 0.3

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

	var combat = GameServiceLocator.get_service("CombatMediator")
	if combat:
		if not combat.stun_applied.is_connected(_on_jevil_stunned):
			combat.stun_applied.connect(_on_jevil_stunned)
		if not combat.damage_dealt.is_connected(_on_jevil_damaged):
			combat.damage_dealt.connect(_on_jevil_damaged)

	print("[Teleport] Activado | caster: ", _caster_id, " | slot: ", _slot_index)
	_start_next_teleport()


func _start_next_teleport() -> void:
	if not _active or not is_instance_valid(_player_node):
		_finish()
		return

	_current_target = _find_random_target()
	if not _current_target:
		print("[Teleport] No hay target vivo, terminando.")
		_finish()
		return

	print("[Teleport] Teleport ", _teleports_done + 1, "/", MAX_TELEPORTS, " → ", _current_target.name)
	_set_visible(false)

	var tree = _player_node.get_tree()
	if not tree:
		_finish()
		return
	tree.create_timer(0.2).timeout.connect(_do_teleport)


func _do_teleport() -> void:
	if not _active or not is_instance_valid(_player_node) or not is_instance_valid(_current_target):
		print("[Teleport] Cancelado en _do_teleport (nodo inválido)")
		_finish()
		return

	var spawn_dist: float = _data.range_ if _data and _data.range_ > 0 else 100.0
	var dir_to_target: Vector2 = (_current_target.global_position - _player_node.global_position).normalized()
	if dir_to_target == Vector2.ZERO:
		dir_to_target = Vector2.RIGHT

	_player_node.global_position = _current_target.global_position - dir_to_target * spawn_dist
	_player_node.facing_right = dir_to_target.x >= 0.0

	print("[Teleport] Teletransportado a ", _player_node.global_position)
	_set_visible(true)

	if _data and _data.prepare_animation != "":
		_player_node.play_prepare_animation(_data.prepare_animation, _slot_index, _player_node.facing_right)

	var tree = _player_node.get_tree()
	if not tree:
		_finish()
		return
	tree.create_timer(TELEPORT_DELAY).timeout.connect(_do_attack)


func _do_attack() -> void:
	if not _active or not is_instance_valid(_player_node) or not is_instance_valid(_current_target):
		print("[Teleport] Cancelado en _do_attack (nodo inválido)")
		_finish()
		return

	_spawn_pikes()

	_teleports_done += 1
	print("[Teleport] Ataque completado ", _teleports_done, "/", MAX_TELEPORTS)

	if _teleports_done >= MAX_TELEPORTS:
		_finish()
	else:
		var tree = _player_node.get_tree()
		if not tree:
			_finish()
			return
		tree.create_timer(TIME_BETWEEN_TELEPORTS).timeout.connect(_start_next_teleport)


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
			"on_hit": func(_target_node: Node) -> void:
				pass
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
	_active = false
	_finish()


func _on_jevil_damaged(_attacker_id: int, target_id: int, _final_damage: int, _attack_type: String) -> void:
	if target_id != _caster_id or not _active:
		return
	print("[Teleport] Cancelado por daño")
	_active = false
	_finish()


func _set_visible(v: bool) -> void:
	if is_instance_valid(_player_node):
		_player_node.visible = v


func _finish() -> void:
	if not _active:
		return
	_active = false

	print("[Teleport] Finalizando | slot: ", _slot_index)

	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
		_cd_svc.start(_caster_id, _slot_index, _data.cooldown if _data else 10.0)

	_set_visible(true)

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_cancel_ability")

	var combat = GameServiceLocator.get_service("CombatMediator")
	if combat:
		if combat.stun_applied.is_connected(_on_jevil_stunned):
			combat.stun_applied.disconnect(_on_jevil_stunned)
		if combat.damage_dealt.is_connected(_on_jevil_damaged):
			combat.damage_dealt.disconnect(_on_jevil_damaged)
