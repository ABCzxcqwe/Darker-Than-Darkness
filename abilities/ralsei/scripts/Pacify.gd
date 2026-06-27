extends AbilityBase

const CHARGE_DURATION: float = 1.0
const STUN_POLL_INTERVAL: float = 0.1

var _active: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _area_radius: float = 0.0


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	_player_node = player_node
	_caster_id = player_node.get_multiplayer_authority()
	_data = data
	_slot_index = slot_index
	_active = true
	_area_radius = data.range_ if data.range_ > 0.0 else 300.0

	var tp_svc = GameServiceLocator.get_service("TPService")
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(_caster_id, data.tp_cost):
			_fail_cleanup()
			return

	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, _slot_index, player_node.facing_right)

	var combat = GameServiceLocator.get_service("CombatMediator")
	if combat:
		combat.apply_root(_player_node, CHARGE_DURATION + 0.5)

	if is_instance_valid(_player_node) and _player_node.multiplayer.is_server():
		AudioManager.play_sfx_networked.rpc(SfxId.SPELLCAST, _player_node.global_position.x, _player_node.global_position.y)

	_show_indicator()

	_player_node.get_tree().create_timer(CHARGE_DURATION).timeout.connect(
		func():
			_on_charge_complete()
	)
	_player_node.get_tree().create_timer(STUN_POLL_INTERVAL).timeout.connect(
		func():
			_check_stun()
	)

	print("[Pacify] Carga iniciada | peer: ", _caster_id, " | radio: ", _area_radius)


func _check_stun() -> void:
	if not _active or not is_instance_valid(_player_node):
		return

	var status = GameServiceLocator.get_service("StatusEffectService")
	if status and status.is_stunned(_caster_id):
		_cancel_charge()
		return

	if _active:
		_player_node.get_tree().create_timer(STUN_POLL_INTERVAL).timeout.connect(
			func():
				_check_stun()
		)


func _cancel_charge() -> void:
	if not _active:
		return
	_active = false

	_hide_indicator()

	var combat = GameServiceLocator.get_service("CombatMediator")
	if combat and is_instance_valid(_player_node):
		combat.remove_root(_player_node)

	var cd = GameServiceLocator.get_service("CooldownService")
	if cd:
		cd.release_lock(_caster_id, _slot_index)
		if _data and _data.cooldown_cancel > 0.0:
			cd.start(_caster_id, _slot_index, _data.cooldown_cancel)

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_cancel_ability")

	print("[Pacify] Carga cancelada por stun | peer: ", _caster_id)


func _on_charge_complete() -> void:
	if not _active:
		return
	_active = false

	_hide_indicator()

	var combat = GameServiceLocator.get_service("CombatMediator")
	if not is_instance_valid(_player_node):
		return

	if combat:
		combat.remove_root(_player_node)

	_apply_effects(combat)

	var cd = GameServiceLocator.get_service("CooldownService")
	if cd:
		cd.release_lock(_caster_id, _slot_index)
		cd.start(_caster_id, _slot_index, _data.cooldown if _data else 15.0)

	if is_instance_valid(_player_node):
		AudioManager.play_sfx_networked.rpc(SfxId.PACIFY, _player_node.global_position.x, _player_node.global_position.y)
		_player_node.rpc("_sync_cancel_ability")

	print("[Pacify] Carga completada | peer: ", _caster_id)


func _apply_effects(combat: Node) -> void:
	var center: Vector2 = _player_node.global_position
	var status_svc = GameServiceLocator.get_service("StatusEffectService")
	var slow_dur: float = _data.slow_duration if _data and _data.slow_duration > 0.0 else 3.0
	var slow_mag: float = _data.slow_magnitude if _data and _data.slow_magnitude > 0.0 else 0.3
	var silence_dur: float = _data.stun_duration if _data and _data.stun_duration > 0.0 else 3.0
	var hit_count := 0

	for killer in _player_node.get_tree().get_nodes_in_group("killer"):
		if not is_instance_valid(killer):
			continue
		if killer.get("health_state") == "dead" or killer.get("health_state") == "downed":
			continue

		var dist: float = center.distance_to(killer.global_position)
		if dist <= _area_radius:
			if combat and slow_mag > 0.0:
				combat.apply_slow(killer, slow_dur, slow_mag)
			if status_svc and silence_dur > 0.0:
				status_svc.apply(killer, "silence", { "duration": silence_dur })
			hit_count += 1

	print("[Pacify] Efectos aplicados a ", hit_count, " killers")


func _show_indicator() -> void:
	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_show_pacify_indicator", _player_node.global_position, _area_radius)


func _hide_indicator() -> void:
	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_hide_pacify_indicator")


func _fail_cleanup() -> void:
	_active = false
	var cd = GameServiceLocator.get_service("CooldownService")
	if cd:
		cd.release_lock(_caster_id, _slot_index)
	print("[Pacify] Fallo en activación | peer: ", _caster_id)
