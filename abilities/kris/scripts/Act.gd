# res://scripts/abilities/kris/kris_act.gd  (CORREGIDO)
# Fix: validación de aliado ahora verifica character_data.team además de grupo,
# por si el nodo no fue añadido al grupo "survivor" en el momento de la llamada.
# Fix: logs detallados para diagnosticar target_peer_id recibido.
extends AbilityBase

const COUNTER_WINDOW: float = 2.0
const SLOT: int = 1


func activate(player_node: Node, data: AbilityData, direction: Vector2) -> void:
	if not is_instance_valid(player_node):
		push_warning("[ACT] player_node inválido.")
		return

	var lms_svc := GameServiceLocator.get_service("LMSService")
	var is_lms: bool = lms_svc != null and lms_svc.is_lms_active()

	if is_lms:
		_activate_counter(player_node, data)
	else:
		_activate_act(player_node, data, direction)


# ── Modo normal: ACT ─────────────────────────────────────────────────────

func _activate_act(player_node: Node, _data: AbilityData, direction: Vector2) -> void:
	var caster_id: int = player_node.get_multiplayer_authority()

	var part_high: int = int(round(direction.x))
	var part_low: int  = int(round(direction.y))
	var target_peer_id: int = (part_high << 16) | (part_low & 0xFFFF)

	print("[ACT] Decodificando objetivo | direction: ", direction,
		  " | part_high: ", part_high, " | part_low: ", part_low,
		  " | target_peer_id: ", target_peer_id)

	if target_peer_id <= 0:
		print("[ACT] Sin objetivo seleccionado (ID <= 0). Cancelado.")
		return

	var target_node := player_node.get_tree().root.find_child(str(target_peer_id), true, false)
	if not is_instance_valid(target_node):
		push_warning("[ACT] Nodo no encontrado para peer_id: ", target_peer_id)
		return

	if target_peer_id == caster_id:
		print("[ACT] Kris no puede potenciarse a sí mismo.")
		return

	# ── Validación robusta: grupo O character_data.team ─────────────────
	var is_survivor: bool = target_node.is_in_group("survivor")
	if not is_survivor and target_node.get("character_data") != null:
		is_survivor = target_node.character_data.team == "survivor"

	if not is_survivor:
		print("[ACT] El objetivo (peer: ", target_peer_id, ") no es un survivor.",
			  " | grupos: ", target_node.get_groups())
		return

	var health_svc := GameServiceLocator.get_service("HealthService")
	if health_svc and not health_svc.is_alive(target_peer_id):
		print("[ACT] El objetivo está caído o muerto.")
		return

	var evo_svc := GameServiceLocator.get_service("EvolutionService")
	if not evo_svc:
		push_error("[ACT] EvolutionService no disponible.")
		return

	evo_svc.evolve_slot(target_peer_id, 1)

	print("[ACT] ✓ Kris (", caster_id, ") potencia a peer ", target_peer_id,
		  " → Slot 1 evolucionado.")


# ── Modo LMS: Counter ────────────────────────────────────────────────────

func _activate_counter(player_node: Node, _data: AbilityData) -> void:
	var caster_id: int = player_node.get_multiplayer_authority()

	var abs_svc := GameServiceLocator.get_service("AbilityStateService")
	if not abs_svc:
		push_error("[Counter] AbilityStateService no disponible.")
		return

	if abs_svc.is_mode_active(caster_id, SLOT):
		print("[Counter] Ya está activo. Ignorado.")
		return

	abs_svc.activate_mode(caster_id, SLOT, {})

	print("[Counter] Ventana de parry abierta | peer: ", caster_id,
		  " | duración: ", COUNTER_WINDOW, "s")

	var timer := player_node.get_tree().create_timer(COUNTER_WINDOW)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(player_node) and abs_svc.is_mode_active(caster_id, SLOT):
			abs_svc.deactivate_mode(caster_id, SLOT)
			print("[Counter] Ventana expiró sin acierto | peer: ", caster_id)
	)


# ── API pública: llamada desde HealthService ─────────────────────────────

static func try_counter(player_node: Node, attacker_node: Node, data: AbilityData) -> bool:
	if not is_instance_valid(player_node):
		return false

	var caster_id: int = player_node.get_multiplayer_authority()

	var abs_svc := GameServiceLocator.get_service("AbilityStateService")
	if not abs_svc or not abs_svc.is_mode_active(caster_id, SLOT):
		return false

	abs_svc.deactivate_mode(caster_id, SLOT)

	if is_instance_valid(attacker_node) and attacker_node.is_in_group("killer"):
		var status := GameServiceLocator.get_service("StatusEffectService")
		if status and data and data.stun_duration > 0.0:
			status.apply(attacker_node, "stun", { "duration": data.stun_duration })

	if data and data.tp_reward > 0.0:
		var tp := GameServiceLocator.get_service("TPService")
		if tp:
			tp.add_tp_custom(caster_id, data.tp_reward)

	print("[Counter] ¡ACIERTO! peer: ", caster_id, " contrarrestó el ataque.")
	return true
