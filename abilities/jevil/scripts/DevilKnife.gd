extends AbilityBase

const AIM_TIMEOUT: float = 8.0

static var _keep_alive: Array = []

static func _invalidate_old_instances() -> void:
	for i in range(_keep_alive.size() - 1, -1, -1):
		var inst = _keep_alive[i]
		if inst._active:
			inst._active = false
			_keep_alive.remove_at(i)


var _active: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	_player_node = player_node
	_caster_id = player_node.get_multiplayer_authority()
	_data = data
	_slot_index = slot_index

	_invalidate_old_instances()

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if abs_svc and abs_svc.is_mode_active(_caster_id, _slot_index):
		_launch(direction)
		return

	_enter_aim()


func _enter_aim() -> void:
	if not is_instance_valid(_player_node):
		return

	_active = true
	_keep_alive.append(self)

	var combat = GameServiceLocator.get_service("CombatMediator")
	if combat:
		combat.apply_root(_player_node, AIM_TIMEOUT + 1.0)

	_player_node.rpc("_sync_effect", "free_look", true)
	_player_node.rpc("_sync_aiming_mode", _slot_index, true)

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if abs_svc:
		abs_svc.activate_mode(_caster_id, _slot_index, {})

	var cd = GameServiceLocator.get_service("CooldownService")
	if cd and cd.has_method("release_lock"):
		cd.release_lock(_caster_id, _slot_index)

	print("[DevilKnife] Modo apuntado activado | peer: ", _caster_id, " | slot: ", _slot_index)

	await _player_node.get_tree().create_timer(AIM_TIMEOUT).timeout
	if _active:
		print("[DevilKnife] Tiempo de apuntado agotado | peer: ", _caster_id)
		_cancel_aim()


func _launch(direction: Vector2) -> void:
	if not is_instance_valid(_player_node):
		_cancel_aim()
		return

	var combat = GameServiceLocator.get_service("CombatMediator")
	var tp_svc = GameServiceLocator.get_service("TPService")
	var hs = GameServiceLocator.get_service("HitboxService")
	var _cd = GameServiceLocator.get_service("CooldownService")

	if _data and _data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(_caster_id, _data.tp_cost):
			_cancel_aim()
			return

	if combat:
		combat.apply_root(_player_node, 2.0)

	if _data and _data.action_animation != "":
		_player_node.play_ability_animation(_data.action_animation, _slot_index, _player_node.facing_right)

	var anim_dur := _get_anim_duration(_data.action_animation)
	var total_delay := maxf(_data.spawn_delay, anim_dur) if _data else 0.3

	if _data.spawn_delay > 0.0:
		await _player_node.get_tree().create_timer(_data.spawn_delay).timeout
	elif anim_dur > 0.0:
		await _player_node.get_tree().create_timer(anim_dur).timeout

	if not is_instance_valid(_player_node):
		_cancel_aim()
		return

	var proj_dir: Vector2 = direction.normalized()
	if proj_dir == Vector2.ZERO:
		proj_dir = Vector2.RIGHT if _player_node.facing_right else Vector2.LEFT

	if hs:
		hs.create({
			"attacker_id": _caster_id,
			"attacker_node": _player_node,
			"type": "projectile",
			"aim_mode": "fixed",
			"direction": proj_dir,
			"shape_scene": _data.ability_scene,
			"damage": _data.base_damage,
			"attack_type": _data.attack_type if _data else "normal",
			"hit_limit": 1,
			"team_filter": "enemy",
			"lifetime": _data.projectile_lifetime if _data and _data.projectile_lifetime > 0 else 2.0,
			"speed": _data.projectile_speed if _data and _data.projectile_speed > 0 else 600.0,
			"offset": _data.range_ if _data else 80.0,
			"impact_lifetime": 0.3,
			"on_hit": func(target_node: Node) -> void:
				if is_instance_valid(target_node) and combat:
					combat.apply_damage(_player_node, target_node, _data.base_damage if _data else 10, _data.attack_type if _data else "normal")
					if target_node.is_in_group("killer"):
						var status = GameServiceLocator.get_service("StatusEffectService")
						var stun_dur = (_data.stun_duration + _data.evo_status_duration_bonus) if _data else 0.0
						if status and stun_dur > 0.0:
							status.apply(target_node, "stun", { "duration": stun_dur })
		})

	print("[DevilKnife] Cuchillo lanzado | peer: ", _caster_id, " | dir: ", proj_dir)

	await _player_node.get_tree().create_timer(total_delay + 0.5).timeout
	_finish()


func _cancel_aim() -> void:
	if not _active:
		return
	_active = false

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_aiming_mode", _slot_index, false)
		_player_node.rpc("_sync_effect", "free_look", false)

		var combat = GameServiceLocator.get_service("CombatMediator")
		if combat:
			combat.remove_root(_player_node)

		var abs_svc = GameServiceLocator.get_service("AbilityStateService")
		if abs_svc and abs_svc.is_mode_active(_caster_id, _slot_index):
			abs_svc.deactivate_mode(_caster_id, _slot_index)

		var cd = GameServiceLocator.get_service("CooldownService")
		if cd and cd.has_method("release_lock"):
			cd.release_lock(_caster_id, _slot_index)

		_player_node.rpc("_sync_cancel_ability")

	_keep_alive.erase(self)


func _finish() -> void:
	if not _active:
		return
	_active = false

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_aiming_mode", _slot_index, false)
		_player_node.rpc("_sync_effect", "free_look", false)

		var combat = GameServiceLocator.get_service("CombatMediator")
		if combat:
			combat.remove_root(_player_node)

		var abs_svc = GameServiceLocator.get_service("AbilityStateService")
		if abs_svc and abs_svc.is_mode_active(_caster_id, _slot_index):
			abs_svc.deactivate_mode(_caster_id, _slot_index)

		var cd = GameServiceLocator.get_service("CooldownService")
		if cd:
			if cd.has_method("release_lock"):
				cd.release_lock(_caster_id, _slot_index)
			cd.start(_caster_id, _slot_index, _data.cooldown if _data else 10.0)

		_player_node.rpc("_sync_cancel_ability")

	_keep_alive.erase(self)


func _get_anim_duration(anim_name: String) -> float:
	if anim_name == "" or not is_instance_valid(_player_node):
		return 0.3
	var sprite: AnimatedSprite2D = _player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return 0.3
	if not sprite.sprite_frames.has_animation(anim_name):
		return 0.3
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return 0.3
	return frame_count / fps
