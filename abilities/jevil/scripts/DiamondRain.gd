extends AbilityBase

const HITBOX_SCRIPT := preload("res://Hitboxes/Hitbox.gd")

const CHARGE_DURATION: float = 0.5
const STUN_POLL_INTERVAL: float = 0.1
const AOE_RADIUS: float = 1000.0
const DIAMOND_SPEED: float = 600.0
const DIAMOND_LIFETIME: float = 3.0
const SPAWN_INTERVAL: float = 0.08
const DIAMOND_COLLISION_WIDTH: float = 40.0
const RING_SPACING_RATIO: float = 1.5
const INSIDE_DIAMOND_COUNT: int = 50
const RING_LIFETIME: float = 9.0

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
		combat.apply_root(_player_node, CHARGE_DURATION + RING_LIFETIME)

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

	var cd = GameServiceLocator.get_service("CooldownService")
	if cd:
		cd.release_lock(_caster_id, _slot_index)
		cd.start(_caster_id, _slot_index, _data.cooldown if _data else 15.0)

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_cancel_ability")

	_launch_diamonds()

	print("[DiamondRain] Carga completada | peer: ", _caster_id)


func _spawn_ring_instant() -> void:
	if not is_instance_valid(_player_node):
		return

	var pn := _player_node
	var world = pn.get_tree().root.find_child("World", true, false)
	if not world:
		return
	var container = world.get_node_or_null("Projectiles")
	if not container:
		return

	var cid := _caster_id
	var d := _data

	var spacing = DIAMOND_COLLISION_WIDTH * RING_SPACING_RATIO
	var circumference = 2.0 * PI * AOE_RADIUS
	var ring_count = maxi(int(circumference / spacing), 4)

	for i in range(0, ring_count, 2):
		var angle = (2.0 * PI / ring_count) * i
		_spawn_ring_diamond(pn, cid, d, _target_center, angle)


func _launch_diamonds() -> void:
	if not is_instance_valid(_player_node):
		return

	_spawn_ring_instant()

	var cmbt = GameServiceLocator.get_service("CombatMediator")
	var spawn_altitude = DIAMOND_SPEED * DIAMOND_LIFETIME * 0.5
	var pn := _player_node
	var cid := _caster_id
	var d := _data

	for i in range(INSIDE_DIAMOND_COUNT):
		pn.get_tree().create_timer(i * SPAWN_INTERVAL).timeout.connect(
			func():
				_spawn_falling_diamond(pn, cid, d, cmbt, _target_center, spawn_altitude)
		)


func _spawn_ring_diamond(pn: Node, cid: int, d: AbilityData, target_center: Vector2, angle: float) -> void:
	if not is_instance_valid(pn):
		return

	var world = pn.get_tree().root.find_child("World", true, false)
	if not world:
		return
	var container = world.get_node_or_null("Projectiles")
	if not container:
		return

	var shape_scene = d.ability_scene if d else null
	if not shape_scene:
		return

	var angle_rad = angle
	var offset_x = cos(angle_rad) * AOE_RADIUS
	var offset_y = sin(angle_rad) * AOE_RADIUS
	var spawn_pos = target_center + Vector2(offset_x, offset_y)

	var hitbox = shape_scene.instantiate()
	hitbox.set_script(HITBOX_SCRIPT)

	hitbox.attacker_id = cid
	hitbox.damage = 0
	hitbox.hit_limit = 0
	hitbox.team_filter = "enemy"
	hitbox.lifetime = RING_LIFETIME
	hitbox.speed = 0.1
	hitbox.aim_mode = "fixed"
	hitbox.detect_walls = false

	hitbox.global_position = spawn_pos
	hitbox.set_direction(Vector2.DOWN)
	hitbox.set_multiplayer_authority(1)
	hitbox.collision_layer = 0
	hitbox.collision_mask = 0

	container.add_child(hitbox, true)


func _spawn_falling_diamond(pn: Node, cid: int, d: AbilityData, cmbt: Node, target_center: Vector2, altitude: float) -> void:
	if not is_instance_valid(pn):
		return

	var world = pn.get_tree().root.find_child("World", true, false)
	if not world:
		return
	var container = world.get_node_or_null("Projectiles")
	if not container:
		return

	var shape_scene = d.ability_scene if d else null
	if not shape_scene:
		return

	var ang = randf_range(0, 2.0 * PI)
	var dist = sqrt(randf_range(0, 1.0)) * AOE_RADIUS * 0.9
	var offset_x = cos(ang) * dist
	var offset_y = sin(ang) * dist
	var spawn_pos = target_center + Vector2(offset_x, offset_y - altitude)

	var hitbox = shape_scene.instantiate()
	hitbox.set_script(HITBOX_SCRIPT)

	var dmg = d.base_damage if d else 10
	var atk_type = d.attack_type if d else "normal"

	hitbox.attacker_id = cid
	hitbox.damage = dmg
	hitbox.attack_type = atk_type
	hitbox.hit_limit = 1
	hitbox.team_filter = "enemy"
	hitbox.lifetime = DIAMOND_LIFETIME
	hitbox.speed = DIAMOND_SPEED
	hitbox.aim_mode = "fixed"
	hitbox.detect_walls = false
	hitbox.impact_lifetime = 0.3

	hitbox.on_hit_callback = func(target_node: Node) -> void:
		if is_instance_valid(target_node) and cmbt:
			cmbt.apply_damage(pn, target_node, dmg, atk_type)

	hitbox.global_position = spawn_pos
	hitbox.set_direction(Vector2.DOWN)
	hitbox.set_multiplayer_authority(1)
	hitbox.collision_layer = 32
	hitbox.collision_mask = 8

	container.add_child(hitbox, true)


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
