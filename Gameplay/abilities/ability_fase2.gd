class_name AbilityFase2
extends RefCounted
## Orquestación de la Fase 2 (AIM/CHANNEL): timers, lockouts, movimiento,
## cancelaciones e i-frames.
##
## Las habilidades no gestionan timers ni cancelaciones; llaman a los métodos
## públicos de AbilityRouter, que delegan acá.

const TAG := "AbilityFase2"

var _router: Node


func _init(router: Node) -> void:
	_router = router


## Devuelve el slot con modo fase2 activo para el peer, o -1 si no hay.
func get_active_fase2_slot(peer_id: int) -> int:
	var abs_svc: Node = GameServiceLocator.ability_state
	if not abs_svc or not abs_svc.has_method("is_mode_active"):
		return -1
	for slot_index in range(5):
		if abs_svc.is_mode_active(peer_id, slot_index):
			var md: Dictionary = abs_svc.get_mode_data(peer_id, slot_index)
			if md.get("fase2", false):
				return slot_index
	return -1


## Abre la fase 2 (AIM) para una habilidad. Devuelve false si no se pudo abrir.
func start_fase2(player_node: Node, data: AbilityData, slot_index: int) -> bool:
	if not _router.multiplayer.is_server():
		return false
	if not is_instance_valid(player_node) or not data or not data.has_fase2:
		return false
	if slot_index < 0:
		return false

	var caster_id: int = PlayerLifecycleManager.get_owner_peer_id(player_node)
	var abs_svc: Node = GameServiceLocator.ability_state
	if not abs_svc:
		NetLog.error(TAG, "start_fase2 sin AbilityStateService.")
		return false
	if abs_svc.is_mode_active(caster_id, slot_index):
		return false

	var cd = GameServiceLocator.cooldown
	var now := Time.get_ticks_msec()
	var timeout: float = data.fase2_timeout if data.fase2_timeout > 0.0 else 12.0
	var timeout_ms: int = now + int(timeout * 1000.0) if data.fase2_cancel_on_timeout else 0
	var pose: String = data.prepare_animation if data.prepare_animation != "" else "idle_prepare"
	var interrupt_cd: float = data.fase2_interrupt_cd if data.fase2_interrupt_cd > 0.0 else data.fase2_cancel_cd
	var timeout_cd: float = data.fase2_timeout_cd if data.fase2_timeout_cd > 0.0 else data.fase2_cancel_cd

	var mode := {
		"fase2": true,
		"kind": int(data.fase2_kind),
		"entry_slot": slot_index,
		"phase": "aim",
		"started_ms": now,
		"charge_ready_ms": now + int(maxf(data.fase2_charge_time, 0.0) * 1000.0),
		"cancel_ready_ms": now + int(maxf(data.fase2_cancel_lockout, 0.0) * 1000.0),
		"timeout_deadline_ms": timeout_ms,
		"mobility": int(data.fase2_mobility),
		"mobility_scale": data.fase2_mobility_scale,
		"move_animation": data.fase2_move_animation,
		"pose_animation": pose,
		"cancel_on_player": data.fase2_cancel_on_player,
		"cancel_on_damage": data.fase2_cancel_on_damage,
		"cancel_on_stun": data.fase2_cancel_on_stun,
		"cancel_on_timeout": data.fase2_cancel_on_timeout,
		"cancel_cd": data.fase2_cancel_cd,
		"interrupt_cd": interrupt_cd,
		"timeout_cd": timeout_cd,
		"aim_damage_reduction": data.fase2_aim_damage_reduction,
		"fire_iframes_mode": int(data.fase2_fire_iframes_mode),
		"fire_iframes": data.fase2_fire_iframes,
		"fire_iframes_extra": data.fase2_fire_iframes_extra,
		"fire_animation": data.fase2_fire_animation,
		"fire_cooldown": data.fase2_fire_cooldown,
		"fire_cooldown_fail": data.fase2_fire_cooldown_fail,
		"channel_enabled": data.fase2_channel_enabled,
		"channel_time": data.fase2_channel_time,
		"channel_animation": data.fase2_channel_animation,
		"channel_mobility": int(data.fase2_channel_mobility),
		"channel_mobility_scale": data.fase2_channel_mobility_scale,
		"channel_damage_reduction": data.fase2_channel_damage_reduction,
		"channel_cancel_on_player": data.fase2_channel_cancel_on_player,
		"channel_cancel_on_damage": data.fase2_channel_cancel_on_damage,
		"channel_cancel_on_stun": data.fase2_channel_cancel_on_stun,
		"channel_iframes_mode": int(data.fase2_channel_iframes_mode),
		"channel_iframes": data.fase2_channel_iframes,
		"channel_cd": data.fase2_channel_cd,
		"channel_cancel_cd": data.fase2_channel_cancel_cd,
	}

	abs_svc.activate_mode(caster_id, slot_index, mode)
	if cd and cd.has_method("release_lock"):
		cd.release_lock(caster_id, slot_index)

	# Movilidad antes que el flag activo para evitar un frame con movilidad default.
	_apply_fase2_movement(player_node, mode, "aim")
	player_node.rpc("_sync_fase2", slot_index, true, "aim", data.fase2_charge_time, data.fase2_cancel_lockout)
	player_node.rpc("_sync_effect", "free_look", true)
	player_node.play_ability_animation(pose, slot_index, player_node.facing_right)
	player_node.rpc("_sync_ability_hold", true)

	_connect_fase2_interrupts()
	_schedule_fase2_timeout(caster_id, slot_index, timeout_ms)

	NetLog.debug(TAG, "Fase2 AIM abierta | peer: %d | slot: %d | movilidad: %s | carga: %ss | lockout: %ss" % [
		caster_id, slot_index, data.fase2_mobility, data.fase2_charge_time, data.fase2_cancel_lockout
	])
	return true


## Cierra la fase 2 tras un disparo correcto.
func end_fase2_after_fire(peer_id: int, slot_index: int, keep_anim: bool = true) -> void:
	var abs_svc: Node = GameServiceLocator.ability_state
	if abs_svc and abs_svc.is_mode_active(peer_id, slot_index):
		abs_svc.update_mode_data(peer_id, slot_index, "fired", true)
	_end_fase2(peer_id, slot_index, 0.0, keep_anim, "fire", false)


## Aborta la fase 2 sin cooldown ni animación de disparo.
func abort_fase2(peer_id: int, slot_index: int) -> void:
	var md := _get_fase2_mode(peer_id, slot_index)
	if String(md.get("phase", "aim")) == "channel":
		_notify_channel_stop(peer_id, slot_index, "abort")
	_end_fase2(peer_id, slot_index, 0.0, false, "abort", true)


## Pasa de AIM a CHANNEL tras el disparo.
func start_fase2_channel(peer_id: int, slot_index: int) -> bool:
	var abs_svc: Node = GameServiceLocator.ability_state
	var md := _get_fase2_mode(peer_id, slot_index)
	if md.is_empty():
		return false
	if not bool(md.get("channel_enabled", false)):
		return false
	if String(md.get("phase", "aim")) != "aim":
		return false

	var now := Time.get_ticks_msec()
	var channel_time: float = float(md.get("channel_time", 0.0))
	var deadline_ms: int = now + int(channel_time * 1000.0) if channel_time > 0.0 else 0
	abs_svc.update_mode_data(peer_id, slot_index, "phase", "channel")
	abs_svc.update_mode_data(peer_id, slot_index, "channel_started_ms", now)
	abs_svc.update_mode_data(peer_id, slot_index, "channel_deadline_ms", deadline_ms)

	var player_node: Node = _router._get_player_node(peer_id)
	if is_instance_valid(player_node):
		_apply_fase2_movement(player_node, md, "channel")
		player_node.rpc("_sync_fase2", slot_index, true, "channel", 0.0, 0.0)
		var channel_anim: String = String(md.get("channel_animation", ""))
		if channel_anim == "":
			channel_anim = String(md.get("fire_animation", ""))
			if channel_anim != "":
				abs_svc.update_mode_data(peer_id, slot_index, "channel_animation", channel_anim)
		if String(md.get("channel_animation", "")) != "":
			player_node.play_ability_animation(channel_anim, slot_index, player_node.facing_right)
		player_node.rpc("_sync_ability_hold", true)
		_apply_fase2_channel_iframes(player_node, md)

	if channel_time > 0.0:
		_schedule_fase2_channel_timeout(peer_id, slot_index, deadline_ms)

	_connect_fase2_interrupts()
	NetLog.debug(TAG, "Fase2 CHANNEL iniciada | peer: %d | slot: %d | duración: %ss" % [
		peer_id, slot_index, channel_time
	])
	return true


## Cancela AIM o CHANNEL si la configuración y el lockout lo permiten.
func cancel_fase2(peer_id: int, slot_index: int, reason: String) -> bool:
	var md := _get_fase2_mode(peer_id, slot_index)
	if md.is_empty():
		return false

	var phase := String(md.get("phase", "aim"))
	var now := Time.get_ticks_msec()

	if phase == "channel":
		if reason == "player" and not bool(md.get("channel_cancel_on_player", true)):
			return false
		if reason == "damage" and not bool(md.get("channel_cancel_on_damage", true)):
			return false
		if reason == "stun" and not bool(md.get("channel_cancel_on_stun", true)):
			return false
		if reason != "player" and reason != "damage" and reason != "stun" and reason != "death":
			return false
		_finish_fase2_channel(peer_id, slot_index, reason)
		return true

	# Fase AIM.
	if reason == "player":
		if not bool(md.get("cancel_on_player", true)):
			return false
		if now < int(md.get("cancel_ready_ms", 0)):
			NetLog.debug(TAG, "Cancelación en lockout | peer: %d | faltan %dms" % [
				peer_id, int(md.get("cancel_ready_ms", 0)) - now
			])
			return false
	elif reason == "damage":
		if not bool(md.get("cancel_on_damage", false)):
			return false
	elif reason == "stun":
		if not bool(md.get("cancel_on_stun", true)):
			return false
	elif reason == "timeout":
		if not bool(md.get("cancel_on_timeout", true)):
			return false
	elif reason != "death":
		return false

	var cooldown := 0.0
	if reason == "player":
		cooldown = float(md.get("cancel_cd", 0.0))
	elif reason == "timeout":
		cooldown = float(md.get("timeout_cd", 0.0))
	elif reason == "damage" or reason == "stun":
		cooldown = float(md.get("interrupt_cd", 0.0))

	_end_fase2(peer_id, slot_index, cooldown, false, reason, true)
	return true


## Reducción de daño activa por fase 2 (0.0 si no hay fase 2).
func get_fase2_damage_reduction(peer_id: int) -> float:
	var slot_index := get_active_fase2_slot(peer_id)
	if slot_index < 0:
		return 0.0
	var md := _get_fase2_mode(peer_id, slot_index)
	if md.is_empty():
		return 0.0
	if String(md.get("phase", "aim")) == "channel":
		return clampf(float(md.get("channel_damage_reduction", 0.0)), 0.0, 1.0)
	return clampf(float(md.get("aim_damage_reduction", 0.0)), 0.0, 1.0)


## Aplica los i-frames de disparo. `anim_duration` se usa con COVER_ANIMATION.
func apply_fase2_fire_iframes(player_node: Node, slot_index: int, anim_duration: float) -> void:
	if not is_instance_valid(player_node) or not _router.multiplayer.is_server():
		return
	var md := _get_fase2_mode(PlayerLifecycleManager.get_owner_peer_id(player_node), slot_index)
	if md.is_empty():
		return
	var mode: int = int(md.get("fire_iframes_mode", 0))
	if mode == 0:
		return
	var duration: float = float(md.get("fire_iframes", 0.0))
	if mode == 2:
		duration = maxf(anim_duration, 0.0) + maxf(float(md.get("fire_iframes_extra", 0.0)), 0.0)
	if duration <= 0.0:
		return
	var now := Time.get_ticks_msec()
	var remaining: int = maxi(player_node.invincible_until - now, 0)
	var ms: int = maxi(remaining, int(duration * 1000.0))
	player_node.invincible_until = now + ms
	player_node.rpc("_sync_invincibility", ms)
	NetLog.debug(TAG, "I-frames de disparo | peer: %d | %dms" % [
		PlayerLifecycleManager.get_owner_peer_id(player_node), ms
	])


# ── Internos ──

func _get_fase2_mode(peer_id: int, slot_index: int) -> Dictionary:
	var abs_svc: Node = GameServiceLocator.ability_state
	if not abs_svc or not abs_svc.is_mode_active(peer_id, slot_index):
		return {}
	var md: Dictionary = abs_svc.get_mode_data(peer_id, slot_index)
	if not md.get("fase2", false):
		return {}
	return md


func _apply_fase2_movement(player_node: Node, md: Dictionary, phase: String) -> void:
	if not is_instance_valid(player_node):
		return
	var mobility: int = int(md.get("mobility", 2))
	var mobility_scale: float = float(md.get("mobility_scale", 0.5))
	if phase == "channel":
		mobility = int(md.get("channel_mobility", 2))
		mobility_scale = float(md.get("channel_mobility_scale", 0.5))

	var locked := mobility == 2  # RESTRICTED
	var move_scale := 1.0
	if mobility == 1:  # REDUCED
		move_scale = clampf(mobility_scale, 0.0, 1.0)
	elif mobility == 2:
		move_scale = 0.0

	var pose: String = String(md.get("pose_animation", ""))
	if phase == "channel":
		var channel_pose: String = String(md.get("channel_animation", ""))
		if channel_pose != "":
			pose = channel_pose

	player_node.rpc("_sync_fase2_movement", true, move_scale, locked,
			String(md.get("move_animation", "")), pose)


func _schedule_fase2_timeout(peer_id: int, slot_index: int, deadline_ms: int) -> void:
	if deadline_ms <= 0:
		return
	var delay: float = maxf((deadline_ms - Time.get_ticks_msec()) / 1000.0, 0.0) + 0.05
	_router.get_tree().create_timer(delay).timeout.connect(
			_on_fase2_aim_timeout.bind(peer_id, slot_index, deadline_ms))


func _on_fase2_aim_timeout(peer_id: int, slot_index: int, deadline_ms: int) -> void:
	var md := _get_fase2_mode(peer_id, slot_index)
	if md.is_empty():
		return
	if String(md.get("phase", "aim")) != "aim":
		return
	if int(md.get("timeout_deadline_ms", 0)) != deadline_ms:
		return
	NetLog.debug(TAG, "Fase2 AIM timeout | peer: %d | slot: %d" % [peer_id, slot_index])
	cancel_fase2(peer_id, slot_index, "timeout")


func _schedule_fase2_channel_timeout(peer_id: int, slot_index: int, deadline_ms: int) -> void:
	var delay: float = maxf((deadline_ms - Time.get_ticks_msec()) / 1000.0, 0.0) + 0.05
	_router.get_tree().create_timer(delay).timeout.connect(
			_on_fase2_channel_timeout.bind(peer_id, slot_index, deadline_ms))


func _on_fase2_channel_timeout(peer_id: int, slot_index: int, deadline_ms: int) -> void:
	var md := _get_fase2_mode(peer_id, slot_index)
	if md.is_empty():
		return
	if String(md.get("phase", "aim")) != "channel":
		return
	if int(md.get("channel_deadline_ms", 0)) != deadline_ms:
		return
	NetLog.debug(TAG, "Fase2 CHANNEL finalizada | peer: %d | slot: %d" % [peer_id, slot_index])
	_finish_fase2_channel(peer_id, slot_index, "end")


func _finish_fase2_channel(peer_id: int, slot_index: int, reason: String) -> void:
	var md := _get_fase2_mode(peer_id, slot_index)
	if md.is_empty():
		return
	if String(md.get("phase", "aim")) != "channel":
		return

	_notify_channel_stop(peer_id, slot_index, reason)

	var cooldown := 0.0
	if reason == "end":
		cooldown = float(md.get("channel_cd", 0.0))
	elif reason != "death":
		cooldown = float(md.get("channel_cancel_cd", 0.0))

	_end_fase2(peer_id, slot_index, cooldown, false, reason, true)


func _notify_channel_stop(peer_id: int, slot_index: int, reason: String) -> void:
	var ability: AbilityBase = AbilityBase.find_active_for_peer(peer_id, slot_index)
	if ability:
		ability.on_fase2_channel_stop(reason)
	else:
		NetLog.warn(TAG, "CHANNEL sin instancia registrada | peer: %d | slot: %d" % [peer_id, slot_index])


func _apply_fase2_channel_iframes(player_node: Node, md: Dictionary) -> void:
	if not is_instance_valid(player_node):
		return
	var mode: int = int(md.get("channel_iframes_mode", 0))
	if mode == 0:
		return
	var duration: float = float(md.get("channel_iframes", 0.0))
	if mode == 2:
		var channel_time: float = float(md.get("channel_time", 0.0))
		duration = maxf(duration, channel_time)
	if duration <= 0.0:
		return
	var now := Time.get_ticks_msec()
	var remaining: int = maxi(player_node.invincible_until - now, 0)
	var ms: int = maxi(remaining, int(duration * 1000.0))
	player_node.invincible_until = now + ms
	player_node.rpc("_sync_invincibility", ms)


func _end_fase2(peer_id: int, slot_index: int, cooldown: float,
		keep_anim: bool, reason: String, release_lock: bool) -> void:
	var abs_svc: Node = GameServiceLocator.ability_state
	var player_node: Node = _router._get_player_node(peer_id)
	var md := _get_fase2_mode(peer_id, slot_index)

	if abs_svc and abs_svc.is_mode_active(peer_id, slot_index):
		abs_svc.deactivate_mode(peer_id, slot_index)

	if is_instance_valid(player_node):
		player_node.rpc("_sync_fase2", slot_index, false)
		player_node.rpc("_sync_fase2_movement", false, 1.0, false, "", "")
		player_node.rpc("_sync_effect", "free_look", false)
		if keep_anim:
			player_node.rpc("_sync_ability_hold", false)
		else:
			player_node.rpc("_sync_cancel_ability")

	var cd = GameServiceLocator.cooldown
	if release_lock and cd and cd.has_method("release_lock"):
		cd.release_lock(peer_id, slot_index)
	if cooldown > 0.0 and cd and cd.has_method("start"):
		cd.start(peer_id, slot_index, cooldown)

	AbilityBase.unregister_active(peer_id, slot_index)
	NetLog.debug(TAG, "Fase2 cerrada | peer: %d | slot: %d | motivo: %s | cooldown: %ss | phase: %s" % [
		peer_id, slot_index, reason, cooldown, String(md.get("phase", "?"))
	])


func _connect_fase2_interrupts() -> void:
	var combat = GameServiceLocator.combat_mediator
	if not combat:
		return
	if combat.has_signal("stun_applied") and not combat.stun_applied.is_connected(_on_fase2_stun):
		combat.stun_applied.connect(_on_fase2_stun)


func _on_fase2_stun(target_id: int, _duration: float) -> void:
	var slot_index := get_active_fase2_slot(target_id)
	if slot_index < 0:
		return
	cancel_fase2(target_id, slot_index, "stun")
