extends Node

# { peer_id: target_peer_id } — target pendiente de selección contextual.
var _pending_targets: Dictionary = {}


func set_pending_target(caster_peer_id: int, target_peer_id: int) -> void:
	_pending_targets[caster_peer_id] = target_peer_id
	print("[AbilityRouter] Target pendiente registrado | caster: ", caster_peer_id,
		  " -> target: ", target_peer_id)


func _consume_pending_target(caster_peer_id: int) -> int:
	if not _pending_targets.has(caster_peer_id):
		return -1
	var target: int = _pending_targets[caster_peer_id]
	_pending_targets.erase(caster_peer_id)
	return target


func _ready() -> void:
	print("[AbilityRouter] listo.")


func _dispatch_with_target(slot_index: int, target_peer_id: int, caster_id: int) -> void:
	var player_node := _get_player_node(caster_id)
	if not player_node:
		return

	var char_data: CharacterData = player_node.character_data
	if not char_data or slot_index < 0 or slot_index >= char_data.ability_slots.size():
		return

	var ability_data: AbilityData = char_data.ability_slots[slot_index]
	if not ability_data or not ability_data.ability_script:
		return

	var status = GameServiceLocator.status_effect
	if status:
		if status.is_silenced(caster_id):
			return
		if status.is_stunned(caster_id) and not ability_data.can_use_while_stunned:
			return

	var cd = GameServiceLocator.cooldown
	if cd and not cd.is_ready(caster_id, slot_index):
		return

	if cd and cd.has_method("start_lock"):
		if not cd.is_ready(caster_id, slot_index):
			var remaining = cd.get_remaining(caster_id, slot_index)
			if remaining == -1.0:
				push_warning("[AbilityRouter] Lock huérfano detectado en _dispatch_with_target | peer: ", caster_id, " slot: ", slot_index, " — liberando.")
				cd.release_lock(caster_id, slot_index)
		cd.start_lock(caster_id, slot_index)

	var handler: AbilityBase = ability_data.ability_script.new()
	handler.pending_target_peer = target_peer_id
	handler.activate(player_node, ability_data, Vector2.ZERO, slot_index)

	print("[AbilityRouter] '", ability_data.display_name, "' despachado directo | peer: ", caster_id,
		  " | slot: ", slot_index, " | target: ", target_peer_id)

	# Notificación centralizada también para dispatch con target
	var char_data2: CharacterData = player_node.character_data
	if char_data2 and slot_index >= 0 and slot_index < char_data2.ability_slots.size():
		var base2: AbilityData = char_data2.ability_slots[slot_index]
		_notify_slot_updated(caster_id, slot_index, ability_data, base2 if base2 else ability_data)


@rpc("any_peer", "reliable")
func request_ability(slot_index: int, direction: Vector2) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()

	# Si el servidor se envía a sí mismo (call_local), sender_id es 0
	var peer_id: int = sender_id if sender_id != 0 else multiplayer.get_unique_id()

	if sender_id != 0 and sender_id != peer_id:
		push_warning("[AbilityRouter] Rechazado: sender ", sender_id, " != peer ", peer_id)
		return

	_process_request(slot_index, direction, peer_id)


func _process_request(slot_index: int, direction: Vector2, peer_id: int) -> void:
	if not _validate_game_active():
		return

	var player_node := _validate_player(peer_id)
	if not player_node:
		return

	var char_data := _validate_character_data(player_node, peer_id)
	if not char_data:
		return

	if not _validate_alive(player_node):
		return

	var base_data := _validate_slot(slot_index, char_data, peer_id)
	if not base_data:
		return

	# ── Fase 2: solo el slot en fase 2 acepta input (M1 = fase 2, X = cancelar
	# vía cancel_aim). Cualquier otro slot se ignora mientras haya fase 2 activa.
	var fase2_entry: int = _get_fase2_entry_slot(peer_id)
	if fase2_entry >= 0:
		if slot_index != fase2_entry:
			return
		var abs_mode = GameServiceLocator.ability_state
		var md: Dictionary = abs_mode.get_mode_data(peer_id, fase2_entry) if abs_mode else {}
		# La fase CHANNEL no acepta un nuevo disparo: se cancela con X.
		if String(md.get("phase", "aim")) != "aim":
			print("[AbilityRouter] Fase2 en canalización; disparo ignorado.")
			return
		# Carga mínima validada también en servidor (el cliente puede mentir).
		if Time.get_ticks_msec() < int(md.get("charge_ready_ms", 0)):
			print("[AbilityRouter] Fase2 aún cargando; disparo ignorado.")
			return

	# M1 durante fase 2 es disparo, nunca cancelación por "misma tecla".
	if fase2_entry < 0 and _maybe_cancel_active_ability(peer_id, player_node, slot_index, base_data):
		return

	var evolution_service: Node = GameServiceLocator.evolution
	var lms_svc: Node = GameServiceLocator.lms
	var resolve := _resolve_ability_version(peer_id, slot_index, base_data, evolution_service, lms_svc)
	var ability_data: AbilityData = resolve["ability_data"]
	var is_evolved: bool = resolve["is_evolved"]
	var lms_wants_evolve: bool = resolve["lms_wants_evolve"]

	var cd = GameServiceLocator.cooldown
	if not _validate_cooldown(peer_id, slot_index, cd):
		return

	var status = GameServiceLocator.status_effect
	if not _validate_status_effects(peer_id, base_data, status):
		return

	var abs_svc = GameServiceLocator.ability_state
	var tp_result := _validate_tp(peer_id, ability_data, slot_index, base_data, abs_svc, lms_svc, is_evolved, lms_wants_evolve)
	if not tp_result["valid"]:
		return
	ability_data = tp_result["ability_data"]
	is_evolved = tp_result["is_evolved"]
	lms_wants_evolve = tp_result["lms_wants_evolve"]

	if _handle_animation_state(peer_id, player_node, slot_index, base_data, cd):
		return

	var pending_target: int = _consume_pending_target(peer_id)
	if _handle_context_menu(peer_id, player_node, slot_index, ability_data, pending_target):
		return

	if cd and cd.has_method("start_lock"):
		cd.start_lock(peer_id, slot_index)

	_dispatch(peer_id, player_node, ability_data, slot_index, direction, pending_target)

	if evolution_service:
		_consume_evolution(evolution_service, peer_id, slot_index, is_evolved, lms_wants_evolve)

	_notify_slot_updated(peer_id, slot_index, ability_data, base_data)


func _validate_game_active() -> bool:
	var state = GameServiceLocator.game_state
	if not state or not state.is_in_game():
		return false
	return true


func _validate_player(peer_id: int) -> Node:
	var player_node := _get_player_node(peer_id)
	if not player_node:
		push_warning("[AbilityRouter] Jugador no encontrado para peer ", peer_id)
	return player_node


func _validate_character_data(player_node: Node, peer_id: int) -> CharacterData:
	var char_data: CharacterData = player_node.character_data
	if not char_data:
		push_warning("[AbilityRouter] Jugador ", peer_id, " sin character_data.")
	return char_data


func _validate_alive(player_node: Node) -> bool:
	if player_node.health <= 0:
		return false
	if player_node.health_state != "alive":
		return false
	return true


func _validate_slot(slot_index: int, char_data: CharacterData, _peer_id: int) -> AbilityData:
	if slot_index < 0 or slot_index >= char_data.ability_slots.size():
		push_warning("[AbilityRouter] Slot ", slot_index, " fuera de rango.")
		return null
	var base_data: AbilityData = char_data.ability_slots[slot_index]
	if not base_data:
		return null
	return base_data


func _resolve_ability_version(peer_id: int, slot_index: int, base_data: AbilityData,
		evolution_service: Node, lms_svc: Node) -> Dictionary:
	var stage: int = evolution_service.get_evolved_stage(peer_id, slot_index) if evolution_service else 0
	var lms_wants_evolve: bool = false

	if stage <= 0 and base_data.lms_auto_evolve and base_data.evolved_version:
		if lms_svc and lms_svc.is_lms_active():
			var lms_survivor = lms_svc.get_active_survivor()
			if lms_survivor and lms_survivor.get_multiplayer_authority() == peer_id:
				lms_wants_evolve = true
	if lms_wants_evolve:
		stage = 1

	# Camina la cadena evolved_version `stage` veces (soporta evolución multi-hop).
	var ability_data: AbilityData = base_data
	for i in range(stage):
		if ability_data and ability_data.evolved_version:
			ability_data = ability_data.evolved_version
		else:
			break

	var is_evolved: bool = stage > 0 and ability_data != base_data
	return {
		"ability_data": ability_data,
		"is_evolved": is_evolved,
		"lms_wants_evolve": lms_wants_evolve,
	}


func _validate_cooldown(peer_id: int, slot_index: int, cd: Node) -> bool:
	if cd and not cd.is_ready(peer_id, slot_index):
		print("[AbilityRouter] Bloqueado por cooldown/lock | slot: ", slot_index,
			  " | restante: ", cd.get_remaining(peer_id, slot_index), "s")
		return false
	return true


func _validate_status_effects(peer_id: int, base_data: AbilityData, status: Node) -> bool:
	if status:
		if status.is_silenced(peer_id):
			print("[AbilityRouter] Bloqueado por silence.")
			return false
		if status.is_stunned(peer_id) and not base_data.can_use_while_stunned:
			print("[AbilityRouter] Bloqueado por stun.")
			return false
	return true


func _validate_tp(peer_id: int, ability_data: AbilityData, slot_index: int,
		base_data: AbilityData, abs_svc: Node, lms_svc: Node,
		is_evolved: bool, lms_wants_evolve: bool) -> Dictionary:
	var effective_tp_cost: float = _resolve_tp_cost(ability_data, peer_id, slot_index, abs_svc)

	if effective_tp_cost <= 0.0:
		return {"valid": true, "ability_data": ability_data, "is_evolved": is_evolved, "lms_wants_evolve": lms_wants_evolve}

	var tp_svc = GameServiceLocator.tp
	if tp_svc and tp_svc.get_tp_for_peer(peer_id) < effective_tp_cost:
		var is_permanent: bool = base_data.evolved_version != null and base_data.evolved_version.evolution_consume == 1

		if is_permanent:
			return {"valid": false, "ability_data": ability_data, "is_evolved": is_evolved, "lms_wants_evolve": lms_wants_evolve}

		if lms_wants_evolve:
			is_evolved = false
			lms_wants_evolve = false
			ability_data = base_data
			effective_tp_cost = _resolve_tp_cost(base_data, peer_id, slot_index, abs_svc)
			if tp_svc.get_tp_for_peer(peer_id) < effective_tp_cost:
				return {"valid": false, "ability_data": ability_data, "is_evolved": is_evolved, "lms_wants_evolve": lms_wants_evolve}
		elif is_evolved and base_data.lms_auto_evolve and base_data.evolved_version:
			if lms_svc and lms_svc.is_lms_active():
				var lms_survivor = lms_svc.get_active_survivor()
				if lms_survivor and lms_survivor.get_multiplayer_authority() == peer_id:
					is_evolved = false
					ability_data = base_data
					effective_tp_cost = _resolve_tp_cost(base_data, peer_id, slot_index, abs_svc)
					if tp_svc.get_tp_for_peer(peer_id) < effective_tp_cost:
						return {"valid": false, "ability_data": ability_data, "is_evolved": is_evolved, "lms_wants_evolve": lms_wants_evolve}
		else:
			return {"valid": false, "ability_data": ability_data, "is_evolved": is_evolved, "lms_wants_evolve": lms_wants_evolve}

	return {"valid": true, "ability_data": ability_data, "is_evolved": is_evolved, "lms_wants_evolve": lms_wants_evolve}


# ── Cancelación de habilidad activa (toggle del mismo botón) ──────────────

func _maybe_cancel_active_ability(peer_id: int, player_node: Node, slot_index: int,
		base_data: AbilityData) -> bool:
	if not base_data.can_cancel:
		return false
	if player_node.state != 2 or player_node.active_ability_slot != slot_index:
		return false
	var ability: AbilityBase = AbilityBase.find_active_for(player_node, slot_index)
	if not ability:
		# Fallback legacy para instancias que aún no registran en AbilityBase (transición)
		ability = LanzaAbility.find_active_for(player_node, slot_index) if LanzaAbility else null
	if not ability:
		return false
	if ability.has_method("can_cancel_now") and not ability.can_cancel_now():
		print("[AbilityRouter] Cancel bloqueado por grace period | peer: ", peer_id,
			  " | slot: ", slot_index)
		return true
	ability.cancel_early()
	print("[AbilityRouter] Habilidad activa cancelada con la misma tecla | peer: ", peer_id,
		  " | slot: ", slot_index)
	return true


func _handle_animation_state(peer_id: int, player_node: Node, slot_index: int,
		base_data: AbilityData, cd: Node) -> bool:
	var anim_state: int = player_node.state

	# ── Fase 2: la entrada no deja al jugador en estado ABILITY/PREPARE
	# bloqueante (usa root + free_look), así que el disparo/confirmación
	# (mismo slot) siempre pasa este filtro.
	if _get_fase2_entry_slot(peer_id) == slot_index:
		return false

	if anim_state == 1: # PREPARE
		_cancel_ability(peer_id, player_node, slot_index, base_data, cd)
		return true

	if anim_state == 2: # ABILITY
		if slot_index == player_node.active_ability_slot and base_data.can_cancel:
			var ability: AbilityBase = AbilityBase.find_active_for(player_node, slot_index)
			if not ability:
				ability = LanzaAbility.find_active_for(player_node, slot_index) if LanzaAbility else null
			if ability and ability.has_method("can_cancel_now") and not ability.can_cancel_now():
				print("[AbilityRouter] Cancel via _handle_animation_state bloqueado por grace | peer: ", peer_id)
				return true
			_cancel_ability(peer_id, player_node, slot_index, base_data, cd)
		else:
			print("[AbilityRouter] Habilidad en curso no cancelable o slot diferente.")
		return true

	return false


func _handle_context_menu(peer_id: int, player_node: Node, slot_index: int,
		ability_data: AbilityData, pending_target: int) -> bool:
	if ability_data.requires_selection and pending_target == -1:
		_open_context_menu(peer_id, player_node, slot_index, ability_data)
		return true
	return false


func _dispatch(peer_id: int, player_node: Node, ability_data: AbilityData,
		slot_index: int, direction: Vector2, pending_target: int) -> void:
	var ability_script: GDScript = ability_data.ability_script
	if not ability_script:
		push_error("[AbilityRouter] ability_script no asignado en '", ability_data.display_name, "'")
		return

	var handler: AbilityBase = ability_script.new()
	handler.pending_target_peer = pending_target
	handler.activate(player_node, ability_data, direction, slot_index)

	print("[AbilityRouter] '", ability_data.display_name, "' despachado | peer: ", peer_id,
		  " | slot: ", slot_index)


func _consume_evolution(evolution_service: Node, peer_id: int, slot_index: int,
		is_evolved: bool, lms_wants_evolve: bool) -> void:
	# ── Fase 2: la entrada (modo fase2 activo tras el dispatch) NO consume la
	# evolución; se consume al disparar/confirmar (modo ya desactivado).
	var abs_svc: Node = GameServiceLocator.ability_state
	if abs_svc and abs_svc.has_method("is_mode_active") and abs_svc.is_mode_active(peer_id, slot_index):
		var md: Dictionary = abs_svc.get_mode_data(peer_id, slot_index)
		# Solo la fase AIM retiene la evolución. Si ya se disparó y estamos en
		# CHANNEL, la evolución debe consumirse igual que en un disparo normal.
		if md.get("fase2", false) and String(md.get("phase", "aim")) == "aim":
			return
	if lms_wants_evolve:
		evolution_service.evolve_slot(peer_id, slot_index)
		evolution_service.consume_evolution(peer_id, slot_index)
	elif is_evolved:
		evolution_service.consume_evolution(peer_id, slot_index)


# ── Cancelación unificada ───────────────────────────────────────────────────

func _cancel_ability(peer_id: int, player_node: Node, slot_index: int,
		ability_data: AbilityData, cd: Node) -> void:

	var combat = GameServiceLocator.combat_mediator
	if combat:
		combat.remove_root(player_node)

	if cd and cd.has_method("release_lock"):
		cd.release_lock(peer_id, slot_index)

	if cd and cd.has_method("start") and ability_data.cooldown_cancel > 0.0:
		cd.start(peer_id, slot_index, ability_data.cooldown_cancel)

	if ability_data.requires_selection and player_node.state == 2:
		var huds = player_node.get_tree().get_nodes_in_group(GroupNames.GAME_HUD)
		if not huds.is_empty() and huds[0].has_method("cancel_selection"):
			huds[0].cancel_selection()

	player_node.rpc("_sync_cancel_ability")

	print("[AbilityRouter] Habilidad cancelada | peer: ", peer_id,
		  " | slot: ", slot_index, " | nombre: ", ability_data.display_name)


# ── Cancelación de apuntado / canalización ─────────────────────────────────

@rpc("any_peer", "reliable")
func cancel_aim(peer_id: int, slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	# Un cliente solo puede cancelar su propia fase 2.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != peer_id:
		push_warning("[AbilityRouter] cancel_aim rechazado | sender: ", sender, " peer: ", peer_id)
		return

	var cancelled := cancel_fase2(peer_id, slot_index, "player")
	if cancelled:
		print("[AbilityRouter] Fase2 cancelada por jugador | peer: ", peer_id, " | slot: ", slot_index)
	else:
		print("[AbilityRouter] cancel_aim ignorado (lockout/flags/fase inactiva) | peer: ",
			  peer_id, " | slot: ", slot_index)


# ── Menú contextual ─────────────────────────────────────────────────────────

func _open_context_menu(peer_id: int, player_node: Node, slot_index: int,
		ability_data: AbilityData) -> void:

	player_node.rpc_id(peer_id, "_open_ability_selection",
		slot_index,
		ability_data.display_name,
		ability_data.selection_type)

	print("[AbilityRouter] Menú contextual abierto | peer: ", peer_id,
		  " | slot: ", slot_index, " | tipo: ", ability_data.selection_type)


# ── Notificación centralizada a UI ────────────────────────────────────────

func _notify_slot_updated(peer_id: int, slot_index: int, ability_data: AbilityData, base_data: AbilityData) -> void:
	var abs_svc: Node = GameServiceLocator.ability_state
	var evo_svc: Node = GameServiceLocator.evolution
	var relay: Node = GameServiceLocator.get_client_relay()
	if not relay or not relay.has_method("_rpc_ability_slot_updated"):
		return
	var tp: float = _resolve_tp_cost(ability_data, peer_id, slot_index, abs_svc)
	# Para is_scalable usar cooldown dinámico, si no base
	var cd: float = ability_data.cooldown
	if abs_svc and ability_data.is_scalable and abs_svc.has_method("get_dynamic_cooldown"):
		cd = abs_svc.get_dynamic_cooldown(peer_id, slot_index)
	var stage: int = 0
	if evo_svc and evo_svc.has_method("get_evolved_stage"):
		stage = evo_svc.get_evolved_stage(peer_id, slot_index)
	relay.rpc_id(peer_id, "_rpc_ability_slot_updated", slot_index, tp, cd, stage)


# ════════════════════════════════════════════════════════════════════════════
# FASE 2 — ORQUESTACIÓN CENTRAL
#
# Las habilidades no gestionan timers, lockouts, movimiento ni cancelaciones.
# Solo llaman:
#   start_fase2()             al activar la fase 1
#   apply_fase2_fire_iframes() justo al disparar
#   end_fase2_after_fire()    si la habilidad termina al disparar
#   start_fase2_channel()     si empieza una fase CHANNEL
#   abort_fase2()             si el disparo falla antes de empezar
# y, si tienen canalización, implementan on_fase2_channel_stop(reason).
# ════════════════════════════════════════════════════════════════════════════

## Devuelve el slot con modo fase2 activo para el peer, o -1 si no hay.
## El modo se guarda en AbilityStateService con mode_data {"fase2": true}.
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


func _get_fase2_entry_slot(peer_id: int) -> int:
	return get_active_fase2_slot(peer_id)


## Abre la fase 2 (AIM) para una habilidad. Devuelve false si no se pudo abrir.
## El lock del slot debe haberse liberado aquí para que M1 pueda disparar.
func start_fase2(player_node: Node, data: AbilityData, slot_index: int) -> bool:
	if not multiplayer.is_server():
		return false
	if not is_instance_valid(player_node) or not data or not data.has_fase2:
		return false
	if slot_index < 0:
		return false

	var caster_id: int = player_node.get_multiplayer_authority()
	var abs_svc: Node = GameServiceLocator.ability_state
	if not abs_svc:
		push_error("[AbilityRouter] start_fase2 sin AbilityStateService.")
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
	# El Router hizo start_lock(entry) antes del dispatch: se libera para que
	# la fase 2 (mismo slot) quede pulsable. El cooldown real cae al disparar
	# o al cancelar.
	if cd and cd.has_method("release_lock"):
		cd.release_lock(caster_id, slot_index)

	# Movilidad antes que el flag activo: si el cliente recibe el estado activo
	# primero, durante un frame usaría la movilidad por defecto.
	_apply_fase2_movement(player_node, mode, "aim")
	player_node.rpc("_sync_fase2", slot_index, true, "aim",
			data.fase2_charge_time, data.fase2_cancel_lockout)
	player_node.rpc("_sync_effect", "free_look", true)
	player_node.play_ability_animation(pose, slot_index, player_node.facing_right)
	player_node.rpc("_sync_ability_hold", true)

	_connect_fase2_interrupts()
	_schedule_fase2_timeout(caster_id, slot_index, timeout_ms)

	print("[AbilityRouter] Fase2 AIM abierta | peer: ", caster_id, " | slot: ", slot_index,
		  " | movilidad: ", data.fase2_mobility, " | carga: ", data.fase2_charge_time,
		  "s | lockout: ", data.fase2_cancel_lockout, "s")
	return true


## Cierra la fase 2 tras un disparo correcto, sin pisar la animación de disparo
## ni liberar el lock (la habilidad lo mantiene hasta on_hit/on_end).
func end_fase2_after_fire(peer_id: int, slot_index: int, keep_anim: bool = true) -> void:
	var abs_svc: Node = GameServiceLocator.ability_state
	if abs_svc and abs_svc.is_mode_active(peer_id, slot_index):
		abs_svc.update_mode_data(peer_id, slot_index, "fired", true)
	_end_fase2(peer_id, slot_index, 0.0, keep_anim, "fire", false)


## Aborta la fase 2 sin cooldown ni animación de disparo (ej: TP insuficiente).
func abort_fase2(peer_id: int, slot_index: int) -> void:
	var md := _get_fase2_mode(peer_id, slot_index)
	if String(md.get("phase", "aim")) == "channel":
		_notify_channel_stop(peer_id, slot_index, "abort")
	_end_fase2(peer_id, slot_index, 0.0, false, "abort", true)


## Pasa de AIM a CHANNEL tras el disparo. La habilidad que llama a esto debe
## seguir viva y haber registrado su instancia (AbilityBase.register_active)
## para recibir on_fase2_channel_stop().
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

	var player_node := _get_player_node(peer_id)
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
	print("[AbilityRouter] Fase2 CHANNEL iniciada | peer: ", peer_id, " | slot: ", slot_index,
		  " | duración: ", channel_time, "s")
	return true


## Cancela la fase AIM o CHANNEL si la configuración y el lockout lo permiten.
## `reason`: "player" | "damage" | "stun" | "timeout" | "death".
## El DoT nunca debe llegar aquí (HealthService lo filtra).
func cancel_fase2(peer_id: int, slot_index: int, reason: String) -> bool:
	var abs_svc: Node = GameServiceLocator.ability_state
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

	# ── Fase AIM ──
	if reason == "player":
		if not bool(md.get("cancel_on_player", true)):
			return false
		if now < int(md.get("cancel_ready_ms", 0)):
			print("[AbilityRouter] Cancelación en lockout | peer: ", peer_id,
				  " | faltan ", int(md.get("cancel_ready_ms", 0)) - now, "ms")
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
	if not is_instance_valid(player_node) or not multiplayer.is_server():
		return
	var md := _get_fase2_mode(player_node.get_multiplayer_authority(), slot_index)
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
	print("[AbilityRouter] I-frames de disparo | peer: ", player_node.get_multiplayer_authority(),
		  " | ", ms, "ms")


# ── Internos de fase 2 ──────────────────────────────────────────────────────

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

	var locked := mobility == 2 # RESTRICTED
	var move_scale := 1.0
	if mobility == 1: # REDUCED
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
	get_tree().create_timer(delay).timeout.connect(
			_on_fase2_aim_timeout.bind(peer_id, slot_index, deadline_ms))


func _on_fase2_aim_timeout(peer_id: int, slot_index: int, deadline_ms: int) -> void:
	var md := _get_fase2_mode(peer_id, slot_index)
	if md.is_empty():
		return
	if String(md.get("phase", "aim")) != "aim":
		return
	if int(md.get("timeout_deadline_ms", 0)) != deadline_ms:
		return # timer obsoleto (la fase se reinició)
	print("[AbilityRouter] Fase2 AIM timeout | peer: ", peer_id, " | slot: ", slot_index)
	cancel_fase2(peer_id, slot_index, "timeout")


func _schedule_fase2_channel_timeout(peer_id: int, slot_index: int, deadline_ms: int) -> void:
	var delay: float = maxf((deadline_ms - Time.get_ticks_msec()) / 1000.0, 0.0) + 0.05
	get_tree().create_timer(delay).timeout.connect(
			_on_fase2_channel_timeout.bind(peer_id, slot_index, deadline_ms))


func _on_fase2_channel_timeout(peer_id: int, slot_index: int, deadline_ms: int) -> void:
	var md := _get_fase2_mode(peer_id, slot_index)
	if md.is_empty():
		return
	if String(md.get("phase", "aim")) != "channel":
		return
	if int(md.get("channel_deadline_ms", 0)) != deadline_ms:
		return
	print("[AbilityRouter] Fase2 CHANNEL finalizada | peer: ", peer_id, " | slot: ", slot_index)
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
		push_warning("[AbilityRouter] CHANNEL sin instancia registrada | peer: ",
				peer_id, " | slot: ", slot_index)


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
	var player_node := _get_player_node(peer_id)
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
	print("[AbilityRouter] Fase2 cerrada | peer: ", peer_id, " | slot: ", slot_index,
		  " | motivo: ", reason, " | cooldown: ", cooldown,
		  "s | phase: ", String(md.get("phase", "?")))


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


# ── Helpers ─────────────────────────────────────────────────────────────────

func _resolve_tp_cost(ability_data: AbilityData, peer_id: int,
		slot_index: int, abs_svc: Node) -> float:
	if ability_data.is_scalable and abs_svc != null and abs_svc.has_method("get_dynamic_tp_cost"):
		return abs_svc.get_dynamic_tp_cost(peer_id, slot_index)
	# En fase 2 el coste real es el de disparo (la fase 1 siempre cuesta 0).
	if abs_svc != null and abs_svc.has_method("is_mode_active"):
		if abs_svc.is_mode_active(peer_id, slot_index):
			var md: Dictionary = abs_svc.get_mode_data(peer_id, slot_index)
			if md.get("fase2", false) and "fase2_fire_tp_cost" in ability_data:
				return ability_data.fase2_fire_tp_cost
	return ability_data.tp_cost


func _get_player_node(peer_id: int) -> Node:
	return PlayerRegistry.get_player(peer_id)
