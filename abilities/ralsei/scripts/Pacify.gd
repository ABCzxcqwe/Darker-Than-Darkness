extends AbilityBase

const AREA_LIFETIME: float = 3.0

const TICK_INTERVAL: float = 0.5


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[Pacify] player_node inválido.")
		return

	var caster_id: int   = player_node.get_multiplayer_authority()
	var stun_dur: float  = data.stun_duration
	var slow_mag: float  = data.slow_magnitude
	var slow_dur: float  = data.slow_duration
	var hit_threshold: int = data.hit_count_for_effect if data.hit_count_for_effect > 0 else 4

	var tp_svc = GameServiceLocator.get_service("TPService")
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			push_warning("[Pacify] consume_tp falló inesperadamente para peer ", caster_id)
			return

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if not abs_svc:
		push_error("[Pacify] AbilityStateService no disponible.")
		return

	abs_svc.reset_hit_counter(caster_id, slot_index)

	var hs = GameServiceLocator.get_service("HitboxService")
	if not hs:
		push_error("[Pacify] HitboxService no disponible.")
		return

	var cd = GameServiceLocator.get_service("CooldownService")

	var stun_applied := [false]

	hs.create({
		"attacker_id"   : caster_id,
		"attacker_node" : player_node,
		"type"          : "area",
		"aim_mode"      : "origin",
		"shape_scene"   : data.ability_scene,
		"damage"        : 0,
		"attack_type"   : data.attack_type,
		"team_filter"   : "enemy",
		"hit_limit"     : 0,
		"lifetime"      : AREA_LIFETIME,

		"on_hit": func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return
			if not target_node.is_in_group("killer"):
				return

			if slow_mag > 0.0:
				var status = GameServiceLocator.get_service("StatusEffectService")
				if status:
					status.apply(target_node, "slow", {
						"duration"  : slow_dur,
						"magnitude" : slow_mag
					})

			if stun_applied[0]:
				return

			var total: int = abs_svc.add_hit(caster_id, slot_index)

			print("[Pacify] Hit ", total, "/", hit_threshold,
				  " | killer: ", target_node.name)

			if total >= hit_threshold:
				stun_applied[0] = true
				abs_svc.reset_hit_counter(caster_id, slot_index)

				var status = GameServiceLocator.get_service("StatusEffectService")
				if status and stun_dur > 0.0:
					status.apply(target_node, "stun", { "duration": stun_dur })

				print("[Pacify] STUN aplicado! | killer: ", target_node.name,
					  " | duración: ", stun_dur, "s"),

		"on_end": func(_hit_count: int) -> void:
			if not stun_applied[0]:
				abs_svc.reset_hit_counter(caster_id, slot_index)
				print("[Pacify] Área expiró sin stun | hits reseteados")

			if cd and cd.has_method("release_lock"):
				cd.release_lock(caster_id, slot_index)
			if cd:
				cd.start(caster_id, slot_index, data.cooldown)

			print("[Pacify] Área terminó")
	})

	print("[Pacify] Área activada | peer: ", caster_id,
		  " | umbral: ", hit_threshold, " hits",
		  " | slow: ", slow_mag * 100, "%",
		  " | stun al umbral: ", stun_dur, "s")
