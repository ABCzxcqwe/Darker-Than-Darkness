# res://abilities/jevil/Rage/Rage.gd
extends AbilityBase

const RAGE_SLOT_INDEX: int = 4
const RAGE_DURATION: float = 101.0
const RAGE_STAMINA_DRAIN_MULT: float = 0.8
const RAGE_SPEED_MULTIPLIER: float = 1.25
const POST_RAGE_COOLDOWN_FALLBACK: float = 30.0
const EVOLVED_SLOTS: Array[int] = [0, 1, 3]

static var _keep_alive: Array = []

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
		var base_resist: float = _data.rage_stun_resistance_base if _data and _data.rage_stun_resistance_base > 0.0 else 0.5
		var decay_resist: float = _data.rage_stun_resistance_decay if _data and _data.rage_stun_resistance_decay > 0.0 else 0.1
		abs_svc.activate_mode(_caster_id, RAGE_SLOT_INDEX, {
			"stamina_drain_mult": RAGE_STAMINA_DRAIN_MULT,
			"stun_resistance": base_resist,
			"stun_hits": 0,
			"base_resistance": base_resist,
			"decay_resistance": decay_resist,
		})
	var evo = GameServiceLocator.evolution
	if evo:
		for s in EVOLVED_SLOTS:
			evo.evolve_slot(_caster_id, s)
		evo.evolve_slot(_caster_id, RAGE_SLOT_INDEX)
	var combat = GameServiceLocator.combat_mediator
	if combat:
		combat.apply_speed_boost(_player_node, RAGE_DURATION, RAGE_SPEED_MULTIPLIER)
		print("[Rage][LOG] apply_root 2.0 para peer ", _caster_id, " is_server=", _player_node.multiplayer.is_server(), " has_root_before=", GameServiceLocator.status_effect.has_effect(_caster_id, "root") if GameServiceLocator.status_effect else "no_svc")
		combat.apply_root(_player_node, 2.0)
		print("[Rage][LOG] tras apply_root has_root=", GameServiceLocator.status_effect.has_effect(_caster_id, "root") if GameServiceLocator.status_effect else "no_svc", " is_rooted=", GameServiceLocator.status_effect.is_rooted(_caster_id) if GameServiceLocator.status_effect else "no_svc")
	var status = GameServiceLocator.status_effect
	if status:
		print("[Rage][LOG] apply silence 2.0 y immunity 2.0 para peer ", _caster_id)
		status.apply(_player_node, "silence", {"duration": 2.0})
		status.grant_stun_immunity(_caster_id, 2.0)
		print("[Rage][LOG] tras apply silence has_silence=", status.has_effect(_caster_id, "silence"), " has_immunity=", status.has_stun_immunity(_caster_id))
	_player_node.invincible_until = Time.get_ticks_msec() + 2000
	_player_node.rpc("_sync_invincibility", 2000)
	print("[Rage][LOG] invincible_until=", _player_node.invincible_until, " now=", Time.get_ticks_msec())
	if _player_node.has_method("play_ability_animation"):
		_player_node.play_ability_animation("idle_r", _slot_index, _player_node.facing_right)
	else:
		var spr = _player_node.get_node_or_null("AnimatedSprite2D")
		if spr:
			spr.play("idle_r")
	_keep_alive.append(self)
	var _captured_peer := _caster_id
	var _captured_node := _player_node
	print("[Rage][LOG] programando timer 2s para quitar root/silence peer ", _captured_peer)
	var _root_tree := _player_node.get_tree()
	if _root_tree:
		_root_tree.create_timer(2.0).timeout.connect(func() -> void:
			print("[Rage][LOG] timer 2s disparado peer ", _captured_peer, " valid_player=", is_instance_valid(_captured_node))
			if not is_instance_valid(_captured_node):
				print("[Rage][LOG] player no valido en timeout 2s")
				return
			var st_check = GameServiceLocator.status_effect
			if st_check:
				print("[Rage][LOG] antes remove has_root=", st_check.has_effect(_captured_peer, "root"), " has_silence=", st_check.has_effect(_captured_peer, "silence"), " immunity=", st_check.has_stun_immunity(_captured_peer))
			var c2 = GameServiceLocator.combat_mediator
			if c2:
				print("[Rage][LOG] ejecutando remove_root peer ", _captured_peer)
				c2.remove_root(_captured_node)
			var s2 = GameServiceLocator.status_effect
			if s2:
				print("[Rage][LOG] ejecutando remove silence e immunity 0 peer ", _captured_peer)
				s2.remove_effect(_captured_node, "silence")
				s2.grant_stun_immunity(_captured_peer, 0.0)
			if st_check:
				print("[Rage][LOG] despues remove has_root=", st_check.has_effect(_captured_peer, "root"), " has_silence=", st_check.has_effect(_captured_peer, "silence"))
			if is_instance_valid(_captured_node) and _captured_node.has_method("reset_ability_state"):
				print("[Rage][LOG] liberando AnimState ABILITY -> IDLE para peer ", _captured_peer)
				_captured_node.rpc("_sync_cancel_ability")
		)
	else:
		print("[Rage][LOG] ERROR no se pudo obtener SceneTree para timer 2s")
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
	print("[Rage][LOG] ACTIVADO token ", _rage_token+1, " peer ", _caster_id, " dur ", RAGE_DURATION)
	_rage_token += 1
	var my_token := _rage_token
	var _rage_peer := _caster_id
	var tree := _player_node.get_tree()
	if tree:
		tree.create_timer(RAGE_DURATION).timeout.connect(func() -> void:
			print("[Rage][LOG] timer RAGE_DURATION disparado token ", my_token, " current ", _rage_token, " is_mode_active=", GameServiceLocator.ability_state.is_mode_active(_rage_peer, RAGE_SLOT_INDEX) if GameServiceLocator.ability_state else "no_svc")
			if _rage_token == my_token: _end_rage()
		)


func _on_lms_activated(_survivor_node: Node, _killer_node: Node, _duration: float) -> void:
	_end_rage()


func _end_rage() -> void:
	print("[Rage][LOG] _end_rage llamado peer ", _caster_id, " token ", _rage_token)
	var abs_svc = GameServiceLocator.ability_state
	if not abs_svc or not abs_svc.is_mode_active(_caster_id, RAGE_SLOT_INDEX):
		print("[Rage][LOG] _end_rage abortado no activo peer ", _caster_id)
		return
	print("[Rage][LOG] _end_rage procediendo peer ", _caster_id)
	_rage_token += 1
	abs_svc.deactivate_mode(_caster_id, RAGE_SLOT_INDEX)
	var st_svc = GameServiceLocator.status_effect
	if st_svc and st_svc.has_method("clear_rage_resistance"):
		st_svc.clear_rage_resistance(_caster_id)
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
		if _player_node.has_method("reset_ability_state"):
			_player_node.rpc("_sync_cancel_ability")
		else:
			var spr2 = _player_node.get_node_or_null("AnimatedSprite2D")
			if spr2 and spr2.sprite_frames and spr2.sprite_frames.has_animation("idle_horizontal"):
				_player_node.rpc("_sync_ability_anim", "idle_horizontal", _player_node.active_ability_slot)
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
	_keep_alive.erase(self)
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
