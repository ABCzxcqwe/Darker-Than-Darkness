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


## Llamado por Player._submit_ability_selection para evitar el bug de
## get_remote_sender_id() = 0 en llamadas directas.
## peer_id se pasa explícitamente porque esta función se llama directo.
func _submit_ability(slot_index: int, caster_id: int) -> void:
	_process_request(slot_index, Vector2.ZERO, caster_id)


@rpc("any_peer", "reliable")
func request_ability(slot_index: int, direction: Vector2) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int   = sender_id if sender_id != 0 else 1

	if sender_id != 0 and sender_id != peer_id:
		push_warning("[AbilityRouter] Rechazado: sender ", sender_id, " != peer ", peer_id)
		return

	_process_request(slot_index, direction, peer_id)


func _process_request(slot_index: int, direction: Vector2, peer_id: int) -> void:
	# ── 1. ¿Partida activa? ──────────────────────────────────────────────
	var state = GameServiceLocator.get_service("GameStateService")
	if not state or not state.is_in_game():
		return

	# ── 2. ¿El jugador existe? ───────────────────────────────────────────
	var player_node := _get_player_node(peer_id)
	if not player_node:
		push_warning("[AbilityRouter] Jugador no encontrado para peer ", peer_id)
		return

	# ── 3. ¿Tiene CharacterData? ─────────────────────────────────────────
	var char_data: CharacterData = player_node.character_data
	if not char_data:
		push_warning("[AbilityRouter] Jugador ", peer_id, " sin character_data.")
		return

	# ── 4. ¿Está vivo? ───────────────────────────────────────────────────
	if player_node.health <= 0:
		return

	# ── 5. ¿Slot válido? ─────────────────────────────────────────────────
	if slot_index < 0 or slot_index >= char_data.ability_slots.size():
		push_warning("[AbilityRouter] Slot ", slot_index, " fuera de rango.")
		return
	var base_data: AbilityData = char_data.ability_slots[slot_index]
	if not base_data:
		return

	# ── 6. Resolver versión evolucionada / LMS ───────────────────────────
	var evolution_service: Node = GameServiceLocator.get_service("EvolutionService")
	var is_evolved: bool = evolution_service != null and evolution_service.is_evolved(peer_id, slot_index)

	var lms_svc: Node = GameServiceLocator.get_service("LMSService")
	var lms_wants_evolve: bool = false
	if not is_evolved and base_data.lms_auto_evolve and base_data.evolved_version:
		if lms_svc and lms_svc.is_lms_active():
			var lms_survivor = lms_svc.get_active_survivor()
			if lms_survivor and lms_survivor.get_multiplayer_authority() == peer_id:
				lms_wants_evolve = true
	if lms_wants_evolve:
		is_evolved = true

	var ability_data: AbilityData = base_data.evolved_version if (is_evolved and base_data.evolved_version) else base_data

	# ── 7. Cooldown listo? ───────────────────────────────────────────────
	var cd = GameServiceLocator.get_service("CooldownService")
	if cd and not cd.is_ready(peer_id, slot_index):
		var remaining = cd.get_remaining(peer_id, slot_index)
		print("[AbilityRouter] Bloqueado por cooldown | slot: ", slot_index,
			  " | restante: ", remaining, "s")
		return

	# ── 8. ¿Efectos que bloquean? ────────────────────────────────────────
	var status = GameServiceLocator.get_service("StatusEffectService")
	if status:
		if status.is_silenced(peer_id):
			print("[AbilityRouter] Bloqueado por silence.")
			return
		if status.is_stunned(peer_id) and not base_data.can_use_while_stunned:
			print("[AbilityRouter] Bloqueado por stun.")
			return

	# ── 9. ¿TP suficiente? (solo verificar, NO consumir) ─────────────────
	var abs_svc: Node = GameServiceLocator.get_service("AbilityStateService")
	var effective_tp_cost: float = _resolve_tp_cost(ability_data, peer_id, slot_index, abs_svc)

	if effective_tp_cost > 0.0:
		var tp_svc = GameServiceLocator.get_service("TPService")
		if tp_svc and tp_svc.get_tp_for_peer(peer_id) < effective_tp_cost:
			if lms_wants_evolve:
				is_evolved = false
				lms_wants_evolve = false
				ability_data = base_data
				effective_tp_cost = _resolve_tp_cost(base_data, peer_id, slot_index, abs_svc)
				if tp_svc.get_tp_for_peer(peer_id) < effective_tp_cost:
					return
			elif is_evolved and base_data.lms_auto_evolve and base_data.evolved_version:
				if lms_svc and lms_svc.is_lms_active():
					var lms_survivor = lms_svc.get_active_survivor()
					if lms_survivor and lms_survivor.get_multiplayer_authority() == peer_id:
						is_evolved = false
						ability_data = base_data
						effective_tp_cost = _resolve_tp_cost(base_data, peer_id, slot_index, abs_svc)
						if tp_svc.get_tp_for_peer(peer_id) < effective_tp_cost:
							return
			else:
				return

	# ── 10. ¿Existe el script? ──────────────────────────────────────────
	var ability_script: GDScript = ability_data.ability_script
	if not ability_script:
		push_error("[AbilityRouter] ability_script no asignado en '", ability_data.display_name, "'")
		return

	# ── 11. Animación — Cancelación unificada ───────────────────────────
	var anim_state: int = player_node.state

	if anim_state == 2: # PREPARE
		_cancel_ability(peer_id, player_node, slot_index, base_data, cd)
		return

	if anim_state == 1: # ABILITY
		if slot_index == player_node.active_ability_slot and base_data.can_cancel:
			_cancel_ability(peer_id, player_node, slot_index, base_data, cd)
		else:
			print("[AbilityRouter] Habilidad en curso no cancelable o slot diferente.")
		return

	# ── 12. Menú contextual ─────────────────────────────────────────────
	var pending_target: int = _consume_pending_target(peer_id)

	if ability_data.requires_selection and pending_target == -1:
		_open_context_menu(peer_id, player_node, slot_index, ability_data)
		return

	# ── 13. Lockear slot (evita spam) ───────────────────────────────────
	if cd and cd.has_method("start_lock"):
		cd.start_lock(peer_id, slot_index)

	# ── 14. Despachar ───────────────────────────────────────────────────
	var handler: AbilityBase = ability_script.new()
	handler.pending_target_peer = pending_target
	handler.activate(player_node, ability_data, direction, slot_index)

	print("[AbilityRouter] '", ability_data.display_name, "' despachado | peer: ", peer_id,
		  " | slot: ", slot_index, " | evolucionada: ", is_evolved)

	# ── 15. Consumir evolución ──────────────────────────────────────────
	if evolution_service:
		if lms_wants_evolve:
			evolution_service.evolve_slot(peer_id, slot_index)
			evolution_service.consume_evolution(peer_id, slot_index)
		elif is_evolved:
			evolution_service.consume_evolution(peer_id, slot_index)


# ── Cancelación unificada ───────────────────────────────────────────────────

func _cancel_ability(peer_id: int, player_node: Node, slot_index: int,
		ability_data: AbilityData, cd: Node) -> void:

	if cd and cd.has_method("release_lock"):
		cd.release_lock(peer_id, slot_index)

	if cd and cd.has_method("start") and ability_data.cooldown_cancel > 0.0:
		cd.start(peer_id, slot_index, ability_data.cooldown_cancel)

	if ability_data.requires_selection and player_node.state == 2:
		var huds = player_node.get_tree().get_nodes_in_group("game_hud")
		if not huds.is_empty() and huds[0].has_method("cancel_selection"):
			huds[0].cancel_selection()

	player_node.rpc("_sync_cancel_ability")

	print("[AbilityRouter] Habilidad cancelada | peer: ", peer_id,
		  " | slot: ", slot_index, " | nombre: ", ability_data.display_name)


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
	return get_tree().root.find_child(str(peer_id), true, false)
