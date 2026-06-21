extends AbilityBase

const AIM_TIMEOUT: float = 8.0
const DIAMOND_COUNT: int = 40
const AOE_RADIUS: float = 1000.0
const DIAMOND_SPEED: float = 500.0
const DIAMOND_LIFETIME: float = 2.0
const SPAWN_INTERVAL: float = 0.08

var _active: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	print("[DiamondRain] activate() | peer: ", player_node.get_multiplayer_authority() if is_instance_valid(player_node) else -1, " | slot: ", slot_index)
	if not is_instance_valid(player_node):
		return

	_player_node = player_node
	_caster_id = player_node.get_muldastiplayer_authority()
	_data = data
	_slot_index = slot_index

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if abs_svc and abs_svc.is_mode_active(_caster_id, _slot_index):
		print("[DiamondRain] activate() → modo activo detectado, lanzando")
		_launch(direction)
		return

	print("[DiamondRain] activate() → entrando en modo apuntado")
	_enter_aim()


func _enter_aim() -> void:
	print("[DiamondRain] _enter_aim() | peer: ", _caster_id, " | slot: ", _slot_index)
	if not is_instance_valid(_player_node):
		return

	_active = true

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

	_player_node.get_tree().create_timer(AIM_TIMEOUT).timeout.connect(
		func():
			if _active:
				_cancel_aim()
	)


func _launch(direction: Vector2) -> void:
	print("[DiamondRain] _launch() | peer: ", _caster_id, " | dir: ", direction)
	_active = true
	if not is_instance_valid(_player_node):
		_cancel_aim()
		return

	var combat = GameServiceLocator.get_service("CombatMediator")
	var tp_svc = GameServiceLocator.get_service("TPService")

	if _data and _data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(_caster_id, _data.tp_cost):
			_cancel_aim()
			return

	if combat:
		combat.apply_root(_player_node, 2.0)

	if _data and _data.action_animation != "":
		_player_node.play_ability_animation(_data.action_animation, _slot_index, _player_node.facing_right)

	var sprite: AnimatedSprite2D = _player_node.get_node_or_null("AnimatedSprite2D")
	var anim_dur: float = 0.3
	if sprite and sprite.sprite_frames and _data and _data.action_animation != "" and sprite.sprite_frames.has_animation(_data.action_animation):
		anim_dur = sprite.sprite_frames.get_frame_count(_data.action_animation) / sprite.sprite_frames.get_animation_speed(_data.action_animation)

	var pn := _player_node
	var cid := _caster_id
	var sid := _slot_index
	var d := _data
	var dir := direction

	_player_node.get_tree().create_timer(anim_dur).timeout.connect(
		func():
			_on_anim_timer(pn, cid, sid, d, dir)
	)


func _on_anim_timer(pn: Node, cid: int, _sid: int, d: AbilityData, dir: Vector2) -> void:
	print("[DiamondRain] _on_anim_timer() | peer: ", cid)
	if not is_instance_valid(pn):
		_cancel_aim()
		return

	var hs = GameServiceLocator.get_service("HitboxService")
	if not hs:
		_finish()
		return

	var proj_dir: Vector2 = dir.normalized()
	if proj_dir == Vector2.ZERO:
		proj_dir = Vector2.RIGHT if pn.facing_right else Vector2.LEFT

	var target_range: float = d.range_ if d and d.range_ > 0.0 else 500.0
	var target_center: Vector2 = pn.global_position + proj_dir * target_range

	var cmbt = GameServiceLocator.get_service("CombatMediator")

	var spawn_altitude = DIAMOND_SPEED * DIAMOND_LIFETIME * 0.5

	for i in range(DIAMOND_COUNT):
		pn.get_tree().create_timer(i * SPAWN_INTERVAL).timeout.connect(
			func():
				_spawn_diamond(pn, cid, d, hs, cmbt, target_center, spawn_altitude)
		)

	var total_dur = (DIAMOND_COUNT - 1) * SPAWN_INTERVAL + DIAMOND_LIFETIME
	pn.get_tree().create_timer(total_dur).timeout.connect(
		func():
			_finish()
	)


func _spawn_diamond(pn: Node, cid: int, d: AbilityData, hs: Node, cmbt: Node, target_center: Vector2, altitude: float) -> void:
	if not is_instance_valid(pn) or not hs:
		return

	var offset_x = randf_range(-AOE_RADIUS, AOE_RADIUS)
	var offset_y = randf_range(-AOE_RADIUS, AOE_RADIUS)
	var spawn_pos = target_center + Vector2(offset_x, offset_y - altitude)

	var fall_dir = Vector2.DOWN
	var dmg = d.base_damage if d else 20
	var atk_type = d.attack_type if d else "normal"
	var scene = d.ability_scene if d else null

	var config = {
		"attacker_id": cid,
		"attacker_node": pn,
		"type": "projectile",
		"aim_mode": "fixed",
		"direction": fall_dir,
		"shape_scene": scene,
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


func _cancel_aim() -> void:
	print("[DiamondRain] _cancel_aim() | peer: ", _caster_id, " | _active: ", _active)
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


func _finish() -> void:
	print("[DiamondRain] _finish() | peer: ", _caster_id, " | _active: ", _active)
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
			cd.start(_caster_id, _slot_index, _data.cooldown if _data else 15.0)

		_player_node.rpc("_sync_cancel_ability")
