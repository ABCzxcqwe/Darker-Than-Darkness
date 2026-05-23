# res://scripts/abilities/ralsei/ralsei_pacify.gd
# ============================================================
# Habilidad 2 de Ralsei — Pacify
#
# Comportamiento:
#   - Ralsei despliega un área de efecto a su alrededor.
#   - El área aplica slow al killer mientras está dentro.
#   - Cada vez que el killer es golpeado por el área, se suma 1 al
#     contador de golpes (hit_counter en AbilityStateService).
#   - Al acumular hit_count_for_effect golpes (default: 4), el stun
#     se aplica y el contador se resetea.
#   - Si el área expira antes de llegar al umbral, el contador se resetea.
#   - move_restriction = FREE (Ralsei puede moverse y hacer kiting).
#
# Contador de golpes:
#   El área tiene lifetime configurable. Dentro de ese tiempo,
#   cada "tick" del área suma un hit. El HitboxService maneja el
#   área con hit_limit = 0 (ilimitado), y el on_hit cuenta manualmente.
#
# AbilityData.tres  (Pacify):
#   display_name            = "Pacify"
#   ability_script          = este script
#   ability_scene           = res://hitboxes/pacify_area.tscn
#   ability_type            = UTILITY
#   move_restriction        = FREE
#   cooldown                = 15.0
#   tp_cost                 = 15.0
#   tp_reward               = 0.0
#   base_damage             = 0
#   range_                  = 0.0       ← área centrada en Ralsei (aim_mode = origin)
#   attack_type             = "magic"
#   stun_duration           = 2.0       ← stun al alcanzar el umbral de golpes
#   slow_magnitude          = 0.4       ← 40% de reducción de velocidad mientras está en el área
#   slow_duration           = 0.5       ← cada tick refresca el slow por 0.5s
#   hit_count_for_effect    = 4         ← golpes necesarios para aplicar el stun
#   can_use_while_stunned   = false
#   lms_auto_evolve         = false
# ============================================================
extends AbilityBase

# Slot de esta habilidad en el array ability_slots de Ralsei
const SLOT: int = 1

# Duración total del área en segundos
const AREA_LIFETIME: float = 3.0

# Intervalo entre ticks de daño/slow del área (segundos)
# HitboxService no hace ticks automáticos — usamos un Timer interno
# que reaplica el slow y cuenta golpes periódicamente.
const TICK_INTERVAL: float = 0.5


func activate(player_node: Node, _data: AbilityData, _direction: Vector2) -> void:
	if not is_instance_valid(player_node):
		push_warning("[Pacify] player_node inválido.")
		return

	var caster_id: int   = player_node.get_multiplayer_authority()
	var stun_dur: float  = _data.stun_duration
	var slow_mag: float  = _data.slow_magnitude
	var slow_dur: float  = _data.slow_duration
	var hit_threshold: int = _data.hit_count_for_effect if _data.hit_count_for_effect > 0 else 4

	var abs_svc := GameServiceLocator.get_service("AbilityStateService")
	if not abs_svc:
		push_error("[Pacify] AbilityStateService no disponible.")
		return

	# Resetear el contador al inicio de cada uso
	abs_svc.reset_hit_counter(caster_id, SLOT)

	var hs := GameServiceLocator.get_service("HitboxService")
	if not hs:
		push_error("[Pacify] HitboxService no disponible.")
		return

	# Flag para evitar aplicar el stun más de una vez si varios ticks
	# llegan en el mismo frame justo al alcanzar el umbral
	var stun_applied: bool = false

	hs.create({
		"attacker_id"   : caster_id,
		"attacker_node" : player_node,
		"type"          : "area",
		"aim_mode"      : "origin",     # centrada en Ralsei
		"shape_scene"   : _data.ability_scene,
		"damage"        : 0,
		"attack_type"   : _data.attack_type,
		"team_filter"   : "enemy",
		"hit_limit"     : 0,            # ilimitado — contamos manualmente
		"lifetime"      : AREA_LIFETIME,

		"on_hit": func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return
			if not target_node.is_in_group("killer"):
				return

			# Aplicar slow en cada hit (se refresca si ya estaba activo)
			if slow_mag > 0.0:
				var status := GameServiceLocator.get_service("StatusEffectService")
				if status:
					status.apply(target_node, "slow", {
						"duration"  : slow_dur,
						"magnitude" : slow_mag
					})

			# Stun ya aplicado en este ciclo de Pacify → ignorar hits adicionales
			if stun_applied:
				return

			# Sumar golpe al contador
			var total: int = abs_svc.add_hit(caster_id, SLOT)

			print("[Pacify] Hit ", total, "/", hit_threshold,
				  " | killer: ", target_node.name)

			# ¿Alcanzamos el umbral?
			if total >= hit_threshold:
				stun_applied = true
				abs_svc.reset_hit_counter(caster_id, SLOT)

				var status := GameServiceLocator.get_service("StatusEffectService")
				if status and stun_dur > 0.0:
					status.apply(target_node, "stun", { "duration": stun_dur })

				print("[Pacify] ¡STUN aplicado! | killer: ", target_node.name,
					  " | duración: ", stun_dur, "s"),

		"on_end": func(hit_count: int) -> void:
			# Si el área expiró sin llegar al umbral, resetear el contador
			if not stun_applied:
				abs_svc.reset_hit_counter(caster_id, SLOT)
				print("[Pacify] Área expiró sin stun | hits acumulados reseteados")
			print("[Pacify] Área terminó | total hits: ", hit_count)
	})

	print("[Pacify] Área activada | peer: ", caster_id,
		  " | umbral: ", hit_threshold, " hits",
		  " | slow: ", slow_mag * 100, "%",
		  " | stun al umbral: ", stun_dur, "s")
