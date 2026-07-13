extends AbilityBase

const DIAMOND_COUNT: int = 80
const AOE_RADIUS: float = 1000.0
const DIAMOND_SPEED: float = 600.0
const DIAMOND_LIFETIME: float = 3.0
const SPAWN_INTERVAL: float = 0.08
const RING_SLOT_COUNT: int = 80
const ABILITY_DURATION: float = 6.0

var _active: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _ring_picas: Array = []


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	_player_node = player_node
	_caster_id = player_node.get_multiplayer_authority()
	_data = data
	_slot_index = slot_index
	_active = true

	var tp_svc = GameServiceLocator.tp
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(_caster_id, data.tp_cost):
			_fail_cleanup()
			return

	if data.action_animation != "":
		player_node.play_ability_animation("idle_down", _slot_index, player_node.facing_right)

	var combat = GameServiceLocator.combat_mediator
	if combat:
		combat.apply_root(_player_node, ABILITY_DURATION)

	var status = GameServiceLocator.status_effect
	if status:
		status.grant_stun_immunity(_caster_id, ABILITY_DURATION)

	var target_center = player_node.global_position

	_spawn_ring(target_center)
	_launch_diamonds(target_center)

	var cd = GameServiceLocator.cooldown
	if cd:
		cd.release_lock(_caster_id, _slot_index)
		if _data and _data.cooldown > 0.0:
			cd.start(_caster_id, _slot_index, _data.cooldown)

	player_node.get_tree().create_timer(ABILITY_DURATION).timeout.connect(
		func():
			_finish_ability()
	)

	print("[DiamondRain] Habilidad iniciada | peer: ", _caster_id, " | centro: ", target_center)


func _spawn_ring(center: Vector2) -> void:
	if not is_instance_valid(_player_node):
		return

	var hs = GameServiceLocator.hitbox
	var cmbt = GameServiceLocator.combat_mediator
	var d = _data
	var cid = _caster_id
	var pn = _player_node

	for i in range(RING_SLOT_COUNT):
		var angle = (float(i) / float(RING_SLOT_COUNT)) * TAU
		var pos = center + Vector2(cos(angle), sin(angle)) * AOE_RADIUS

		var config = {
			"attacker_id": cid,
			"attacker_node": pn,
			"type": "projectile",
			"aim_mode": "fixed",
			"direction": Vector2.RIGHT,
			"shape_scene": d.ability_scene if d else null,
			"damage": d.base_damage if d else 10,
			"attack_type": d.attack_type if d else "normal",
			"hit_limit": 0,
			"team_filter": "enemy",
			"lifetime": ABILITY_DURATION,
			"speed": 0.0,
			"offset": 0.0,
			"on_hit": func(target_node: Node) -> void:
				if is_instance_valid(target_node) and cmbt and d:
					cmbt.apply_damage(pn, target_node, d.base_damage, d.attack_type)
		}

		var hitbox = hs.create(config)
		if hitbox:
			hitbox.global_position = pos
			hitbox.rotation = angle
			_ring_picas.append(hitbox)

	print("[DiamondRain] Ring creado con ", _ring_picas.size(), " picas alrededor de ", center)


func _clear_ring() -> void:
	for pica in _ring_picas:
		if is_instance_valid(pica):
			pica.queue_free()
	_ring_picas.clear()


func _launch_diamonds(target_center: Vector2) -> void:
	if not is_instance_valid(_player_node):
		return

	var hs = GameServiceLocator.hitbox
	var cmbt = GameServiceLocator.combat_mediator
	var spawn_altitude = DIAMOND_SPEED * DIAMOND_LIFETIME * 0.5
	var pn := _player_node
	var cid := _caster_id
	var d := _data

	for i in range(DIAMOND_COUNT):
		pn.get_tree().create_timer(i * SPAWN_INTERVAL).timeout.connect(
			func():
				_spawn_diamond(pn, cid, d, hs, cmbt, target_center, spawn_altitude)
		)


func _spawn_diamond(pn: Node, cid: int, d: AbilityData, hs: Node, cmbt: Node, target_center: Vector2, altitude: float) -> void:
	if not is_instance_valid(pn) or not hs:
		return

	var offset_x = randf_range(-AOE_RADIUS, AOE_RADIUS)
	var offset_y = randf_range(-AOE_RADIUS, AOE_RADIUS)
	var spawn_pos = target_center + Vector2(offset_x, offset_y - altitude)

	var dmg = d.base_damage if d else 10
	var atk_type = d.attack_type if d else "normal"

	var config = {
		"attacker_id": cid,
		"attacker_node": pn,
		"type": "projectile",
		"aim_mode": "fixed",
		"direction": Vector2.DOWN,
		"shape_scene": d.ability_scene if d else null,
		"damage": dmg,
		"attack_type": atk_type,
		"hit_limit": 1,
		"team_filter": "enemy",
		"lifetime": DIAMOND_LIFETIME,
		"speed": DIAMOND_SPEED,
		"offset": 0.0,
		"impact_lifetime": 0.3,
		"on_hit": func(target_node: Node) -> void:
			if is_instance_valid(target_node) and cmbt:
				cmbt.apply_damage(pn, target_node, dmg, atk_type)
	}

	var hitbox = hs.create(config)
	if hitbox:
		hitbox.global_position = spawn_pos
		hitbox.rotation = 0.0


func _finish_ability() -> void:
	if not _active:
		return
	_active = false

	_clear_ring()

	var combat = GameServiceLocator.combat_mediator
	if combat and is_instance_valid(_player_node):
		combat.remove_root(_player_node)

	var status = GameServiceLocator.status_effect
	if status:
		status.grant_stun_immunity(_caster_id, 0.0)

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_cancel_ability")

	print("[DiamondRain] Habilidad finalizada | peer: ", _caster_id)


func _fail_cleanup() -> void:
	_active = false
	_clear_ring()
	var cd = GameServiceLocator.cooldown
	if cd:
		cd.release_lock(_caster_id, _slot_index)
	print("[DiamondRain] Fallo en activación | peer: ", _caster_id)
