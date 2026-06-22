extends AbilityBase

const CHARGE_DURATION: float = 2.0
const STUN_POLL_INTERVAL: float = 0.1
const DIAMOND_COUNT: int = 30
const AOE_RADIUS: float = 1000.0
const DIAMOND_SPEED: float = 600.0
const DIAMOND_LIFETIME: float = 3.0
const SPAWN_INTERVAL: float = 0.08

var _active: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _target_center: Vector2 = Vector2.ZERO

func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	_player_node = player_node
	_caster_id = player_node.get_multiplayer_authority()
	_data = data
	_slot_index = slot_index
	_active = true

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

	_target_center = player_node.global_position

	_show_aoe_indicator(_target_center)

	player_node.get_tree().create_timer(CHARGE_DURATION).timeout.connect(
		func():
			_on_charge_complete()
	)
	player_node.get_tree().create_timer(STUN_POLL_INTERVAL).timeout.connect(
		func():
			_check_stun()
	)

	print("[DiamondRain] Carga iniciada | peer: ", _caster_id, " | centro: ", _target_center)


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

	_hide_aoe_indicator()

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

	# TODO: reproducir sonido de fallo
	print("[DiamondRain] Carga cancelada por stun | peer: ", _caster_id)


func _on_charge_complete() -> void:
	if not _active:
		return
	_active = false

	_hide_aoe_indicator()

	var combat = GameServiceLocator.get_service("CombatMediator")
	if combat and is_instance_valid(_player_node):
		combat.remove_root(_player_node)

	var cd = GameServiceLocator.get_service("CooldownService")
	if cd:
		cd.release_lock(_caster_id, _slot_index)
		cd.start(_caster_id, _slot_index, _data.cooldown if _data else 15.0)

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_cancel_ability")

	_launch_diamonds()

	print("[DiamondRain] Carga completada | peer: ", _caster_id)


func _launch_diamonds() -> void:
	if not is_instance_valid(_player_node):
		return

	var hs = GameServiceLocator.get_service("HitboxService")
	var cmbt = GameServiceLocator.get_service("CombatMediator")
	var spawn_altitude = DIAMOND_SPEED * DIAMOND_LIFETIME * 0.5
	var pn := _player_node
	var cid := _caster_id
	var d := _data

	for i in range(DIAMOND_COUNT):
		pn.get_tree().create_timer(i * SPAWN_INTERVAL).timeout.connect(
			func():
				_spawn_diamond(pn, cid, d, hs, cmbt, _target_center, spawn_altitude)
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


func _show_aoe_indicator(center: Vector2) -> void:
	_player_node.rpc("_sync_show_aoe_indicator", center)


func _hide_aoe_indicator() -> void:
	_player_node.rpc("_sync_hide_aoe_indicator")


func _fail_cleanup() -> void:
	_active = false
	var cd = GameServiceLocator.get_service("CooldownService")
	if cd:
		cd.release_lock(_caster_id, _slot_index)
	print("[DiamondRain] Fallo en activación | peer: ", _caster_id)
