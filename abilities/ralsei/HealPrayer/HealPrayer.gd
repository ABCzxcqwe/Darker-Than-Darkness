# res://abilities/ralsei/HealPrayer/HealPrayer.gd
# Canalización de rezo: Ralsei queda plantado 4 s y cada segundo cura
# a UN solo aliado dentro del área (el de menor HP relativo).
# Recibir daño/stun después del primer tick corta la habilidad.
extends AbilityBase

const CAST_TIME: float = 0.3
const CHANNEL_DURATION: float = 4.0
const CHANNEL_END: float = 4.3
const TICK_COUNT: int = 4
const TICK_INTERVAL: float = 1.0
const FIRST_TICK_DELAY: float = 1.0
const RADIUS: float = 220.0
const IFRAME_TIME: float = 1.0
const CANCEL_COOLDOWN_FALLBACK: float = 5.0

static var _keep_alive: Array = []

var _caster_id: int = -1
var _player_node: Node = null
var _data: AbilityData = null
var _slot_index: int = -1
var _active := false
var _guard_until: int = 0
var _iframe_until: int = 0
var _iframe_ours := false
var _last_hp: int = 0


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[HealPrayer] player_node inválido.")
		return
	if not player_node.multiplayer.is_server():
		return

	_caster_id = player_node.get_multiplayer_authority()
	_player_node = player_node
	_data = data
	_slot_index = slot_index if slot_index >= 0 else 1
	_active = true
	_last_hp = int(player_node.health)

	var health_svc = GameServiceLocator.health
	if not health_svc:
		push_error("[HealPrayer] HealthService no disponible.")
		_fail_cleanup()
		return

	var tp_svc = GameServiceLocator.tp
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(_caster_id, data.tp_cost):
			push_warning("[HealPrayer] consume_tp falló para peer ", _caster_id)
			_fail_cleanup()
			return

	# I-frames + inmunidad a stun hasta el primer tick.
	var now := Time.get_ticks_msec()
	_guard_until = now + int(IFRAME_TIME * 1000.0)
	_iframe_until = _guard_until
	_iframe_ours = int(player_node.invincible_until) < _guard_until
	if _iframe_ours:
		player_node.invincible_until = _guard_until
	var iframe_remaining := int(player_node.invincible_until) - now
	if iframe_remaining > 0:
		player_node.rpc("_sync_invincibility", iframe_remaining)

	var status_svc = GameServiceLocator.status_effect
	if status_svc and status_svc.has_method("grant_stun_immunity"):
		status_svc.grant_stun_immunity(_caster_id, IFRAME_TIME)

	var combat = GameServiceLocator.combat_mediator
	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, _slot_index, player_node.facing_right)
		player_node.rpc("_sync_ability_hold", true)

	if combat:
		combat.apply_root(player_node, CHANNEL_END)

	player_node.rpc("_rpc_heal_field", true, RADIUS, CHANNEL_END)
	if player_node.multiplayer.is_server():
		AudioManager.play_sfx_networked.rpc(
			SfxId.SPELLCAST, player_node.global_position.x, player_node.global_position.y)

	_keep_alive.append(self)
	AbilityBase.register_active(_caster_id, _slot_index, self)

	if health_svc.has_signal("health_changed"):
		if not health_svc.health_changed.is_connected(_on_health_changed):
			health_svc.health_changed.connect(_on_health_changed)
	if combat and combat.has_signal("stun_applied"):
		if not combat.stun_applied.is_connected(_on_stun_applied):
			combat.stun_applied.connect(_on_stun_applied)

	var tree := player_node.get_tree()
	if tree == null:
		_finish()
		return

	# Ticks en 1.0, 2.0, 3.0 y 4.0 s.
	for i in TICK_COUNT:
		var delay: float = FIRST_TICK_DELAY + float(i) * TICK_INTERVAL
		tree.create_timer(delay).timeout.connect(_tick)
	tree.create_timer(CHANNEL_END).timeout.connect(_finish)

	print("[HealPrayer] Canal iniciado | peer: ", _caster_id, " | ticks: ", TICK_COUNT)


func _tick() -> void:
	if not _active or not is_instance_valid(_player_node):
		return

	var target := _pick_target()
	if not is_instance_valid(target):
		return

	var amount: int = int(_data.base_heal) if _data and _data.base_heal > 0 else 10
	var healed: int = 0
	var combat = GameServiceLocator.combat_mediator
	if combat and combat.has_method("apply_heal"):
		healed = combat.apply_heal(_player_node, target, amount)
	else:
		var health_svc = GameServiceLocator.health
		if health_svc:
			health_svc.heal(target, amount)
			healed = amount

	if healed > 0:
		AudioManager.play_sfx_networked.rpc(
			SfxId.HEAL, target.global_position.x, target.global_position.y)
		print("[HealPrayer] Tick | caster: ", _caster_id,
			" | target: ", target.get_multiplayer_authority(), " | HP: ", healed)


func _pick_target() -> Node:
	if not is_instance_valid(_player_node):
		return null
	var best: Node = null
	var best_ratio := INF
	var radius_sq := RADIUS * RADIUS
	var caster_pos: Vector2 = _player_node.global_position
	var can_self: bool = _data == null or _data.can_target_self
	var tree := _player_node.get_tree()
	if tree == null:
		return null

	for n in tree.get_nodes_in_group("survivor"):
		if not is_instance_valid(n):
			continue
		if str(n.get("health_state")) != "alive":
			continue
		if not can_self and n == _player_node:
			continue
		if n.global_position.distance_squared_to(caster_pos) > radius_sq:
			continue
		var char_data = n.get("character_data")
		var max_hp: int = 1
		if char_data and "max_health" in char_data:
			max_hp = maxi(int(char_data.max_health), 1)
		var hp: int = int(n.get("health"))
		var ratio := float(hp) / float(max_hp)
		if ratio < best_ratio:
			best_ratio = ratio
			best = n

	return best


func _on_health_changed(peer_id: int, current_hp: int, _max_hp: int) -> void:
	if not _active or peer_id != _caster_id:
		return
	if current_hp < _last_hp:
		_last_hp = current_hp
		# DoT también puede pegar durante los i-frames; ahí no corta.
		if Time.get_ticks_msec() >= _guard_until:
			_interrupt("damage")
	else:
		_last_hp = current_hp


func _on_stun_applied(target_id: int, _duration: float) -> void:
	if not _active or target_id != _caster_id:
		return
	if Time.get_ticks_msec() >= _guard_until:
		_interrupt("stun")


func _finish() -> void:
	if not _active:
		return
	_active = false
	_cleanup()
	var cd = GameServiceLocator.cooldown
	if cd:
		if cd.has_method("release_lock"):
			cd.release_lock(_caster_id, _slot_index)
		var full_cd: float = _data.cooldown if _data else 18.0
		cd.start(_caster_id, _slot_index, full_cd)
	print("[HealPrayer] Canal completado | peer: ", _caster_id)


func _interrupt(reason: String) -> void:
	if not _active:
		return
	_active = false
	_cleanup()
	var cd = GameServiceLocator.cooldown
	if cd:
		if cd.has_method("release_lock"):
			cd.release_lock(_caster_id, _slot_index)
		var cancel_cd: float = _data.cooldown_cancel if _data and _data.cooldown_cancel > 0.0 else CANCEL_COOLDOWN_FALLBACK
		cd.start(_caster_id, _slot_index, cancel_cd)
	print("[HealPrayer] Interrumpido (", reason, ") | peer: ", _caster_id)


func cancel_early() -> void:
	_interrupt("player")


func _cleanup() -> void:
	var health_svc = GameServiceLocator.health
	if health_svc and health_svc.has_signal("health_changed"):
		if health_svc.health_changed.is_connected(_on_health_changed):
			health_svc.health_changed.disconnect(_on_health_changed)

	var combat = GameServiceLocator.combat_mediator
	if combat:
		if combat.has_signal("stun_applied") and combat.stun_applied.is_connected(_on_stun_applied):
			combat.stun_applied.disconnect(_on_stun_applied)
		if is_instance_valid(_player_node):
			combat.remove_root(_player_node)

	if is_instance_valid(_player_node):
		# Si los i-frames eran nuestros y todavía quedan, limpiarlos al cancelar.
		if _iframe_ours and Time.get_ticks_msec() < _iframe_until and _player_node.invincible_until <= _iframe_until:
			_player_node.invincible_until = 0
			_player_node.rpc("_sync_invincibility", 0)
		_player_node.rpc("_rpc_heal_field", false, 0.0, 0.0)
		_player_node.rpc("_sync_ability_hold", false)
		_player_node.rpc("_sync_cancel_ability")

	AbilityBase.unregister_active(_caster_id, _slot_index)
	_keep_alive.erase(self)


func _fail_cleanup() -> void:
	_active = false
	var cd = GameServiceLocator.cooldown
	if cd and cd.has_method("release_lock"):
		cd.release_lock(_caster_id, _slot_index)
	AbilityBase.unregister_active(_caster_id, _slot_index)
	_keep_alive.erase(self)
