extends ChannelledAbilityBase
class_name TopoAbility

const WAVE_COUNT: int = 5
const WAVE_INTERVAL: float = 1.5
const WARNING_TIME: float = 1.0
const SPEAR_HOLD: float = 1.5
const SPEARS_PER_SURVIVOR: int = 8
const WARNING_RADIUS: float = 110.0
const SPEAR_MIN_MULT: float = 2.0
const SPEAR_MAX_MULT: float = 5.0

const SIGNAL_TEX := preload("res://Characters/King/assets/Sprites/señal.png")
const WARNING_SCENE := preload("res://Hitboxes/King/Topo/WarningCircle.tscn")
const SPEAR_SCENE := preload("res://Hitboxes/King/Topo/TopoSpear.tscn")

static var _keep_alive: Array = []

var _active: bool = false
var _total_duration: float = 0.0


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not _cache_common(player_node, data, slot_index):
		return
	_active = true
	if not _consume_tp_or_fail():
		return
	var facing_right: bool = _get_facing_right(direction)
	var grow_time: float = 0.5
	var wave_life: float = WARNING_TIME + grow_time + SPEAR_HOLD + 0.5
	_total_duration = float(WAVE_COUNT - 1) * WAVE_INTERVAL + wave_life + 0.5
	if data.cast_duration > 0.0:
		_total_duration = maxf(_total_duration, data.cast_duration)
	_setup_channelled(data, slot_index, facing_right, _total_duration, _total_duration)
	var status_svc = GameServiceLocator.status_effect
	if status_svc:
		for survivor in _get_alive_survivors():
			if is_instance_valid(survivor):
				status_svc.apply(survivor, "sprint_disabled", { "duration": _total_duration })
	_keep_alive.append(self)
	AbilityBase.register_active(_caster_id, _slot_index, self)
	if _cd_svc and _cd_svc.has_method("release_lock"):
		_cd_svc.release_lock(_caster_id, _slot_index)
	_cd_svc.start(_caster_id, _slot_index, data.cooldown)
	for w in range(WAVE_COUNT):
		var delay: float = float(w) * WAVE_INTERVAL
		var tree := player_node.get_tree()
		if tree:
			tree.create_timer(delay).timeout.connect(_spawn_wave.bind(w))
	var tree_fin := player_node.get_tree()
	if tree_fin:
		tree_fin.create_timer(_total_duration).timeout.connect(_finish)
	else:
		await Engine.get_main_loop().create_timer(_total_duration).timeout
		_finish()
	print("[Topo] Habilidad iniciada | peer: ", _caster_id, " | oleadas: ", WAVE_COUNT, " | duración: ", _total_duration)


func _spawn_wave(wave_idx: int) -> void:
	if not _active or not is_instance_valid(_player_node) or not _player_node.get_tree():
		return
	var survivors := _get_alive_survivors()
	if survivors.is_empty():
		survivors = [_player_node]
	for survivor in survivors:
		if not is_instance_valid(survivor):
			continue
		for i in range(SPEARS_PER_SURVIVOR):
			var angle: float = randf() * TAU
			var dist: float = randf_range(220.0, 440.0) if randf() >= 0.3 else randf_range(100.0, 180.0)
			var pos: Vector2 = survivor.global_position + Vector2(dist, 0).rotated(angle)
			_spawn_warning(pos)


func _spawn_warning(pos: Vector2) -> void:
	if not _active or not is_instance_valid(_player_node) or not _player_node.get_tree() or not _player_node.multiplayer.is_server():
		return
	var hs = GameServiceLocator.hitbox
	if not hs:
		return
	# WarningCircle no es hitbox real pero lo spawneamos como projectile custom para replicar vía ProjectileSpawner
	var warning = hs.create({
		"attacker_id": _caster_id,
		"attacker_node": _player_node,
		"type": "projectile",
		"aim_mode": "fixed",
		"direction": Vector2.DOWN,
		"shape_scene": WARNING_SCENE,
		"team_filter": "enemy",
		"lifetime": WARNING_TIME + SPEAR_HOLD + 1.0,
		"speed": 0.0,
		"hit_limit": 0,
		"custom_hitbox": true,
		"position": pos,
	})
	if not warning:
		return
	var circle_duration: float = WARNING_TIME + SPEAR_HOLD + 1.0
	if "radius" in warning:
		warning.radius = WARNING_RADIUS
	if "duration" in warning:
		warning.duration = circle_duration
	elif warning.has_method("set_duration"):
		warning.set_duration(circle_duration)
	var tree2 := _player_node.get_tree()
	if tree2:
		tree2.create_timer(WARNING_TIME).timeout.connect(_spawn_spear.bind(pos))


func _spawn_spear(pos: Vector2) -> void:
	if not _active or not is_instance_valid(_player_node) or not _player_node.get_tree() or not _player_node.multiplayer.is_server():
		return
	var hs = GameServiceLocator.hitbox
	if not hs:
		return
	var spear = hs.create({
		"attacker_id": _caster_id,
		"attacker_node": _player_node,
		"type": "projectile",
		"aim_mode": "fixed",
		"direction": Vector2.DOWN,
		"shape_scene": SPEAR_SCENE,
		"damage": _data.base_damage if _data and _data.base_damage > 0 else 10,
		"attack_type": _data.attack_type if _data else "normal",
		"team_filter": "enemy",
		"hit_limit": 1,
		"lifetime": 4.0,
		"speed": 0.0,
		"custom_hitbox": true,
		"position": pos,
	})
	if not spear:
		return
	var mult: float = float([2, 3, 4, 5].pick_random())
	if spear.has_method("setup_topo"):
		spear.setup_topo(self, _player_node, mult)


func _get_alive_survivors() -> Array:
	var result: Array = []
	if not is_instance_valid(_player_node) or not _player_node.get_tree():
		return result
	for n in _player_node.get_tree().get_nodes_in_group("survivor"):
		if not is_instance_valid(n) or n.health_state != "alive":
			continue
		result.append(n)
	return result


func _finish() -> void:
	if not _active:
		return
	_active = false
	var status_svc = GameServiceLocator.status_effect
	if status_svc:
		for survivor in _get_alive_survivors():
			if is_instance_valid(survivor):
				status_svc.remove_effect(survivor, "sprint_disabled")
	_finish_channelled()
	AbilityBase.unregister_active(_caster_id, _slot_index)
	_keep_alive.erase(self)
	print("[Topo] Finalizada | peer: ", _caster_id)


func _fail_cleanup() -> void:
	_active = false
	AbilityBase.unregister_active(_caster_id, _slot_index)
	super._fail_cleanup()
	print("[Topo] Fallo activación | peer: ", _caster_id)
