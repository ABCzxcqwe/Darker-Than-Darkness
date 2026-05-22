# res://scripts/abilities/susie/susie_axe_slash.gd
# ============================================================
# Habilidad 1 de Susie — Axe Slash
#
# Comportamiento:
#   - Golpe en arco amplio en la dirección horizontal que mira Susie.
#   - Ancla al caster durante el hitbox (move_restriction = LOCKED).
#   - Alcance y forma más amplios que Sword Slash de Kris.
#   - Si golpea al killer: aplica Stun 3s y genera tp_reward de TP.
#   - Sin versión evolucionada — Susie no tiene lms_auto_evolve en este slot.
#
# Diferencia clave con Sword Slash:
#   El hitbox usa una forma más ancha (axe_shape.tscn) y hit_limit = 0
#   para que pueda golpear al killer aunque esté parcialmente fuera
#   del eje horizontal. La duración del hitbox es levemente mayor (0.3s).
#
# AbilityData.tres  (Axe Slash):
#   display_name            = "Axe Slash"
#   ability_script          = este script
#   ability_scene           = res://hitboxes/axe_shape.tscn
#   ability_type            = ATTACK
#   move_restriction        = LOCKED
#   cooldown                = 12.0
#   tp_cost                 = 0.0
#   tp_reward               = 10.0
#   base_damage             = 0
#   range_                  = 120.0
#   attack_type             = "slash"
#   stun_duration           = 3.0
#   can_use_while_stunned   = false
#   lms_auto_evolve         = false
# ============================================================
extends AbilityBase


func activate(player_node: Node, data: AbilityData, direction: Vector2) -> void:
	if not is_instance_valid(player_node):
		push_warning("[AxeSlash] player_node inválido.")
		return

	var hs := GameServiceLocator.get_service("HitboxService")
	if not hs:
		push_error("[AxeSlash] HitboxService no disponible.")
		return

	var attacker_id: int = player_node.get_multiplayer_authority()
	var dmg: int         = data.base_damage
	var atk_type: String = data.attack_type
	var hit_range: float = data.range_
	var stun_dur: float  = data.stun_duration
	var tp_reward: float = data.tp_reward

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
		# hit_limit = 0 → ilimitado, por si el hitbox amplio roza
		# al killer más de una vez en el mismo swing
		"hit_limit"     : 0,
		"lifetime"      : 0.3,
		"offset"        : hit_range,
		"on_hit": func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return

			if dmg > 0:
				var health_svc = GameServiceLocator.get_service("HealthService")
				if health_svc:
					health_svc.take_damage(target_node, dmg, attacker_id, atk_type)

			if target_node.is_in_group("killer"):
				var status := GameServiceLocator.get_service("StatusEffectService")
				if status and stun_dur > 0.0:
					status.apply(target_node, "stun", { "duration": stun_dur })

				if tp_reward > 0.0:
					var tp := GameServiceLocator.get_service("TPService")
					if tp:
						tp.add_tp_custom(attacker_id, tp_reward),

		"on_end": func(hit_count: int) -> void:
			# Liberar el root aplicado por AbilityRouter
			var status := GameServiceLocator.get_service("StatusEffectService")
			if status and is_instance_valid(player_node):
				status.apply(player_node, "root", { "duration": 0.001 })
			print("[AxeSlash] Terminó | golpes: ", hit_count)
	})

	print("[AxeSlash] Activado | peer: ", attacker_id,
		  " | dir: ", slash_dir, " | stun: ", stun_dur, "s")
