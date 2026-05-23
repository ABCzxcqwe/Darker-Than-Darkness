# res://abilities/kris/scripts/act_counter.gd
# ============================================================
# Habilidad 2 de Kris — ACT (modo normal) / Counter (modo LMS)
#
# Modo NORMAL — ACT:
#   Kris potencia a un aliado seleccionado, forzando la evolución
#   de su slot 1 (Habilidad 1) a través del EvolutionService.
#   El aliado debe estar vivo y no ser el propio Kris.
#
# Modo LMS — Counter:
#   Kris activa un parry de 2 segundos.
#   - Si recibe daño durante la ventana: el daño es cancelado,
#     el killer recibe Stun y Kris gana tp_reward de TP.
#   - Si no recibe daño: el parry expira sin efecto.
#   - can_use_while_stunned = false (no es un reversal instantáneo).
#
# El switch entre modos lo hace el script internamente consultando
# LMSService — el .tres es el mismo recurso para ambos modos.
#
# AbilityData.tres  (ACT / Counter):
#   display_name            = "ACT"
#   ability_script          = este script
#   ability_scene           = null
#   ability_type            = SUPPORT
#   move_restriction        = FREE
#   cooldown                = 20.0
#   tp_cost                 = 0.0
#   tp_reward               = 20.0      ← TP al contrarrestar (Counter)
#   stun_duration           = 2.0       ← stun al killer si Counter acierta
#   can_use_while_stunned   = false
#   requires_selection      = true      ← solo en modo normal (ACT)
#   selection_type          = ALLY
#
# NOTA sobre requires_selection en modo LMS:
#   Player.gd abre el menú cuando requires_selection = true.
#   En LMS Kris es el único survivor, así que el menú no tiene
#   a nadie a quien mostrar. Para evitar esto, lo ideal es que
#   el HUD desactive el menú cuando LMSService.is_lms_active() = true
#   y envíe el RPC directamente con direction = Vector2.ZERO.
#   Este script maneja Vector2.ZERO como "modo Counter activado".
# ============================================================
extends AbilityBase

# Duración de la ventana de parry en segundos
const COUNTER_WINDOW: float = 2.0


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

	# Decodificar target desde el vector de 16 bits (mismo sistema que heal_prayer)
	var part_high: int = int(round(direction.x))
	var part_low: int  = int(round(direction.y))
	var target_peer_id: int = (part_high << 16) | (part_low & 0xFFFF)

	# Fallback: si el vector es cero (no hubo selección), no hacemos nada
	if part_high == 0 and part_low == 0:
		print("[ACT] Sin objetivo seleccionado. Cancelado.")
		return

	# Validar que el objetivo es un aliado vivo distinto de Kris
	var target_node := player_node.get_tree().root.find_child(str(target_peer_id), true, false)
	if not is_instance_valid(target_node):
		push_warning("[ACT] Objetivo no encontrado: ", target_peer_id)
		return
	if target_peer_id == caster_id:
		print("[ACT] Kris no puede potenciarse a sí mismo.")
		return
	if not target_node.is_in_group("survivor"):
		print("[ACT] El objetivo no es un survivor.")
		return
	var health_svc := GameServiceLocator.get_service("HealthService")
	if health_svc and not health_svc.is_alive(target_peer_id):
		print("[ACT] El objetivo está muerto o caído.")
		return

	# Forzar evolución del slot 1 del aliado (su Habilidad 1)
	# El slot 1 es la Habilidad 1 por convención del proyecto.
	var evo_svc := GameServiceLocator.get_service("EvolutionService")
	if not evo_svc:
		push_error("[ACT] EvolutionService no disponible.")
		return

	evo_svc.evolve_slot(target_peer_id, 1)

	print("[ACT] Kris (", caster_id, ") potencia a ", target_peer_id,
		  " → Slot 1 evolucionado.")


# ── Modo LMS: Counter ────────────────────────────────────────────────────

func _activate_counter(player_node: Node, _data: AbilityData) -> void:
	var caster_id: int = player_node.get_multiplayer_authority()

	var abs_svc := GameServiceLocator.get_service("AbilityStateService")
	if not abs_svc:
		push_error("[Counter] AbilityStateService no disponible.")
		return

	# Slot 1 = índice de esta habilidad (ACT/Counter)
	const SLOT: int = 1

	# Evitar doble activación si ya está activo
	if abs_svc.is_mode_active(caster_id, SLOT):
		print("[Counter] Ya está activo. Ignorado.")
		return

	# Activar ventana de parry
	abs_svc.activate_mode(caster_id, SLOT, {})

	print("[Counter] Ventana de parry abierta para peer: ", caster_id,
		  " | duración: ", COUNTER_WINDOW, "s")

	# Temporizador de expiración de la ventana
	var tree := player_node.get_tree()
	var timer := tree.create_timer(COUNTER_WINDOW)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(player_node) and abs_svc.is_mode_active(caster_id, SLOT):
			abs_svc.deactivate_mode(caster_id, SLOT)
			print("[Counter] Ventana expiró sin acierto para peer: ", caster_id)
	)


# ── API pública: llamada desde HealthService al procesar daño a Kris ─────
#
# HealthService debe llamar esto ANTES de aplicar el daño si Kris tiene
# Counter activo. Si devuelve true, el daño debe ser cancelado.
#
# Uso en HealthService.take_damage():
#   var act_script = load("res://abilities/kris/scripts/act_counter.gd")
#   if act_script.try_counter(player_node):
#       return  # daño cancelado
#
# Alternativamente, HealthService puede consultar AbilityStateService
# directamente para no depender de este script:
#   if abs_svc.is_mode_active(peer_id, 1):
#       abs_svc.deactivate_mode(peer_id, 1)
#       ... aplicar stun al killer y dar TP a Kris ...
#       return
#
# El segundo enfoque es más limpio porque no crea dependencia entre
# HealthService y un script de habilidad. Se documenta aquí para que
# sepas dónde va esa lógica cuando modifiques HealthService.
static func try_counter(player_node: Node, attacker_node: Node, data: AbilityData) -> bool:
	if not is_instance_valid(player_node):
		return false

	var caster_id: int = player_node.get_multiplayer_authority()
	const SLOT: int = 1

	var abs_svc := GameServiceLocator.get_service("AbilityStateService")
	if not abs_svc or not abs_svc.is_mode_active(caster_id, SLOT):
		return false

	# Parry exitoso — cerrar ventana
	abs_svc.deactivate_mode(caster_id, SLOT)

	# Stunear al killer
	if is_instance_valid(attacker_node) and attacker_node.is_in_group("killer"):
		var status := GameServiceLocator.get_service("StatusEffectService")
		if status and data and data.stun_duration > 0.0:
			status.apply(attacker_node, "stun", { "duration": data.stun_duration })

	# Dar TP a Kris
	if data and data.tp_reward > 0.0:
		var tp := GameServiceLocator.get_service("TPService")
		if tp:
			tp.add_tp_custom(caster_id, data.tp_reward)

	print("[Counter] ¡ACIERTO! Peer: ", caster_id, " contrarrestó el ataque.")
	return true
