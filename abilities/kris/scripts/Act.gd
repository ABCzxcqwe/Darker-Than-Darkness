extends AbilityBase

# ─────────────────────────────────────────────────────────────────────
# Act.gd — Habilidad de Kris (modo normal).
#
# Abre el menú contextual para elegir un aliado survivor.
# Al confirmar, evoluciona todas las habilidades del aliado
# que tengan evolvable_by_ally = true.
#
# FLUJO DE TP:
#   Primera llamada (abrir menú) → NO consume TP, solo abre el menú.
#   Segunda llamada (target confirmado) → consume TP y ejecuta.
#   Cancelación / target inválido → no se consumió nada.
#
# FLUJO LMS:
#   En LMS, el CharacterData de Kris debe apuntar a Counter.gd
#   en el slot correspondiente. Act.gd no maneja LMS directamente.
#
# REQUISITO en AbilityData de ACT:
#   prepare_animation : animación mientras el menú está abierto (opcional)
#   action_animation  : animación al ejecutar el buff
#   tp_cost           : TP que consume al confirmar el target
#   cooldown          : cooldown tras ejecutar
# ─────────────────────────────────────────────────────────────────────


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[ACT] player_node inválido.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	print("[ACT] activate() | peer: ", caster_id, " | slot: ", slot_index)

	# ── ¿Viene con un target registrado? (segunda llamada tras confirmar menú) ──
	var target_peer_id: int = AbilityRouter.consume_pending_target(caster_id)

	if target_peer_id > 0:
		# Segunda llamada: target confirmado → consumir TP y ejecutar
		print("[ACT] Target confirmado → ejecutando ACT sobre peer: ", target_peer_id)
		_execute_act(player_node, data, caster_id, target_peer_id, slot_index)
	else:
		# Primera llamada: sin target → abrir menú sin consumir TP
		print("[ACT] Primera llamada → abriendo menú contextual.")
		_open_menu(player_node, data, caster_id, slot_index)


# ═══════════════════════════════════════════════════════════════════════
# PRIMERA LLAMADA — Abrir menú
# ═══════════════════════════════════════════════════════════════════════

func _open_menu(player_node: Node, data: AbilityData, caster_id: int, slot_index: int) -> void:
	# Animación de PREPARE mientras el menú está abierto
	if data.prepare_animation != "":
		player_node.play_prepare_animation(data.prepare_animation, slot_index, player_node.facing_right)

	var title := "ACT: " + data.display_name.to_upper()
	if player_node.has_method("_open_ability_selection"):
		# filter_peer_id = caster_id para que Kris no aparezca como opción
		player_node.rpc_id(caster_id, "_open_ability_selection", slot_index, title, caster_id)
		print("[ACT] Menú contextual abierto | peer: ", caster_id)
	else:
		push_warning("[ACT] player_node no tiene _open_ability_selection.")


# ═══════════════════════════════════════════════════════════════════════
# SEGUNDA LLAMADA — Ejecutar buff
# ═══════════════════════════════════════════════════════════════════════

func _execute_act(player_node: Node, data: AbilityData, caster_id: int, target_peer_id: int, slot_index: int) -> void:
	var tp_svc  = GameServiceLocator.get_service("TPService")
	var evo_svc = GameServiceLocator.get_service("EvolutionService")
	var cd_svc  = GameServiceLocator.get_service("CooldownService")

	# ── Validaciones ──────────────────────────────────────────────────
	if target_peer_id == caster_id:
		print("[ACT] Kris no puede potenciarse a sí mismo.")
		return

	var target_node := player_node.get_tree().root.find_child(str(target_peer_id), true, false)
	if not is_instance_valid(target_node):
		push_warning("[ACT] Nodo no encontrado para peer: ", target_peer_id)
		return

	var is_survivor: bool = target_node.is_in_group("survivor")
	if not is_survivor and target_node.get("character_data") != null:
		is_survivor = target_node.character_data.team == "survivor"
	if not is_survivor:
		print("[ACT] El objetivo no es un survivor.")
		return

	var health_svc = GameServiceLocator.get_service("HealthService")
	if health_svc and not health_svc.is_alive(target_peer_id):
		print("[ACT] El objetivo está caído o muerto.")
		return

	if not evo_svc:
		push_error("[ACT] EvolutionService no disponible.")
		return

	# ── Consumir TP ───────────────────────────────────────────────────
	# El Router verificó que hay suficiente. Aquí consumimos.
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			push_warning("[ACT] consume_tp falló inesperadamente para peer ", caster_id)
			return

	# ── Evolucionar habilidades del aliado ────────────────────────────
	var evolved_count: int = 0
	var target_data: CharacterData = target_node.character_data
	if target_data and target_data.ability_slots:
		for i in target_data.ability_slots.size():
			var slot_data: AbilityData = target_data.ability_slots[i]
			if slot_data and slot_data.evolvable_by_ally and slot_data.evolved_version:
				evo_svc.evolve_slot(target_peer_id, i)
				evolved_count += 1
				print("[ACT] Slot ", i, " de peer ", target_peer_id,
					  " evolucionado (", slot_data.display_name, ").")

	if evolved_count == 0:
		print("[ACT] El aliado ", target_peer_id, " no tiene habilidades evolucionables.")

	# ── Animación de acción ───────────────────────────────────────────
	if data.action_animation != "":
		player_node.play_ability_animation(
			data.action_animation, slot_index, player_node.facing_right
		)

	# ── Cooldown ──────────────────────────────────────────────────────
	if cd_svc:
		cd_svc.start(caster_id, data.display_name, data.cooldown, slot_index)
		print("[ACT] Cooldown iniciado: ", data.cooldown, "s | peer: ", caster_id)

	print("[ACT] ✓ Kris (", caster_id, ") potenció a peer ", target_peer_id,
		  " | slots evolucionados: ", evolved_count)
