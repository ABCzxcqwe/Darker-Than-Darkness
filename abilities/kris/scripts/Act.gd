extends AbilityBase

# ─────────────────────────────────────────────────────────────────────
# Act.gd — Habilidad de Kris.
#
# Modo normal (partida estándar):
#   Abre el menú contextual para elegir un aliado survivor.
#   Al confirmar, evoluciona TODAS las habilidades del aliado
#   que tengan evolvable_by_ally = true.
#
# Modo LMS (último survivor):
#   ACT se convierte en Counter: ventana de parry de COUNTER_WINDOW seg.
#   Si Kris recibe un golpe en esa ventana, el killer recibe stun y
#   Kris gana TP. No usa menú contextual.
#
# FLUJO DE TP (importante):
#   Primera llamada (abrir menú):
#     AbilityRouter consume TP → Act lo DEVUELVE de inmediato → abre menú.
#   Segunda llamada (target codificado tras confirmar):
#     AbilityRouter consume TP → Act ejecuta normalmente → TP gastado.
#   Cancelación:
#     El menú cierra, no hay segunda llamada, TP ya fue devuelto.
#
# REQUISITO en AbilityData del ACT:
#   defer_cooldown = true   ← AbilityRouter NO inicia cooldown.
#   consume_tp_on_use = true (normal — AbilityRouter lo consume en cada llamada)
# ─────────────────────────────────────────────────────────────────────

const COUNTER_WINDOW: float = 2.0


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[ACT] player_node inválido.")
		return

	var lms_svc = GameServiceLocator.get_service("LMSService")
	var is_lms: bool = lms_svc != null and lms_svc.is_lms_active()

	print("[ACT] activate() | peer: ", player_node.get_multiplayer_authority(),
		  " | slot: ", slot_index, " | LMS: ", is_lms,
		  " | direction: ", direction)

	if is_lms:
		_activate_counter(player_node, data, slot_index)
	else:
		_activate_act(player_node, data, direction, slot_index)


# ═══════════════════════════════════════════════════════════════════════
# MODO NORMAL — ACT (evolución de aliado)
# ═══════════════════════════════════════════════════════════════════════

func _activate_act(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int) -> void:
	var caster_id: int = player_node.get_multiplayer_authority()

	# ── ¿Viene con un target registrado en AbilityRouter? (segunda llamada) ──
	# Player.gd llamó set_pending_target() antes de re-despachar.
	var target_peer_id: int = AbilityRouter.consume_pending_target(caster_id)

	print("[ACT] _activate_act() | caster: ", caster_id,
		  " | target en AbilityRouter: ", target_peer_id)

	if target_peer_id > 0:
		print("[ACT] Target confirmado por menú → ejecutando ACT.")
		_execute_act(player_node, data, caster_id, target_peer_id, slot_index)
		return

	# ── Sin target: primera llamada → devolver TP y abrir menú ────────
	print("[ACT] Primera llamada (sin target) → devolviendo TP y abriendo menú.")
	_refund_tp_if_needed(caster_id, data)

	var title := "ACT: " + data.display_name.to_upper()
	if player_node.has_method("_open_ability_selection"):
		player_node.rpc_id(caster_id, "_open_ability_selection", slot_index, title, caster_id)
		print("[ACT] Menú contextual abierto para peer: ", caster_id)
	else:
		push_warning("[ACT] player_node no tiene _open_ability_selection.")


func _execute_act(player_node: Node, data: AbilityData, caster_id: int, target_peer_id: int, slot_index: int) -> void:
	# ── Validaciones ──────────────────────────────────────────────────
	if target_peer_id == caster_id:
		print("[ACT] Kris no puede potenciarse a sí mismo → reintegrando TP.")
		_refund_tp_if_needed(caster_id, data)
		return

	var target_node := player_node.get_tree().root.find_child(str(target_peer_id), true, false)
	if not is_instance_valid(target_node):
		push_warning("[ACT] Nodo no encontrado para peer_id: ", target_peer_id, " → reintegrando TP.")
		_refund_tp_if_needed(caster_id, data)
		return

	var is_survivor: bool = target_node.is_in_group("survivor")
	if not is_survivor and target_node.get("character_data") != null:
		is_survivor = target_node.character_data.team == "survivor"
	if not is_survivor:
		print("[ACT] El objetivo no es un survivor → reintegrando TP.")
		_refund_tp_if_needed(caster_id, data)
		return

	var health_svc = GameServiceLocator.get_service("HealthService")
	if health_svc and not health_svc.is_alive(target_peer_id):
		print("[ACT] El objetivo está caído o muerto → reintegrando TP.")
		_refund_tp_if_needed(caster_id, data)
		return

	var evo_svc = GameServiceLocator.get_service("EvolutionService")
	if not evo_svc:
		push_error("[ACT] EvolutionService no disponible → reintegrando TP.")
		_refund_tp_if_needed(caster_id, data)
		return

	# ── Ejecutar ──────────────────────────────────────────────────────
	print("[ACT] Ejecutando sobre peer: ", target_peer_id)

	if data.prepare_animation != "":
		player_node.play_prepare_animation(data.prepare_animation, slot_index, player_node.facing_right)

	# Evolucionar del aliado: todos los slots con evolvable_by_ally = true
	var evolved_count: int = 0
	var target_data: CharacterData = target_node.character_data
	if target_data and target_data.ability_slots:
		for i in target_data.ability_slots.size():
			var slot_data: AbilityData = target_data.ability_slots[i]
			if slot_data and slot_data.evolvable_by_ally and slot_data.evolved_version:
				evo_svc.evolve_slot(target_peer_id, i)
				evolved_count += 1
				print("[ACT] Slot ", i, " de peer ", target_peer_id, " evolucionado (", slot_data.display_name, ").")

	if evolved_count == 0:
		print("[ACT] El aliado ", target_peer_id, " no tiene habilidades evolucionables por ACT.")

	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, slot_index, player_node.facing_right)

	# ── Cooldown manual ───────────────────────────────────────────────
	var cd_svc = GameServiceLocator.get_service("CooldownService")
	if cd_svc:
		cd_svc.start(caster_id, data.display_name, data.cooldown, slot_index)
		print("[ACT] Cooldown iniciado: ", data.cooldown, "s para peer: ", caster_id)

	print("[ACT] ✓ Kris (", caster_id, ") potenció a peer ", target_peer_id)


# ═══════════════════════════════════════════════════════════════════════
# MODO LMS — COUNTER (parry activo)
# ═══════════════════════════════════════════════════════════════════════

func _activate_counter(player_node: Node, data: AbilityData, slot_index: int) -> void:
	var caster_id: int = player_node.get_multiplayer_authority()

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if not abs_svc:
		push_error("[Counter] AbilityStateService no disponible.")
		return

	if abs_svc.is_mode_active(caster_id, slot_index):
		print("[Counter] Ventana ya activa, ignorado.")
		_refund_tp_if_needed(caster_id, data)
		return

	abs_svc.activate_mode(caster_id, slot_index, {})

	if data.prepare_animation != "":
		player_node.play_prepare_animation(data.prepare_animation, slot_index, player_node.facing_right)

	print("[Counter] Ventana de parry abierta | peer: ", caster_id,
		  " | slot: ", slot_index, " | duración: ", COUNTER_WINDOW, "s")

	var timer := player_node.get_tree().create_timer(COUNTER_WINDOW)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(player_node):
			return
		if abs_svc.is_mode_active(caster_id, slot_index):
			abs_svc.deactivate_mode(caster_id, slot_index)
			print("[Counter] Ventana expiró sin acierto | peer: ", caster_id)
	)

	# Cooldown lo maneja AbilityRouter (Counter no tiene defer_cooldown)


# ═══════════════════════════════════════════════════════════════════════
# API ESTÁTICA — llamada desde habilidades del Killer al golpear
# ═══════════════════════════════════════════════════════════════════════

## Verifica si Kris está en ventana de Counter y procesa el parry.
## Devuelve true si el golpe fue contrarrestado.
## La habilidad atacante debe saltar el daño si esto devuelve true.
## `slot_index` es el slot donde vive ACT (se pasa porque try_counter es static).
static func try_counter(player_node: Node, attacker_node: Node, data: AbilityData, slot_index: int) -> bool:
	if not is_instance_valid(player_node):
		return false

	var caster_id: int = player_node.get_multiplayer_authority()

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if not abs_svc or not abs_svc.is_mode_active(caster_id, slot_index):
		return false

	abs_svc.deactivate_mode(caster_id, slot_index)
	print("[Counter] Ventana consumida por impacto | peer: ", caster_id)

	if is_instance_valid(attacker_node) and attacker_node.is_in_group("killer"):
		var status = GameServiceLocator.get_service("StatusEffectService")
		if status and data and data.stun_duration > 0.0:
			status.apply(attacker_node, "stun", { "duration": data.stun_duration })
			print("[Counter] Killer stunned por ", data.stun_duration, "s")

	if data and data.tp_reward > 0.0:
		var tp = GameServiceLocator.get_service("TPService")
		if tp:
			tp.add_tp_custom(caster_id, data.tp_reward)
			print("[Counter] TP otorgado: ", data.tp_reward, " a peer: ", caster_id)

	print("[Counter] PARRY exitoso | peer: ", caster_id)
	return true


# ═══════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════

# _decode_target eliminado — target ahora via AbilityRouter._pending_targets


## Devuelve el TP consumido por AbilityRouter cuando la habilidad
## no llega a ejecutarse (menú abierto, objetivo inválido, cancelación).
func _refund_tp_if_needed(caster_id: int, data: AbilityData) -> void:
	if not data or not data.consume_tp_on_use or data.tp_cost <= 0.0:
		return
	var tp_svc = GameServiceLocator.get_service("TPService")
	if tp_svc:
		tp_svc.add_tp_custom(caster_id, data.tp_cost)
		print("[ACT] TP reintegrado (", data.tp_cost, ") a peer: ", caster_id)
