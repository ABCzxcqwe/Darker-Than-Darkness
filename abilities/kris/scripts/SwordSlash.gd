extends AbilityBase

const HITBOX_LIFETIME: float = 0.5


func activate(player_node: Node, data: AbilityData, direction: Vector2) -> void:
	if not is_instance_valid(player_node):
		push_warning("[SwordSlash] player_node inválido.")
		return

	var combat = GameServiceLocator.get_service("CombatMediator")
	if not combat:
		push_error("[SwordSlash] CombatMediator no disponible.")
		return

	var hs = GameServiceLocator.get_service("HitboxService")
	if not hs:
		push_error("[SwordSlash] HitboxService no disponible.")
		return

	var attacker_id: int = player_node.get_multiplayer_authority()
	var dmg: int         = int(data.base_damage * data.evo_damage_multiplier)
	var atk_type: String = data.attack_type
	var hit_range: float = data.range_
	var stun_dur: float  = data.stun_duration + data.evo_status_duration_bonus
	var tp_reward: float = data.tp_reward

	var slash_dir: Vector2 = Vector2.RIGHT if direction.x >= 0.0 else Vector2.LEFT

	# Root durante el hitbox — la habilidad llama remove_root() en on_end
	combat.apply_root(player_node, HITBOX_LIFETIME)

	# Reproducir animación
	print("[SwordSlash] Llamando play_ability_animation con: ", data.action_animation)
	player_node.play_ability_animation(data.action_animation, direction.x >= 0.0)
	print("[SwordSlash] play_ability_animation retornó")

	hs.create({
		"attacker_id"   : attacker_id,
		"attacker_node" : player_node,
		"type"          : "slash",
		"aim_mode"      : "fixed",
		"direction"     : slash_dir,
		"shape_scene"   : data.ability_scene,
		"damage"        : 0,
		"attack_type"   : atk_type,
		"team_filter"   : "enemy",
		"hit_limit"     : 1,
		"lifetime"      : HITBOX_LIFETIME,
		"offset"        : hit_range,

		"on_hit": func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return

			if dmg > 0:
				combat.apply_damage(player_node, target_node, dmg, atk_type)

			if target_node.is_in_group("killer"):
				if stun_dur > 0.0:
					combat.apply_stun(target_node, stun_dur)
				if tp_reward > 0.0:
					var tp = GameServiceLocator.get_service("TPService")
					if tp:
						tp.add_tp_custom(attacker_id, tp_reward),

		"on_end": func(hit_count: int) -> void:
			if is_instance_valid(player_node):
				combat.remove_root(player_node)

			# Si no golpeó a nadie, reemplazar cooldown por el de fallo
			if hit_count == 0 and data.cooldown_fail > 0.0:
				var cd = GameServiceLocator.get_service("CooldownService")
				if cd:
					cd.start(attacker_id, data.display_name, data.cooldown_fail)

			print("[SwordSlash] Terminó | golpes: ", hit_count,
				  " | cd_fail: ", data.cooldown_fail if hit_count == 0 else "N/A")
	})

	print("[SwordSlash] Activado | peer: ", attacker_id,
		  " | dir: ", slash_dir, " | dmg: ", dmg,
		  " | stun: ", stun_dur, "s",
		  " | anim: ", data.action_animation)
