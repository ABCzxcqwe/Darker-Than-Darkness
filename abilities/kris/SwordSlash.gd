# res://scripts/abilities/kris/sword_slash.gd
# ============================================================
# Habilidad 1 de Kris — Sword Slash  (versión normal)
#                      — X-Slash      (versión evolucionada, mismo script)
#
# Comportamiento:
#   - Golpe en la dirección horizontal que mira Kris (izquierda / derecha).
#   - Ancla al caster durante el hitbox (move_restriction = LOCKED en el .tres).
#   - Si golpea al killer: aplica Stun y genera tp_reward de TP al caster.
#   - Versión evolucionada (X-Slash): el multiplicador de daño y el bonus
#     de duración de stun se leen de evo_damage_multiplier y
#     evo_status_duration_bonus del recurso evolucionado.
#
# AbilityData.tres  (Sword Slash — normal):
#   display_name            = "Sword Slash"
#   ability_script          = este script
#   ability_scene           = res://hitboxes/slash_shape.tscn
#   ability_type            = ATTACK
#   move_restriction        = LOCKED
#   cooldown                = 15.0
#   tp_cost                 = 0.0
#   tp_reward               = 15.0
#   base_damage             = 0
#   range_                  = 100.0
#   attack_type             = "slash"
#   stun_duration           = 3.0
#   can_use_while_stunned   = false
#   lms_auto_evolve         = true
#   evolved_version         = <XSlash.tres>
#
# AbilityData.tres  (X-Slash — evolucionada):
#   display_name            = "X-Slash"
#   ability_script          = este mismo script
#   ability_scene           = res://hitboxes/xslash_shape.tscn  (forma más ancha)
#   evo_damage_multiplier   = 1.5   (o el valor que decidas)
#   evo_status_duration_bonus = 1.0 (stun pasa de 3s a 4s)
#   tp_cost                 = 25.0  (costo para activar la versión evolucionada)
#   ... resto igual que arriba
# ============================================================
extends AbilityBase


func activate(player_node: Node, data: AbilityData, direction: Vector2) -> void:
	if not is_instance_valid(player_node):
		push_warning("[SwordSlash] player_node inválido.")
		return

	var hs := GameServiceLocator.get_service("HitboxService")
	if not hs:
		push_error("[SwordSlash] HitboxService no disponible.")
		return

	var attacker_id: int    = player_node.get_multiplayer_authority()
	var dmg: int            = int(data.base_damage * data.evo_damage_multiplier)
	var atk_type: String    = data.attack_type
	var hit_range: float    = data.range_
	var stun_dur: float     = data.stun_duration + data.evo_status_duration_bonus
	var tp_reward: float    = data.tp_reward

	# Dirección siempre horizontal — el cliente ya envió el vector normalizado
	var slash_dir: Vector2 = Vector2.RIGHT if direction.x >= 0.0 else Vector2.LEFT

	hs.create({
		"attacker_id"   : attacker_id,
		"attacker_node" : player_node,
		"type"          : "slash",
		"aim_mode"      : "fixed",
		"direction"     : slash_dir,
		"shape_scene"   : data.ability_scene,
		"damage"        : dmg,
		"attack_type"   : atk_type,
		"team_filter"   : "enemy",
		"hit_limit"     : 1,
		"lifetime"      : 0.2,
		"offset"        : hit_range,
		"on_hit": func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return

			# Daño (puede ser 0 en la versión normal)
			if dmg > 0:
				var health_svc = GameServiceLocator.get_service("HealthService")
				if health_svc:
					health_svc.take_damage(target_node, dmg, attacker_id, atk_type)

			# Stun al killer
			if target_node.is_in_group("killer"):
				var status := GameServiceLocator.get_service("StatusEffectService")
				if status and stun_dur > 0.0:
					status.apply(target_node, "stun", { "duration": stun_dur })

				# TP al atacante por golpear
				if tp_reward > 0.0:
					var tp := GameServiceLocator.get_service("TPService")
					if tp:
						tp.add_tp_custom(attacker_id, tp_reward),

		"on_end": func(hit_count: int) -> void:
			# El root fue aplicado por AbilityRouter (move_restriction = LOCKED).
			# El hitbox dura 0.2s, mucho menos que el cooldown de 15s,
			# así que lo cancelamos aquí para que Kris pueda moverse de inmediato.
			var status := GameServiceLocator.get_service("StatusEffectService")
			if status and is_instance_valid(player_node):
				# Aplicar root de duración mínima para forzar la limpieza del efecto
				status.apply(player_node, "root", { "duration": 0.001 })
			print("[SwordSlash] Terminó | golpes: ", hit_count)
	})

	print("[SwordSlash] Activado | peer: ", attacker_id, " | dir: ", slash_dir,
		  " | stun: ", stun_dur, "s | dmg: ", dmg)
