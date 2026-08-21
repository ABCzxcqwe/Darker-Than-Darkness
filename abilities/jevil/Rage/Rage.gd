# res://abilities/jevil/Rage/Rage.gd
extends AbilityBase

const RAGE_SLOT_INDEX: int = 4
const RAGE_DURATION: float = 101.0
const RAGE_STAMINA_DRAIN_MULT: float = 0.8
const RAGE_SPEED_MULTIPLIER: float = 1.25
const POST_RAGE_COOLDOWN_FALLBACK: float = 30.0
const EVOLVED_SLOTS: Array[int] = [0, 1, 3]

var _caster_id: int = -1
var _player_node: Node = null
var _slot_index: int = -1
var _data: AbilityData = null
var _rage_token: int = 0
var _rage_exits_closed: Array[String] = []


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not player_node.multiplayer.is_server():
		return
	_caster_id = player_node.get_multiplayer_authority()
	_player_node = player_node
	_data = data
	_slot_index = slot_index if slot_index >= 0 else RAGE_SLOT_INDEX
	var abs_svc = GameServiceLocator.ability_state
	if abs_svc and abs_svc.is_mode_active(_caster_id, RAGE_SLOT_INDEX):
		_release_lock()
		return
	var lms = GameServiceLocator.lms
	if lms and lms.is_lms_active():
		_release_lock()
		return
	var stats_svc = GameServiceLocator.match_stats
	if not stats_svc or not stats_svc.consume_rage_charge(_caster_id):
		_release_lock()
		return
	if abs_svc:
		abs_svc.activate_mode(_caster_id, RAGE_SLOT_INDEX, {"stamina_drain_mult": RAGE_STAMINA_DRAIN_MULT})
	var evo = GameServiceLocator.evolution
	if evo:
		for s in EVOLVED_SLOTS:
			evo.evolve_slot(_caster_id, s)
		evo.evolve_slot(_caster_id, RAGE_SLOT_INDEX)
	var combat = GameServiceLocator.combat_mediator
	if combat:
		combat.apply_speed_boost(_player_node, RAGE_DURATION, RAGE_SPEED_MULTIPLIER)
	var timer = GameServiceLocator.timer
	if timer:
		timer.set_paused(true)
		timer.rpc("_rpc_set_paused", true)
	var mec = GameServiceLocator.map_event_coordinator
	if mec:
		_rage_exits_closed = mec.get_active_exits()
		mec.rpc("_rpc_rage_exits_close")
	var cd = GameServiceLocator.cooldown
	if cd:
		cd.release_lock(_caster_id, _slot_index)
		var relay = GameServiceLocator.get_client_relay()
		if relay:
			relay.rpc("_rpc_rage_time", _caster_id, RAGE_DURATION)
	AudioManager.rpc("_rpc_activate_rage_music")
	if is_instance_valid(_player_node):
		_player_node.rpc("_rpc_rage_vfx_show")
		_player_node.rpc("_sync_effect", "rage_blink", true)
	if lms and lms.has_signal("lms_activated"):
		if not lms.lms_activated.is_connected(_on_lms_activated):
			lms.lms_activated.connect(_on_lms_activated)
	_rage_token += 1
	var my_token := _rage_token
	var tree := _player_node.get_tree()
	if tree:
		tree.create_timer(RAGE_DURATION).timeout.connect(func() -> void: if _rage_token == my_token: _end_rage())


func _on_lms_activated(_survivor_node: Node, _killer_node: Node, _duration: float) -> void:
	_end_rage()


func _end_rage() -> void:
	var abs_svc = GameServiceLocator.ability_state
	if not abs_svc or not abs_svc.is_mode_active(_caster_id, RAGE_SLOT_INDEX):
		return
	_rage_token += 1
	abs_svc.deactivate_mode(_caster_id, RAGE_SLOT_INDEX)
	var evo = GameServiceLocator.evolution
	if evo:
		for s in EVOLVED_SLOTS:
			evo.reset_slot(_caster_id, s)
		evo.reset_slot(_caster_id, RAGE_SLOT_INDEX)
	if is_instance_valid(_player_node):
		var combat = GameServiceLocator.combat_mediator
		if combat:
			combat.remove_effect(_player_node, "speed_boost")
		_player_node.rpc("_rpc_rage_vfx_hide")
		_player_node.rpc("_sync_effect", "rage_blink", false)
	var timer = GameServiceLocator.timer
	if timer:
		timer.set_paused(false)
		timer.rpc("_rpc_set_paused", false)
	var mec = GameServiceLocator.map_event_coordinator
	if mec:
		mec.rpc("_rpc_rage_exits_restore")
		_rage_exits_closed.clear()
	var relay = GameServiceLocator.get_client_relay()
	if relay:
		relay.rpc("_rpc_rage_time", _caster_id, 0.0)
	var cd = GameServiceLocator.cooldown
	if cd:
		cd.start(_caster_id, _slot_index, _get_post_cooldown())
	AudioManager.rpc("_rpc_deactivate_rage_music")
	_disconnect_lms()


func _get_post_cooldown() -> float:
	var post_cd: float = _data.cooldown if _data else 0.0
	return post_cd if post_cd > 0.0 else POST_RAGE_COOLDOWN_FALLBACK


func _release_lock() -> void:
	var cd = GameServiceLocator.cooldown
	if cd and cd.has_method("release_lock"):
		cd.release_lock(_caster_id, _slot_index)


func _disconnect_lms() -> void:
	var lms = GameServiceLocator.lms
	if lms and lms.has_signal("lms_activated"):
		if lms.lms_activated.is_connected(_on_lms_activated):
			lms.lms_activated.disconnect(_on_lms_activated)
