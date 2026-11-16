# res://Network/gameplay/ability_router.gd
extends Node
## Autoload de entrada para habilidades. Orquesta validación, contexto, TP y
## Fase 2; las habilidades siguen llamando a AbilityRouter.

const TAG := "AbilityRouter"

# { peer_id: target_peer_id } — target pendiente de selección contextual.
var _pending_targets: Dictionary = {}

var _tp: AbilityTp
var _validator: AbilityValidator
var _fase2: AbilityFase2
var _context: AbilityContext


func _ready() -> void:
	_tp = AbilityTp.new()
	_validator = AbilityValidator.new(self, _tp)
	_fase2 = AbilityFase2.new(self)
	_context = AbilityContext.new(self, _fase2)
	NetLog.info(TAG, "listo.")


func set_pending_target(caster_peer_id: int, target_peer_id: int) -> void:
	_pending_targets[caster_peer_id] = target_peer_id
	NetLog.debug(TAG, "Target pendiente | caster: %d -> target: %d" % [caster_peer_id, target_peer_id])


func _consume_pending_target(caster_peer_id: int) -> int:
	if not _pending_targets.has(caster_peer_id):
		return -1
	var target: int = _pending_targets[caster_peer_id]
	_pending_targets.erase(caster_peer_id)
	return target


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
				NetLog.warn(TAG, "Lock huérfano en _dispatch_with_target | peer: %d slot: %d — liberando." % [caster_id, slot_index])
				cd.release_lock(caster_id, slot_index)
		cd.start_lock(caster_id, slot_index)

	var handler: AbilityBase = ability_data.ability_script.new()
	handler.pending_target_peer = target_peer_id
	handler.activate(player_node, ability_data, Vector2.ZERO, slot_index)

	NetLog.debug(TAG, "'%s' despachado directo | peer: %d | slot: %d | target: %d" % [
		ability_data.display_name, caster_id, slot_index, target_peer_id
	])

	var char_data2: CharacterData = player_node.character_data
	if char_data2 and slot_index >= 0 and slot_index < char_data2.ability_slots.size():
		var base2: AbilityData = char_data2.ability_slots[slot_index]
		_notify_slot_updated(caster_id, slot_index, ability_data, base2 if base2 else ability_data)


@rpc("any_peer", "reliable")
func request_ability(slot_index: int, direction: Vector2) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int = sender_id if sender_id != 0 else multiplayer.get_unique_id()
	if sender_id != 0 and sender_id != peer_id:
		NetLog.warn(TAG, "Rechazado: sender %d != peer %d" % [sender_id, peer_id])
		return
	_process_request(slot_index, direction, peer_id)


func _process_request(slot_index: int, direction: Vector2, peer_id: int) -> void:
	if not _validator.validate_game_active():
		return

	var player_node := _validator.validate_player(peer_id)
	if not player_node:
		return

	var char_data := _validator.validate_character_data(player_node, peer_id)
	if not char_data:
		return

	if not _validator.validate_alive(player_node):
		return

	var base_data := _validator.validate_slot(slot_index, char_data, peer_id)
	if not base_data:
		return

	# Fase 2: solo el slot en fase 2 acepta input. Cualquier otro slot se ignora.
	var fase2_entry: int = _fase2.get_active_fase2_slot(peer_id)
	if fase2_entry >= 0:
		if slot_index != fase2_entry:
			return
		var abs_mode = GameServiceLocator.ability_state
		var md: Dictionary = abs_mode.get_mode_data(peer_id, fase2_entry) if abs_mode else {}
		if String(md.get("phase", "aim")) != "aim":
			NetLog.debug(TAG, "Fase2 en canalización; disparo ignorado.")
			return
		if Time.get_ticks_msec() < int(md.get("charge_ready_ms", 0)):
			NetLog.debug(TAG, "Fase2 aún cargando; disparo ignorado.")
			return

	if fase2_entry < 0 and _context.maybe_cancel_active_ability(peer_id, player_node, slot_index, base_data):
		return

	var evolution_service: Node = GameServiceLocator.evolution
	var lms_svc: Node = GameServiceLocator.lms
	var resolve := _validator.resolve_ability_version(peer_id, slot_index, base_data, evolution_service, lms_svc)
	var ability_data: AbilityData = resolve["ability_data"]
	var is_evolved: bool = resolve["is_evolved"]
	var lms_wants_evolve: bool = resolve["lms_wants_evolve"]

	var cd = GameServiceLocator.cooldown
	if not _validator.validate_cooldown(peer_id, slot_index, cd):
		return

	var status = GameServiceLocator.status_effect
	if not _validator.validate_status_effects(peer_id, base_data, status):
		return

	var abs_svc = GameServiceLocator.ability_state
	var tp_result := _validator.validate_tp(
		peer_id, ability_data, slot_index, base_data, abs_svc, lms_svc, is_evolved, lms_wants_evolve
	)
	if not tp_result["valid"]:
		return
	ability_data = tp_result["ability_data"]
	is_evolved = tp_result["is_evolved"]
	lms_wants_evolve = tp_result["lms_wants_evolve"]

	if _context.handle_animation_state(peer_id, player_node, slot_index, base_data, cd):
		return

	var pending_target: int = _consume_pending_target(peer_id)
	if _context.handle_context_menu(peer_id, player_node, slot_index, ability_data, pending_target):
		return

	if cd and cd.has_method("start_lock"):
		cd.start_lock(peer_id, slot_index)

	_dispatch(peer_id, player_node, ability_data, slot_index, direction, pending_target)

	if evolution_service:
		_consume_evolution(evolution_service, peer_id, slot_index, is_evolved, lms_wants_evolve)

	_notify_slot_updated(peer_id, slot_index, ability_data, base_data)


func _dispatch(
	peer_id: int,
	player_node: Node,
	ability_data: AbilityData,
	slot_index: int,
	direction: Vector2,
	pending_target: int
) -> void:
	var ability_script: GDScript = ability_data.ability_script
	if not ability_script:
		NetLog.error(TAG, "ability_script no asignado en '%s'." % ability_data.display_name)
		return

	var handler: AbilityBase = ability_script.new()
	handler.pending_target_peer = pending_target
	handler.activate(player_node, ability_data, direction, slot_index)
	NetLog.debug(TAG, "'%s' despachado | peer: %d | slot: %d" % [
		ability_data.display_name, peer_id, slot_index
	])


func _consume_evolution(
	evolution_service: Node,
	peer_id: int,
	slot_index: int,
	is_evolved: bool,
	lms_wants_evolve: bool
) -> void:
	# La entrada de Fase 2 NO consume evolución; se consume al disparar/confirmar.
	var abs_svc: Node = GameServiceLocator.ability_state
	if abs_svc and abs_svc.has_method("is_mode_active") and abs_svc.is_mode_active(peer_id, slot_index):
		var md: Dictionary = abs_svc.get_mode_data(peer_id, slot_index)
		if md.get("fase2", false) and String(md.get("phase", "aim")) == "aim":
			return
	if lms_wants_evolve:
		evolution_service.evolve_slot(peer_id, slot_index)
		evolution_service.consume_evolution(peer_id, slot_index)
	elif is_evolved:
		evolution_service.consume_evolution(peer_id, slot_index)


func _notify_slot_updated(
	peer_id: int,
	slot_index: int,
	ability_data: AbilityData,
	_base_data: AbilityData
) -> void:
	var abs_svc: Node = GameServiceLocator.ability_state
	var evo_svc: Node = GameServiceLocator.evolution
	var relay: Node = GameServiceLocator.get_client_relay()
	if not relay or not relay.has_method("_rpc_ability_slot_updated"):
		return

	var tp: float = _tp.resolve_tp_cost(ability_data, peer_id, slot_index, abs_svc)
	var cd: float = ability_data.cooldown
	if abs_svc and ability_data.is_scalable and abs_svc.has_method("get_dynamic_cooldown"):
		cd = abs_svc.get_dynamic_cooldown(peer_id, slot_index)
	var stage: int = 0
	if evo_svc and evo_svc.has_method("get_evolved_stage"):
		stage = evo_svc.get_evolved_stage(peer_id, slot_index)
	relay.rpc_id(peer_id, "_rpc_ability_slot_updated", slot_index, tp, cd, stage)


# ── API pública de Fase 2 (delegada) ─────────────────────────────────

func get_active_fase2_slot(peer_id: int) -> int:
	return _fase2.get_active_fase2_slot(peer_id)


func start_fase2(player_node: Node, data: AbilityData, slot_index: int) -> bool:
	return _fase2.start_fase2(player_node, data, slot_index)


func end_fase2_after_fire(peer_id: int, slot_index: int, keep_anim: bool = true) -> void:
	_fase2.end_fase2_after_fire(peer_id, slot_index, keep_anim)


func abort_fase2(peer_id: int, slot_index: int) -> void:
	_fase2.abort_fase2(peer_id, slot_index)


func start_fase2_channel(peer_id: int, slot_index: int) -> bool:
	return _fase2.start_fase2_channel(peer_id, slot_index)


func cancel_fase2(peer_id: int, slot_index: int, reason: String) -> bool:
	return _fase2.cancel_fase2(peer_id, slot_index, reason)


func get_fase2_damage_reduction(peer_id: int) -> float:
	return _fase2.get_fase2_damage_reduction(peer_id)


func apply_fase2_fire_iframes(player_node: Node, slot_index: int, anim_duration: float) -> void:
	_fase2.apply_fase2_fire_iframes(player_node, slot_index, anim_duration)


@rpc("any_peer", "reliable")
func cancel_aim(peer_id: int, slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != peer_id:
		NetLog.warn(TAG, "cancel_aim rechazado | sender: %d peer: %d" % [sender, peer_id])
		return

	var cancelled := _fase2.cancel_fase2(peer_id, slot_index, "player")
	if cancelled:
		NetLog.debug(TAG, "Fase2 cancelada por jugador | peer: %d | slot: %d" % [peer_id, slot_index])
	else:
		NetLog.debug(TAG, "cancel_aim ignorado | peer: %d | slot: %d" % [peer_id, slot_index])


func _get_player_node(peer_id: int) -> Node:
	return PlayerLifecycleManager.get_player(peer_id)
