# res://scripts/abilities/kris/kris_sword_slash.gd  (CORREGIDO)
# Cambio respecto a la versión anterior:
#   - El root ahora lo aplica este script directamente con la duración exacta
#     del hitbox (0.2s), no el cooldown.
#   - El on_end usa status.remove_effect() en lugar de apply(root, 0.001).
extends AbilityBase

const HITBOX_LIFETIME: float = 0.2


func activate(player_node: Node, data: AbilityData, direction: Vector2) -> void:
	if not is_instance_valid(player_node):
		push_warning("[SwordSlash] player_node inválido.")
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

	# ── Anclar al caster SOLO durante el hitbox ──────────────────────────
	var status = GameServiceLocator.get_service("StatusEffectService")
	if status:
		status.apply(player_node, "root", { "duration": HITBOX_LIFETIME })

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
		"lifetime"      : HITBOX_LIFETIME,
		"offset"        : hit_range,
		"on_hit": func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return
			if dmg > 0:
				var health_svc = GameServiceLocator.get_service("HealthService")
				if health_svc:
					health_svc.take_damage(target_node, dmg, attacker_id, atk_type)
			if target_node.is_in_group("killer"):
				var s = GameServiceLocator.get_service("StatusEffectService")
				if s and stun_dur > 0.0:
					s.apply(target_node, "stun", { "duration": stun_dur })
				if tp_reward > 0.0:
					var tp = GameServiceLocator.get_service("TPService")
					if tp:
						tp.add_tp_custom(attacker_id, tp_reward),

		"on_end": func(_hit_count: int) -> void:
			# Liberar root con remove_effect — no afectado por el refresh de apply()
			var s = GameServiceLocator.get_service("StatusEffectService")
			if s and is_instance_valid(player_node):
				s.remove_effect(player_node, "root")
			print("[SwordSlash] Terminó | golpes: ", _hit_count)
	})

	print("[SwordSlash] Activado | peer: ", attacker_id,
		  " | dir: ", slash_dir, " | stun: ", stun_dur, "s | dmg: ", dmg)
