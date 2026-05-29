# res://core/AbilityRouter.gd  (Autoload)
# ============================================================
# AbilityRouter — Valida, resuelve y despacha habilidades.
#
# Cambios respecto a la versión anterior:
#   - Paso 6b: LMS auto-evolve. Si ability_data.lms_auto_evolve = true
#              y LMSService está activo y el jugador tiene TP, se fuerza
#              la evolución automáticamente antes de despachar.
#   - Paso 8.5: El chequeo de TP ahora usa AbilityStateService para
#               habilidades escalables (dynamic_tp_cost) en lugar de
#               leer tp_cost directo del recurso.
#   - Paso 8.6: Restricción de movimiento. Si move_restriction = LOCKED,
#               el caster es anclado antes de ejecutar y liberado en
#               un callback post-habilidad.
#   - Paso 12: El cooldown ahora usa AbilityStateService.get_dynamic_cooldown()
#              para habilidades escalables en lugar de ability_data.cooldown.
#
# Lo que NO cambió:
#   - Toda la lógica de validación previa (pasos 1-8).
#   - El mecanismo de reintegro de TP ante fallo de script.
#   - El helper _get_player_node.
# ============================================================
extends Node


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
	# El chequeo de TP ocurre más abajo (paso 8.5); aquí solo marcamos la
	# intención para que el paso 8.5 use el tp_cost de la versión evolucionada.
	var lms_svc: Node = GameServiceLocator.get_service("LMSService")
	var lms_wants_evolve: bool = false
	if not is_evolved and base_data.lms_auto_evolve and base_data.evolved_version:
		if lms_svc and lms_svc.is_lms_active():
			var lms_survivor: Node = lms_svc.get_active_survivor()
			if lms_survivor and lms_survivor.get_multiplayer_authority() == peer_id:
				lms_wants_evolve = true

	# Si el LMS quiere evolucionar, tratamos la habilidad como evolucionada
	# desde este punto en adelante (el EvolutionService se actualiza en paso 11).
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

	# ── 8.5. ¿Tiene suficiente TP? ───────────────────────────────────────
	# Para habilidades escalables usamos el costo dinámico del AbilityStateService.
	# Para el resto, leemos tp_cost del recurso directamente (comportamiento anterior).
	var abs_svc: Node = GameServiceLocator.get_service("AbilityStateService")
	var effective_tp_cost: float = _resolve_tp_cost(ability_data, peer_id, slot_index, abs_svc)

	if effective_tp_cost > 0.0 and ability_data.consume_tp_on_use:
		var tp_svc = GameServiceLocator.get_service("TPService")
		if tp_svc:
			if tp_svc.get_tp_for_peer(peer_id) < effective_tp_cost:
				print("[AbilityRouter] TP insuficiente para peer ", peer_id,
					  " | Requiere: ", effective_tp_cost,
					  " | Actual: ", tp_svc.get_tp_for_peer(peer_id))
				# Si el LMS quería evolucionar pero no hay TP, revertimos la intención
				# y ejecutamos la versión normal si tiene suficiente TP para ella.
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

			if not tp_svc.consume_tp(peer_id, effective_tp_cost):
				return

	# ── 8.6. Restricción de movimiento ───────────────────────────────────
	# Si la habilidad ancla al caster (LOCKED), forzamos velocidad 0
	# mediante un root temporal mientras la habilidad está activa.
	# La duración del root la decide la habilidad a través de su script;
	# aquí solo aplicamos el efecto si el recurso lo declara.
	# MoveRestriction: 0=FREE, 1=LOCKED, 2=AERIAL
	# if ability_data.move_restriction == AbilityData.MoveRestriction.LOCKED:
	# 	if status:
	# 		# Usamos "root" del StatusEffectService con duración igual al cooldown
	# 		# como límite superior seguro. El script de la habilidad puede
	# 		# removerlo antes si termina antes.
	# 		status.apply(player_node, "root", { "duration": ability_data.cooldown })

	# ── 9. ¿Existe el script? ────────────────────────────────────────────
	var ability_script: GDScript = ability_data.ability_script
	if not ability_script:
		push_error("[AbilityRouter] ability_script no asignado en AbilityData para '",
				   ability_data.display_name, "'")
		# Reintegro de seguridad: devolvemos el TP consumido
		var tp_svc = GameServiceLocator.get_service("TPService")
		if tp_svc and effective_tp_cost > 0.0:
			tp_svc.add_tp_custom(peer_id, effective_tp_cost)
		# Si aplicamos root, lo removemos también
		if ability_data.move_restriction == AbilityData.MoveRestriction.LOCKED and status:
			status.apply(player_node, "root", { "duration": 0.01 })
		return

	# ── 10. Instanciar y ejecutar ─────────────────────────────────────────
	var handler: AbilityBase = ability_script.new()
	handler.activate(player_node, ability_data, direction)

	print("[AbilityRouter] '", ability_data.display_name, "' despachado para peer ", peer_id,
		  " (", "evolucionada" if is_evolved else "normal", ")")

	# ── 11. Consumir / forzar evolución ───────────────────────────────────
	if evolution_service:
		if lms_wants_evolve:
			# La evolución fue forzada por LMS: la registramos y la consumimos
			# en el mismo paso para que no quede un estado "evolucionado" residual.
			evolution_service.evolve_slot(peer_id, slot_index)
			evolution_service.consume_evolution(peer_id, slot_index)
		elif is_evolved:
			# Evolución manual preexistente: consumir normalmente.
			evolution_service.consume_evolution(peer_id, slot_index)

	# ── 12. Iniciar cooldown ──────────────────────────────────────────────
	# Para habilidades escalables usamos el cooldown dinámico acumulado.
	# register_use() actualiza ese valor internamente y lo devuelve ya sumado.
	var effective_cooldown: float = _resolve_cooldown(
		ability_data, peer_id, slot_index, abs_svc
	)
	if cd:
		cd.start(peer_id, ability_data.display_name, effective_cooldown, slot_index)


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

	if not ability_data.can_cancel:
		print("[AbilityRouter] Cancel rechazada: ", ability_data.display_name, " no es cancelable.")
		return

	# Validación de estado FSM (1 = AnimState.ABILITY en Player.gd)
	if player_node.state != 1:
		print("[AbilityRouter] Cancel rechazada: ", ability_data.display_name,
			  " — jugador no está en estado ABILITY.")
		return

	# Reemplazar cooldown completo por cooldown reducido de cancelación.
	# Si cooldown_cancel es 0, la habilidad queda lista inmediatamente.
	var cd = GameServiceLocator.get_service("CooldownService")
	if cd:
		cd.start(peer_id, ability_data.display_name, ability_data.cooldown_cancel, slot_index)

	# Resetear estado FSM en todos los peers
	player_node.rpc("_sync_cancel_ability")

	print("[AbilityRouter] Habilidad cancelada: ", ability_data.display_name,
		  " | peer: ", peer_id, " | cd_cancel: ", ability_data.cooldown_cancel, "s")


# ── Helpers ────────────────────────────────────────────────────────────────

## Devuelve el costo de TP efectivo para esta ejecución.
## Habilidades escalables leen de AbilityStateService; el resto del recurso.
func _resolve_tp_cost(
	ability_data: AbilityData,
	peer_id: int,
	slot_index: int,
	abs_svc: Node
) -> float:
	if ability_data.is_scalable and abs_svc:
		return abs_svc.get_dynamic_tp_cost(peer_id, slot_index)
	return ability_data.tp_cost


## Devuelve el cooldown efectivo y, si es escalable, registra el uso
## (lo que actualiza el dynamic_cooldown para la próxima vez).
## IMPORTANTE: llamar esto DESPUÉS de execute, no antes.
func _resolve_cooldown(
	ability_data: AbilityData,
	peer_id: int,
	slot_index: int,
	abs_svc: Node
) -> float:
	if ability_data.is_scalable and abs_svc:
		# register_use actualiza dynamic_cooldown y devuelve el use_count.
		# get_dynamic_cooldown devuelve el valor YA actualizado.
		abs_svc.register_use(peer_id, slot_index, ability_data)
		return abs_svc.get_dynamic_cooldown(peer_id, slot_index)
	return ability_data.cooldown


func _get_player_node(peer_id: int) -> Node:
	return get_tree().root.find_child(str(peer_id), true, false)
