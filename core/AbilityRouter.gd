# res://core/AbilityRouter.gd  (Autoload)
# ============================================================
# AbilityRouter — Valida, resuelve y despacha habilidades.
#
# RESPONSABILIDADES DEL ROUTER:
#   - Validar que la habilidad se puede ejecutar (pasos 1-11).
#   - Verificar (NO consumir) que el jugador tiene TP suficiente.
#   - Resolver la versión correcta (normal / evolucionada / LMS).
#   - Despachar el script de la habilidad.
#
# RESPONSABILIDADES DE LA HABILIDAD (ability script):
#   - Consumir el TP necesario via TPService.consume_tp() o add_tp_custom().
#   - Iniciar su propio cooldown via CooldownService.start() con el slot_index
#     correcto, en el momento que corresponda (al activar, al impactar, al fallar).
#   - Para habilidades escalables: llamar AbilityStateService.register_use()
#     antes de leer get_dynamic_cooldown().
#
# REGLA: El Router nunca consume TP ni inicia cooldowns.
#        Eso es responsabilidad exclusiva de cada script de habilidad.
# ============================================================
extends Node

# { peer_id: target_peer_id } — target pendiente de selección contextual.
# Act (y cualquier habilidad con menú) escribe aquí antes de re-despachar.
# AbilityRouter lo lee en activate() y lo borra inmediatamente después.
var _pending_targets: Dictionary = {}


## API para habilidades con menú contextual.
## La habilidad llama esto ANTES de re-llamar request_ability(),
## para que AbilityRouter pase el target al script sin codificarlo en Vector2.
func set_pending_target(caster_peer_id: int, target_peer_id: int) -> void:
	_pending_targets[caster_peer_id] = target_peer_id
	print("[AbilityRouter] Target pendiente registrado | caster: ", caster_peer_id,
		  " → target: ", target_peer_id)


## Devuelve y limpia el target pendiente. -1 si no había ninguno.
func consume_pending_target(caster_peer_id: int) -> int:
	if not _pending_targets.has(caster_peer_id):
		return -1
	var target: int = _pending_targets[caster_peer_id]
	_pending_targets.erase(caster_peer_id)
	return target


func _ready() -> void:
	print("[AbilityRouter] listo.")


# ── RPC: el cliente llama esto en el servidor ──────────────────────────────
@rpc("any_peer", "reliable")
func request_ability(slot_index: int, direction: Vector2) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int   = sender_id if sender_id != 0 else 1

	# ── 1. ¿Hay partida activa? ──────────────────────────────────────────
	var state = GameServiceLocator.get_service("GameStateService")
	if not state or not state.is_in_game():
		print("[AbilityRouter] Sin partida activa. Bloqueado.")
		return

	# ── 2. ¿El jugador existe? ───────────────────────────────────────────
	var player_node := _get_player_node(peer_id)
	if not player_node:
		push_warning("[AbilityRouter] No se encontró jugador para peer ", peer_id)
		return

	# ── 3. ¿El jugador tiene CharacterData? ─────────────────────────────
	var char_data: CharacterData = player_node.character_data
	if not char_data:
		push_warning("[AbilityRouter] Jugador ", peer_id, " sin character_data.")
		return

	# ── 4. ¿El jugador está vivo? ────────────────────────────────────────
	if player_node.health <= 0:
		print("[AbilityRouter] Jugador ", peer_id, " sin vida. Bloqueado.")
		return

	# ── 4.5. ¿Estado de animación? ───────────────────────────────────────
	# PREPARE (2): la misma tecla cancela la habilidad en preparación.
	# ABILITY (1): solo cancela si la habilidad lo permite.
	var player_anim_state: int = player_node.state
	if player_anim_state == 2: # AnimState.PREPARE
		request_cancel_ability(slot_index)
		return
	if player_anim_state == 1: # AnimState.ABILITY
		if slot_index < char_data.ability_slots.size():
			var slot_data: AbilityData = char_data.ability_slots[slot_index]
			if slot_data and slot_data.can_cancel:
				request_cancel_ability(slot_index)
			else:
				print("[AbilityRouter] Bloqueado: habilidad en curso no cancelable.")
		return

	# ── 5. ¿Tiene algo en ese slot? ─────────────────────────────────────
	if slot_index < 0 or slot_index >= char_data.ability_slots.size():
		push_warning("[AbilityRouter] Slot ", slot_index, " fuera de rango para peer ", peer_id)
		return
	var base_data: AbilityData = char_data.ability_slots[slot_index]
	if not base_data:
		print("[AbilityRouter] Slot ", slot_index, " vacío para peer ", peer_id)
		return

	# ── 6a. Resolver versión: ¿evolucionada manualmente? ────────────────
	var evolution_service: Node = GameServiceLocator.get_service("EvolutionService")
	var is_evolved: bool = evolution_service != null and evolution_service.is_evolved(peer_id, slot_index)

	# ── 6b. LMS auto-evolve ──────────────────────────────────────────────
	# Si la habilidad tiene lms_auto_evolve = true, el LMS está activo para
	# este jugador, y aún no está evolucionada, la forzamos ahora.
	var lms_svc: Node = GameServiceLocator.get_service("LMSService")
	var lms_wants_evolve: bool = false
	if not is_evolved and base_data.lms_auto_evolve and base_data.evolved_version:
		if lms_svc and lms_svc.is_lms_active():
			var lms_survivor: Node = lms_svc.get_active_survivor()
			if lms_survivor and lms_survivor.get_multiplayer_authority() == peer_id:
				lms_wants_evolve = true

	if lms_wants_evolve:
		is_evolved = true

	var ability_data: AbilityData = base_data.evolved_version if (is_evolved and base_data.evolved_version) else base_data

	# ── 7. ¿Cooldown listo? ──────────────────────────────────────────────
	var cd = GameServiceLocator.get_service("CooldownService")
	if cd and not cd.is_ready(peer_id, ability_data.display_name):
		print("[AbilityRouter] Bloqueado por cooldown: ", ability_data.display_name,
			  " | restante: ", cd.get_remaining(peer_id, ability_data.display_name), "s")
		return

	# ── 8. ¿Efectos que bloquean? ────────────────────────────────────────
	var status = GameServiceLocator.get_service("StatusEffectService")
	if status:
		if status.is_silenced(peer_id):
			print("[AbilityRouter] Bloqueado por silence.")
			return
		if status.is_stunned(peer_id) and not ability_data.can_use_while_stunned:
			print("[AbilityRouter] Bloqueado por stun.")
			return

	# ── 8.5. ¿Tiene suficiente TP? (solo verificación, NO consume) ──────
	# El Router verifica que el jugador tenga el TP requerido pero NO lo consume.
	# El consumo es responsabilidad exclusiva del script de cada habilidad.
	# Para habilidades escalables usamos el costo dinámico del AbilityStateService.
	var abs_svc: Node = GameServiceLocator.get_service("AbilityStateService")
	var effective_tp_cost: float = _resolve_tp_cost(ability_data, peer_id, slot_index, abs_svc)

	if effective_tp_cost > 0.0:
		var tp_svc = GameServiceLocator.get_service("TPService")
		if tp_svc:
			if tp_svc.get_tp_for_peer(peer_id) < effective_tp_cost:
				print("[AbilityRouter] TP insuficiente para peer ", peer_id,
					  " | Requiere: ", effective_tp_cost,
					  " | Actual: ", tp_svc.get_tp_for_peer(peer_id))
				# Si el LMS quería evolucionar pero no hay TP, revertimos la intención
				# y verificamos si alcanza para la versión normal.
				if lms_wants_evolve:
					is_evolved = false
					lms_wants_evolve = false
					ability_data = base_data
					effective_tp_cost = _resolve_tp_cost(base_data, peer_id, slot_index, abs_svc)
					if tp_svc.get_tp_for_peer(peer_id) < effective_tp_cost:
						print("[AbilityRouter] TP insuficiente incluso para versión normal. Bloqueado.")
						return
					# Continúa con la versión normal — no retorna
				else:
					return

	# ── 9. ¿Existe el script? ────────────────────────────────────────────
	var ability_script: GDScript = ability_data.ability_script
	if not ability_script:
		push_error("[AbilityRouter] ability_script no asignado en AbilityData para '",
				   ability_data.display_name, "'")
		return

	# ── 10. Instanciar y ejecutar ─────────────────────────────────────────
	# A partir de aquí la habilidad tiene control total:
	# debe consumir su TP y registrar su cooldown internamente.
	var handler: AbilityBase = ability_script.new()
	handler.activate(player_node, ability_data, direction, slot_index)

	print("[AbilityRouter] '", ability_data.display_name, "' despachado para peer ", peer_id,
		  " (", "evolucionada" if is_evolved else "normal", ") | slot: ", slot_index)

	# ── 11. Consumir / forzar evolución ───────────────────────────────────
	if evolution_service:
		if lms_wants_evolve:
			evolution_service.evolve_slot(peer_id, slot_index)
			evolution_service.consume_evolution(peer_id, slot_index)
		elif is_evolved:
			evolution_service.consume_evolution(peer_id, slot_index)


# ── Cancelación ──────────────────────────────────────────────────────────────
@rpc("any_peer", "reliable")
func request_cancel_ability(slot_index: int) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int   = sender_id if sender_id != 0 else 1

	var player_node = _get_player_node(peer_id)
	if not player_node:
		push_warning("[AbilityRouter] Cancel: jugador no encontrado para peer ", peer_id)
		return

	var char_data: CharacterData = player_node.character_data
	if not char_data:
		push_warning("[AbilityRouter] Cancel: jugador ", peer_id, " sin character_data.")
		return

	if slot_index < 0 or slot_index >= char_data.ability_slots.size():
		push_warning("[AbilityRouter] Cancel: slot ", slot_index, " fuera de rango.")
		return

	var ability_data: AbilityData = char_data.ability_slots[slot_index]
	if not ability_data:
		print("[AbilityRouter] Cancel: slot ", slot_index, " vacío.")
		return

	# Acepta cancelación desde PREPARE (2) o ABILITY (1)
	var anim_state: int = player_node.state
	if anim_state != 1 and anim_state != 2:
		print("[AbilityRouter] Cancel ignorada: jugador no está en ABILITY ni PREPARE.")
		return

	# PREPARE no requiere can_cancel — siempre se puede cancelar el menú contextual
	if anim_state == 1 and not ability_data.can_cancel:
		print("[AbilityRouter] Cancel rechazada: ", ability_data.display_name, " no es cancelable.")
		return

	# Cerrar menú contextual si estaba abierto (estado PREPARE)
	if anim_state == 2:
		var huds := player_node.get_tree().get_nodes_in_group("game_hud")
		if not huds.is_empty() and huds[0].has_method("cancel_selection"):
			huds[0].cancel_selection()

	# Aplicar cooldown de cancelación — este sí lo maneja el Router
	# porque la cancelación es iniciada por el propio Router, no por la habilidad.
	var cd = GameServiceLocator.get_service("CooldownService")
	if cd:
		cd.start(peer_id, ability_data.display_name, ability_data.cooldown_cancel, slot_index)

	# Resetear estado FSM en todos los peers
	player_node.rpc("_sync_cancel_ability")

	print("[AbilityRouter] Habilidad cancelada: ", ability_data.display_name,
		  " | peer: ", peer_id, " | estado: ", "PREPARE" if anim_state == 2 else "ABILITY",
		  " | cd_cancel: ", ability_data.cooldown_cancel, "s")


# ── Helpers ────────────────────────────────────────────────────────────────

## Devuelve el costo de TP efectivo para la verificación del Router.
## Habilidades escalables leen de AbilityStateService; el resto del recurso.
## NOTA: Este valor es solo para verificar — la habilidad decide cuándo y cuánto consumir.
func _resolve_tp_cost(
	ability_data: AbilityData,
	peer_id: int,
	slot_index: int,
	abs_svc: Node
) -> float:
	if ability_data.is_scalable and abs_svc:
		return abs_svc.get_dynamic_tp_cost(peer_id, slot_index)
	return ability_data.tp_cost


func _get_player_node(peer_id: int) -> Node:
	return get_tree().root.find_child(str(peer_id), true, false)
