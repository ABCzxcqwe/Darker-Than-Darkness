# res://scripts/abilities/susie/susie_ultimate_health.gd
# ============================================================
# Habilidad 3 de Susie — Ultimate Health
#
# Curación escalable por uso sobre un aliado seleccionado (o Susie misma).
# Cada uso en la misma partida aumenta la curación y reduce el costo de TP,
# pero también aumenta el cooldown.
#
# Curva de escala (valores del .tres):
#   Uso 0 (primer uso):  cura 1% HP máx  | costo 100% TP | cd 5.0s
#   Uso 1:               cura 3% HP máx  | costo 98%  TP | cd 5.5s
#   Uso 2:               cura 5% HP máx  | costo 96%  TP | cd 6.0s
#   ...
#   Uso N (techo):       cura 55% HP máx | costo 50%  TP | cd X s
#
# La escala es manejada por AbilityStateService.
# El cooldown y el costo de TP dinámicos son calculados por AbilityRouter
# antes de llamar a activate(). Este script solo lee el valor ya escalado.
#
# Menú contextual:
#   Susie selecciona un aliado vivo o a sí misma.
#   Si el vector direction es (0, 0) → autocuración (Susie se cura a sí misma).
#
# AbilityData.tres  (Ultimate Health):
#   display_name                  = "Ultimate Health"
#   ability_script                = este script
#   ability_scene                 = null
#   ability_type                  = SUPPORT
#   move_restriction              = FREE
#   cooldown                      = 5.0          ← cooldown base (uso 0)
#   tp_cost                       = 100.0         ← costo base en puntos de TP
#                                                    (ajustar según tu escala de TP máx)
#   tp_reward                     = 0.0
#   can_use_while_stunned         = false
#   requires_selection            = true
#   selection_type                = ALLY
#   is_scalable                   = true
#   scaling_base_value            = 0.01          ← 1% del HP máximo
#   scaling_per_use               = 0.02          ← +2% por uso
#   scaling_cap                   = 0.55          ← techo: 55%
#   tp_cost_reduction_per_use     = 2.0           ← -2 puntos de TP por uso
#   tp_cost_floor                 = 50.0          ← mínimo 50 puntos de TP
#   cooldown_increase_per_use     = 0.5           ← +0.5s por uso
# ============================================================
extends AbilityBase

# Slot de esta habilidad en el array ability_slots de Susie
const SLOT: int = 2


func activate(player_node: Node, data: AbilityData, direction: Vector2) -> void:
	if not is_instance_valid(player_node):
		push_warning("[UltimateHealth] player_node inválido.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	# ── Resolver objetivo ────────────────────────────────────────────────
	var target_node: Node = _resolve_target(player_node, caster_id, direction)
	if not is_instance_valid(target_node):
		print("[UltimateHealth] Sin objetivo válido. Cancelado.")
		return

	var target_peer_id: int = target_node.get_multiplayer_authority()

	# ── Calcular curación escalada ───────────────────────────────────────
	# AbilityStateService.get_scaled_value() devuelve el porcentaje
	# correspondiente al número de usos ACTUALES (antes de register_use,
	# que AbilityRouter llamará en el paso 12 después de activate()).
	var abs_svc := GameServiceLocator.get_service("AbilityStateService")
	var heal_ratio: float = 0.0
	if abs_svc:
		heal_ratio = abs_svc.get_scaled_value(caster_id, SLOT, data)
	else:
		# Fallback: usar el valor base del recurso si el servicio no está
		heal_ratio = data.scaling_base_value
		push_warning("[UltimateHealth] AbilityStateService no disponible, usando valor base.")

	# Calcular HP a curar basado en el HP máximo del objetivo
	var max_hp: int = target_node.character_data.max_health \
		if target_node.character_data else 100
	var heal_amount: int = maxi(1, int(max_hp * heal_ratio))

	# ── Aplicar curación ─────────────────────────────────────────────────
	var health_svc := GameServiceLocator.get_service("HealthService")
	if not health_svc:
		push_error("[UltimateHealth] HealthService no disponible.")
		return

	if not health_svc.is_alive(target_peer_id):
		print("[UltimateHealth] El objetivo está caído o muerto. Cancelado.")
		return

	health_svc.heal(target_node, heal_amount)

	var use_count: int = abs_svc.get_use_count(caster_id, SLOT) if abs_svc else 0
	print("[UltimateHealth] Curación aplicada",
		  " | caster: ", caster_id,
		  " | objetivo: ", target_peer_id,
		  " | uso #", use_count,
		  " | ratio: ", "%.1f" % (heal_ratio * 100), "%",
		  " | HP curado: ", heal_amount)


# ── Helper: resolver objetivo desde el vector de selección ──────────────

func _resolve_target(player_node: Node, caster_id: int, direction: Vector2) -> Node:
	var part_high: int = int(round(direction.x))
	var part_low: int  = int(round(direction.y))

	# Vector cero → autocuración
	if part_high == 0 and part_low == 0:
		return player_node

	var target_peer_id: int = (part_high << 16) | (part_low & 0xFFFF)

	# Si el ID decodificado es el propio Susie → autocuración
	if target_peer_id == caster_id:
		return player_node

	var target_node := player_node.get_tree().root.find_child(
		str(target_peer_id), true, false
	)

	if not is_instance_valid(target_node):
		push_warning("[UltimateHealth] Nodo del objetivo no encontrado: ", target_peer_id)
		return null

	if not target_node.is_in_group("survivor"):
		push_warning("[UltimateHealth] El objetivo no es un survivor.")
		return null

	return target_node
