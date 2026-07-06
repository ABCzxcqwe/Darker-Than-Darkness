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

	var status = GameServiceLocator.get_service(ServiceNames.STATUS_EFFECT)
	if status:
		if status.is_silenced(caster_id):
			return
		if status.is_stunned(caster_id) and not ability_data.can_use_while_stunned:
			return

	var cd = GameServiceLocator.get_service(ServiceNames.COOLDOWN)
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


@rpc("any_peer", "reliable")
func request_ability(slot_index: int, direction: Vector2) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int   = sender_id if sender_id != 0 else 1

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

	var evolution_service: Node = GameServiceLocator.get_service(ServiceNames.EVOLUTION)
	var lms_svc: Node = GameServiceLocator.get_service(ServiceNames.LMS)
	var resolve := _resolve_ability_version(peer_id, slot_index, base_data, evolution_service, lms_svc)
	var ability_data: AbilityData = resolve["ability_data"]
	var is_evolved: bool = resolve["is_evolved"]
	var lms_wants_evolve: bool = resolve["lms_wants_evolve"]

	var cd = GameServiceLocator.get_service(ServiceNames.COOLDOWN)
	if not _validate_cooldown(peer_id, slot_index, cd):
		return

	var status = GameServiceLocator.get_service(ServiceNames.STATUS_EFFECT)
	if not _validate_status_effects(peer_id, base_data, status):
		return

	var abs_svc = GameServiceLocator.get_service(ServiceNames.ABILITY_STATE)
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


func _validate_game_active() -> bool:
	var state = GameServiceLocator.get_service(ServiceNames.GAME_STATE)
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
	var is_evolved: bool = evolution_service != null and evolution_service.is_evolved(peer_id, slot_index)
	var lms_wants_evolve: bool = false

	if not is_evolved and base_data.lms_auto_evolve and base_data.evolved_version:
		if lms_svc and lms_svc.is_lms_active():
			var lms_survivor = lms_svc.get_active_survivor()
			if lms_survivor and lms_survivor.get_multiplayer_authority() == peer_id:
				lms_wants_evolve = true
	if lms_wants_evolve:
		is_evolved = true

	var ability_data: AbilityData = base_data.evolved_version if (is_evolved and base_data.evolved_version) else base_data
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

	var tp_svc = GameServiceLocator.get_service(ServiceNames.TP)
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


func _handle_animation_state(peer_id: int, player_node: Node, slot_index: int,
		base_data: AbilityData, cd: Node) -> bool:
	var anim_state: int = player_node.state

	if anim_state == 1: # PREPARE
		_cancel_ability(peer_id, player_node, slot_index, base_data, cd)
		return true

	if anim_state == 2: # ABILITY
		if slot_index == player_node.active_ability_slot and base_data.can_cancel:
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
	if lms_wants_evolve:
		evolution_service.evolve_slot(peer_id, slot_index)
		evolution_service.consume_evolution(peer_id, slot_index)
	elif is_evolved:
		evolution_service.consume_evolution(peer_id, slot_index)


# ── Cancelación unificada ───────────────────────────────────────────────────

func _cancel_ability(peer_id: int, player_node: Node, slot_index: int,
		ability_data: AbilityData, cd: Node) -> void:

	var combat = GameServiceLocator.get_service(ServiceNames.COMBAT_MEDIATOR)
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


# ── Cancelación de apuntado ──────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func cancel_aim(peer_id: int, slot_index: int) -> void:
	print("[AbilityRouter] cancel_aim() recibido | peer: ", peer_id, " | slot: ", slot_index)
	var player_node := _get_player_node(peer_id)
	if not player_node:
		print("[AbilityRouter] cancel_aim() → player_node no encontrado")
		return

	var char_data: CharacterData = player_node.character_data
	if not char_data or slot_index < 0 or slot_index >= char_data.ability_slots.size():
		print("[AbilityRouter] cancel_aim() → char_data inválido o slot fuera de rango")
		return

	var ability_data: AbilityData = char_data.ability_slots[slot_index]
	var cd = GameServiceLocator.get_service(ServiceNames.COOLDOWN)
	print("[AbilityRouter] cancel_aim() → datos válidos, procediendo limpieza")

	player_node.rpc("_sync_aiming_mode", slot_index, false)
	player_node.rpc("_sync_effect", "free_look", false)
	print("[AbilityRouter] cancel_aim() → RPCs sync enviados")

	var combat = GameServiceLocator.get_service(ServiceNames.COMBAT_MEDIATOR)
	if combat:
		combat.remove_root(player_node)
		print("[AbilityRouter] cancel_aim() → combat root removido")

	var abs_svc = GameServiceLocator.get_service(ServiceNames.ABILITY_STATE)
	if abs_svc and abs_svc.is_mode_active(peer_id, slot_index):
		abs_svc.deactivate_mode(peer_id, slot_index)
		print("[AbilityRouter] cancel_aim() → modo desactivado")
	else:
		print("[AbilityRouter] cancel_aim() → modo no estaba activo o abs_svc null")

	if cd and cd.has_method("release_lock"):
		cd.release_lock(peer_id, slot_index)
		print("[AbilityRouter] cancel_aim() → lock liberado")

	if cd and cd.has_method("start") and ability_data and ability_data.cooldown_cancel > 0.0:
		cd.start(peer_id, slot_index, ability_data.cooldown_cancel)
		print("[AbilityRouter] cancel_aim() → cooldown_cancel iniciado: ", ability_data.cooldown_cancel)

	player_node.rpc("_sync_cancel_ability")
	print("[AbilityRouter] Apuntado cancelado | peer: ", peer_id, " | slot: ", slot_index)


# ── Menú contextual ─────────────────────────────────────────────────────────

func _open_context_menu(peer_id: int, player_node: Node, slot_index: int,
		ability_data: AbilityData) -> void:

	player_node.rpc_id(peer_id, "_open_ability_selection",
		slot_index,
		ability_data.display_name,
		ability_data.selection_type)

	print("[AbilityRouter] Menú contextual abierto | peer: ", peer_id,
		  " | slot: ", slot_index, " | tipo: ", ability_data.selection_type)


# ── Helpers ─────────────────────────────────────────────────────────────────

func _resolve_tp_cost(ability_data: AbilityData, peer_id: int,
		slot_index: int, abs_svc: Node) -> float:
	if ability_data.is_scalable and abs_svc != null and abs_svc.has_method("get_dynamic_tp_cost"):
		return abs_svc.get_dynamic_tp_cost(peer_id, slot_index)
	return ability_data.tp_cost


func _get_player_node(peer_id: int) -> Node:
	return PlayerRegistry.get_player(peer_id)
