# res://scripts/abilities/ralsei/ralsei_heal_prayer.gd
# ============================================================
# Habilidad 1 de Ralsei — Heal Prayer
#
# Comportamiento:
#   - Ralsei selecciona un aliado (o a sí mismo) mediante menú contextual.
#   - Ancla al caster durante la animación (move_restriction = LOCKED).
#   - Curación fija leída de base_heal del recurso.
#   - Fuerte desde el inicio — no escala con usos.
#
# Modo LMS — Double Heal:
#   Cuando LMSService está activo y Ralsei es el survivor en LMS,
#   hay una probabilidad aleatoria (configurable en el .tres mediante
#   scaling_base_value como threshold 0.0–1.0) de que la curación
#   se duplique automáticamente sin necesidad de ACT de Kris.
#   El threshold por defecto es 0.35 (35% de probabilidad).
#
#   Esta es la única habilidad de Ralsei que tiene comportamiento
#   probabilístico en LMS — no hay un estado previo que activar,
#   simplemente se tira el dado al ejecutar.
#
# AbilityData.tres  (Heal Prayer):
#   display_name            = "Heal Prayer"
#   ability_script          = este script
#   ability_scene           = null
#   ability_type            = SUPPORT
#   move_restriction        = LOCKED
#   cooldown                = 12.0
#   tp_cost                 = 20.0
#   tp_reward               = 0.0
#   base_heal               = 40
#   can_use_while_stunned   = false
#   requires_selection      = true
#   selection_type          = ALLY
#   lms_auto_evolve         = false
#   is_scalable             = false
#   scaling_base_value      = 0.35   ← probabilidad de Double Heal en LMS (0.0–1.0)
# ============================================================
extends AbilityBase

# Slot de esta habilidad en el array ability_slots de Ralsei
const SLOT: int = 0

# Multiplicador de Double Heal
const DOUBLE_HEAL_MULTIPLIER: float = 2.0


func activate(player_node: Node, data: AbilityData, direction: Vector2) -> void:
	if not is_instance_valid(player_node):
		push_warning("[HealPrayer] player_node inválido.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	# ── Resolver objetivo ────────────────────────────────────────────────
	var target_node: Node = _resolve_target(player_node, caster_id, direction)
	if not is_instance_valid(target_node):
		print("[HealPrayer] Sin objetivo válido. Cancelado.")
		return

	var target_peer_id: int = target_node.get_multiplayer_authority()

	# Verificar estado del objetivo
	if target_node.get("health_state") == "dead":
		print("[HealPrayer] Cancelado: el objetivo está muerto permanentemente.")
		return

	var health_svc = GameServiceLocator.get_service("HealthService")
	if not health_svc:
		push_error("[HealPrayer] HealthService no disponible.")
		return

	if not health_svc.is_alive(target_peer_id):
		print("[HealPrayer] El objetivo está caído. Cancelado.")
		return

	# ── Calcular curación ────────────────────────────────────────────────
	var base_heal: int = data.base_heal if data.base_heal > 0 else 40
	var final_heal: int = base_heal
	var is_double: bool = false

	# Chequeo de Double Heal en LMS
	var lms_svc = GameServiceLocator.get_service("LMSService")
	if lms_svc and lms_svc.is_lms_active():
		var lms_survivor: Node = lms_svc.get_active_survivor()
		if lms_survivor and lms_survivor.get_multiplayer_authority() == caster_id:
			# Lanzar el dado — threshold en scaling_base_value
			var threshold: float = data.scaling_base_value \
				if data and "scaling_base_value" in data else 0.35
			var roll: float = randf()
			if roll < threshold:
				final_heal = int(base_heal * DOUBLE_HEAL_MULTIPLIER)
				is_double = true

	# ── Aplicar curación ─────────────────────────────────────────────────
	health_svc.heal(target_node, final_heal)

	# Liberar root aplicado por AbilityRouter (move_restriction = LOCKED)
	# Heal Prayer no tiene hitbox con on_end, así que lo liberamos aquí
	# con un delay mínimo para que la animación de cast tenga tiempo de verse.
	var status = GameServiceLocator.get_service("StatusEffectService")
	if status and is_instance_valid(player_node):
		player_node.get_tree().create_timer(0.4).timeout.connect(func() -> void:
			if is_instance_valid(player_node) and status:
				status.apply(player_node, "root", { "duration": 0.001 })
		)

	print("[HealPrayer] Curación aplicada",
		  " | caster: ", caster_id,
		  " | objetivo: ", target_peer_id,
		  " | HP curado: ", final_heal,
		  " | Double Heal: ", is_double)


# ── Helper: resolver objetivo desde el vector de selección ───────────────

func _resolve_target(player_node: Node, caster_id: int, direction: Vector2) -> Node:
	var part_high: int = int(round(direction.x))
	var part_low: int  = int(round(direction.y))

	# Vector cero o inválido → autocuración
	if part_high == 0 and part_low == 0:
		return player_node

	var target_peer_id: int = (part_high << 16) | (part_low & 0xFFFF)

	if target_peer_id <= 0 or target_peer_id == caster_id:
		return player_node

	var target_node := player_node.get_tree().root.find_child(
		str(target_peer_id), true, false
	)

	if not is_instance_valid(target_node):
		push_warning("[HealPrayer] Nodo del objetivo no encontrado: ", target_peer_id)
		return null

	if not target_node.is_in_group("survivor"):
		push_warning("[HealPrayer] El objetivo no es un survivor.")
		return null

	return target_node
