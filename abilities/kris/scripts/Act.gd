extends AbilityBase

const ANIM_DURATION: float = 1.6


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[ACT] player_node inválido.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()
	var target_peer_id: int = pending_target_peer

	if target_peer_id <= 0:
		print("[ACT] Sin target válido. Cancelado.")
		return

	_execute_act(player_node, data, caster_id, target_peer_id, slot_index)


func _execute_act(player_node: Node, data: AbilityData, caster_id: int, target_peer_id: int, slot_index: int) -> void:
	var combat = GameServiceLocator.get_service("CombatMediator")
	if not combat:
		push_error("[ACT] CombatMediator no disponible.")
		return

	var tp_svc  = GameServiceLocator.get_service("TPService")
	var evo_svc = GameServiceLocator.get_service("EvolutionService")
	var cd_svc  = GameServiceLocator.get_service("CooldownService")

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

	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			push_warning("[ACT] consume_tp falló para peer ", caster_id)
			return

	# Play action animation (root is already active from prepare phase)
	var anim_dur := _get_anim_duration(player_node, data.action_animation)

	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, slot_index, player_node.facing_right)

	player_node.get_tree().create_timer(anim_dur).timeout.connect(
		func() -> void:
			if not is_instance_valid(player_node):
				return

			combat.remove_root(player_node)

			if player_node.state != 2 or player_node.active_ability_slot != slot_index:
				return

			var evolved_count: int = 0
			var t_node := player_node.get_tree().root.find_child(str(target_peer_id), true, false)
			if is_instance_valid(t_node):
				var target_data: CharacterData = t_node.character_data
				if target_data and target_data.ability_slots:
					for i in target_data.ability_slots.size():
						var slot_data: AbilityData = target_data.ability_slots[i]
						if slot_data and slot_data.evolvable_by_ally and slot_data.evolved_version:
							evo_svc.evolve_slot(target_peer_id, i)
							evolved_count += 1

			if evolved_count == 0:
				print("[ACT] El aliado ", target_peer_id, " no tiene habilidades evolucionables.")

			if cd_svc:
				if cd_svc.has_method("release_lock"):
					cd_svc.release_lock(caster_id, slot_index)
				cd_svc.start(caster_id, slot_index, data.cooldown)

			player_node.rpc("_sync_cancel_ability")
			if is_instance_valid(player_node) and player_node.multiplayer.is_server():
				AudioManager.play_sfx(9, Vector2( player_node.global_position.x, player_node.global_position.y))
				# El potenciado lo escucha privado, posicionado en él mismo
				AudioManager.rpc_id(target_peer_id, "play_sfx_on_peer", 9, t_node.global_position.x, t_node.global_position.y)
			print("[ACT] Kris (", caster_id, ") potenció a peer ", target_peer_id,
				  " | slots evolucionados: ", evolved_count)
	)


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return ANIM_DURATION
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return ANIM_DURATION
	if not sprite.sprite_frames.has_animation(anim_name):
		return ANIM_DURATION
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return ANIM_DURATION
	return frame_count / fps
