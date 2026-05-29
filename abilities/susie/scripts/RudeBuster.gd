# res://scripts/abilities/susie/susie_rude_buster.gd
# ============================================================
# Habilidad 2 de Susie — Rude Buster  (normal)
#                       — Red Buster   (evolucionada, mismo script)
#
# Comportamiento normal — Rude Buster:
#   - Proyectil en la dirección del mouse.
#   - Permite kiting (move_restriction = FREE).
#   - Si golpea al killer: aplica Stun 5s.
#   - hit_limit = 1 (el proyectil se detiene al primer impacto).
#
# Comportamiento evolucionado — Red Buster:
#   - Mismo proyectil pero con daño (evo_damage_multiplier > 0).
#   - Piercing: hit_limit = 0 (atraviesa al killer y sigue viajando).
#   - Stun 5s + bonus de evo_status_duration_bonus.
#   - La distinción entre versiones la hacen los campos del recurso:
#       Rude Buster: base_damage = 0,  hit_limit_override = 1
#       Red Buster:  base_damage = 20, hit_limit_override = 0, evo_damage_multiplier = 1.0
#
# AbilityData.tres  (Rude Buster — normal):
#   display_name             = "Rude Buster"
#   ability_script           = este script
#   ability_scene            = res://hitboxes/buster_projectile.tscn
#   ability_type             = ATTACK
#   move_restriction         = FREE
#   cooldown                 = 18.0
#   tp_cost                  = 30.0
#   tp_reward                = 0.0
#   base_damage              = 0
#   range_                   = 0.0     ← no aplica, el offset lo maneja el speed
#   attack_type              = "projectile"
#   stun_duration            = 5.0
#   can_use_while_stunned    = false
#   lms_auto_evolve          = true
#   evolved_version          = <RedBuster.tres>
#
# AbilityData.tres  (Red Buster — evolucionada):
#   display_name             = "Red Buster"
#   ability_script           = este mismo script
#   ability_scene            = res://hitboxes/red_buster_projectile.tscn
#   base_damage              = 20
#   evo_damage_multiplier    = 1.0     ← el daño ya está en base_damage
#   evo_status_duration_bonus = 0.0
#   stun_duration            = 5.0
#   tp_cost                  = 50.0
#   ... resto igual
#
# NOTA sobre piercing:
#   El hit_limit del proyectil se determina en tiempo de ejecución:
#   si base_damage > 0 (Red Buster), hit_limit = 0 (piercing).
#   si base_damage = 0 (Rude Buster), hit_limit = 1 (se detiene).
#   Esto evita necesitar un campo extra en AbilityData para este caso.
# ============================================================
extends AbilityBase

# Velocidad del proyectil en píxeles por segundo
const PROJECTILE_SPEED: float = 500.0

# Duración máxima del proyectil en segundos antes de expirar
const PROJECTILE_LIFETIME: float = 2.0


func activate(player_node: Node, data: AbilityData, direction: Vector2, _slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[RudeBuster] player_node inválido.")
		return

	var hs = GameServiceLocator.get_service("HitboxService")
	if not hs:
		push_error("[RudeBuster] HitboxService no disponible.")
		return

	var attacker_id: int = player_node.get_multiplayer_authority()
	var dmg: int         = int(data.base_damage * data.evo_damage_multiplier)
	var atk_type: String = data.attack_type
	var stun_dur: float  = data.stun_duration + data.evo_status_duration_bonus

	# Piercing: Red Buster (tiene daño) atraviesa; Rude Buster se detiene
	var hit_limit: int = 0 if dmg > 0 else 1

	# La dirección ya viene normalizada desde Player.gd (mouse_dir)
	var proj_dir: Vector2 = direction.normalized()
	if proj_dir == Vector2.ZERO:
		proj_dir = Vector2.RIGHT if player_node.facing_right else Vector2.LEFT

	hs.create({
		"attacker_id"   : attacker_id,
		"attacker_node" : player_node,
		"type"          : "projectile",
		"aim_mode"      : "fixed",
		"direction"     : proj_dir,
		"shape_scene"   : data.ability_scene,
		"damage"        : dmg,
		"attack_type"   : atk_type,
		"team_filter"   : "enemy",
		"hit_limit"     : hit_limit,
		"lifetime"      : PROJECTILE_LIFETIME,
		"speed"         : PROJECTILE_SPEED,
		# offset = 0 para que el proyectil nazca en el centro del caster
		# y viaje desde ahí, en lugar de aparecer desplazado
		"offset"        : 0.0,
		"on_hit": func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return

			if dmg > 0:
				var health_svc = GameServiceLocator.get_service("HealthService")
				if health_svc:
					health_svc.take_damage(target_node, dmg, attacker_id, atk_type)

			if target_node.is_in_group("killer"):
				var status = GameServiceLocator.get_service("StatusEffectService")
				if status and stun_dur > 0.0:
					status.apply(target_node, "stun", { "duration": stun_dur }),

		"on_end": func(hit_count: int) -> void:
			print("[RudeBuster] Proyectil expiró | golpes: ", hit_count)
	})

	print("[RudeBuster] Activado | peer: ", attacker_id,
		  " | dir: ", proj_dir,
		  " | dmg: ", dmg,
		  " | stun: ", stun_dur, "s",
		  " | piercing: ", hit_limit == 0)
