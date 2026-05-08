# sword_slash.gd
# Habilidad 1 de Kris — Sword Slash
# Golpea en la dirección que mira el personaje (izquierda o derecha).
# Si golpea al killer: aplica Stun 3s y genera 15 TP al atacante.
#
# AbilityData.tres:
#   ability_script = este script
#   ability_scene  = <SlashHitbox.tscn>  (CollisionShape2D con forma del slash)
#   damage         = 0       (no hace daño directo, solo stun)
#   attack_type    = "slash"
#   cooldown       = 15.0
#   tp_cost        = 25.0    (para evolucionar a X-Slash en LMS)
extends AbilityBase

const STUN_DURATION := 3.0

func activate(player_node: Node, data: AbilityData, _direction: Vector2) -> void:
	if not is_instance_valid(player_node):
		push_warning("[SwordSlash] player_node inválido.")
		return

	var hs := GameServiceLocator.get_service("HitboxService")
	if not hs:
		push_error("[SwordSlash] HitboxService no disponible.")
		return

	var attacker_id: int    = player_node.get_multiplayer_authority()
	var dmg:         int    = data.damage      if data else 0
	var atk_type:    String = data.attack_type if data else "slash"
	var ability_range: float = data.range * 0.4 if data else 40.0

	hs.create({
		"attacker_id"   : attacker_id,
		"attacker_node" : player_node,
		"type"          : "slash",
		"aim_mode"      : "facing",
		"shape_scene"   : data.ability_scene if data else null,
		"damage"        : dmg,
		"attack_type"   : atk_type,
		"team_filter"   : "enemy",
		"hit_limit"     : 1,
		"lifetime"      : 0.2,
		"offset"        : ability_range,
		"on_hit": func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return
		# 1. Intentar aplicar daño siempre (el HealthService ya filtra internamente si es killer)
			var health_svc = GameServiceLocator.get_service("HealthService")
			if health_svc:
				health_svc.take_damage(target_node, dmg, attacker_id, atk_type)
			
			# 2. Lógica específica si el objetivo es un Killer (Stun + TP)
			if target_node.is_in_group("killer"):
				var status := GameServiceLocator.get_service("StatusEffectService")
				if status:
					status.apply(target_node, "stun", { "duration": STUN_DURATION })
					
				var tp := GameServiceLocator.get_service("TPService")
				if tp:
					tp.add_tp_custom(attacker_id, 15),
		"on_end": func(hit_count: int) -> void:
			print("[SwordSlash] Terminó | golpes: ", hit_count)
	})

	print("[SwordSlash] Activado | peer: ", attacker_id,
		  " | facing_right: ", player_node.facing_right)
