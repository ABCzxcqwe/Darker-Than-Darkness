extends AbilityBase

const ANIM_FALLBACK: float = 1.2
const PROTECT_REDUCTION: float = 0.6
const STAMINA_MULT: float = 0.7
const NOTIFY_DURATION_SHORT: float = 2.5


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[Purieta] player_node inválido.")
		return

	if player_node.multiplayer.is_server():
		AudioManager.play_sfx_networked.rpc(SfxId.PIROUETTE, player_node.global_position.x, player_node.global_position.y)

	var caster_id: int = player_node.get_multiplayer_authority()
	var combat = GameServiceLocator.combat_mediator
	var cd = GameServiceLocator.cooldown

	if not combat or not cd:
		push_error("[Purieta] Servicios no disponibles.")
		return

	var anim_dur := _get_anim_duration(player_node, data.action_animation)
	combat.apply_root(player_node, anim_dur + 1.0)

	var immunity_ms := int((anim_dur + 0.5) * 1000)
	player_node.invincible_until = Time.get_ticks_msec() + immunity_ms
	player_node.rpc("_sync_invincibility", immunity_ms)

	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, slot_index, player_node.facing_right)

	player_node.get_tree().create_timer(anim_dur).timeout.connect(
		func() -> void:
			if not is_instance_valid(player_node):
				return

			if combat:
				combat.remove_root(player_node)

			_apply_random_effect(player_node, caster_id, data)

			if cd:
				if cd.has_method("release_lock"):
					cd.release_lock(caster_id, slot_index)
				cd.start(caster_id, slot_index, data.cooldown)

			player_node.rpc("_sync_cancel_ability")
	)


func _apply_random_effect(player_node: Node, caster_id: int, data: AbilityData) -> void:
	var health_svc = GameServiceLocator.health
	var status_svc = GameServiceLocator.status_effect
	var combat = GameServiceLocator.combat_mediator

	var effect := randi() % 6
	match effect:
		0:
			if health_svc:
				health_svc.heal(player_node, 30)
				print("[Purieta] Efecto: +30 HP")
			_show_effect_notification(player_node, "TE HAS CURADO", NOTIFY_DURATION_SHORT)
		1:
			if status_svc:
				status_svc.apply(player_node, "speed_boost", {
					"duration": data.cooldown,
					"multiplier": 1.3,
				})
				print("[Purieta] Efecto: Velocidad x1.3")
		2:
			_apply_stamina_reduction(player_node, data.cooldown)
			print("[Purieta] Efecto: Stamina -30%")
			_show_effect_notification(player_node, "LA STAMINA BAJA MAS LENTO", data.cooldown)
		3:
			_apply_protection(player_node, caster_id, data.cooldown)
			print("[Purieta] Efecto: Proteccion (40% daño + death shield)")
			_show_effect_notification(player_node, "LA DEFENSA HA AUMENTADO", data.cooldown)
		4:
			print("[Purieta] Efecto: Nada")
			_show_effect_notification(player_node, "NO HACE NADA", NOTIFY_DURATION_SHORT)
		5:
			if health_svc:
				health_svc.take_damage(player_node, 30)
				print("[Purieta] Efecto: -30 HP")
			_show_effect_notification(player_node, "TE HAS DAÑADO", NOTIFY_DURATION_SHORT)


func _show_effect_notification(player_node: Node, text: String, duration: float) -> void:
	var relay = GameServiceLocator.get_client_relay()
	if is_instance_valid(relay):
		var peer_id := player_node.get_multiplayer_authority()
		relay.rpc("_rpc_custom_effect_applied", peer_id, text, duration)


func _apply_stamina_reduction(player_node: Node, duration: float) -> void:
	var original = player_node.character_data.stamina_sprint_drain
	player_node.character_data.stamina_sprint_drain = original * STAMINA_MULT

	player_node.get_tree().create_timer(duration).timeout.connect(
		func() -> void:
			if not is_instance_valid(player_node):
				return
			player_node.character_data.stamina_sprint_drain = original
	)


func _apply_protection(player_node: Node, caster_id: int, duration: float) -> void:
	var combat = GameServiceLocator.combat_mediator
	if not combat:
		return

	combat.register_protection(caster_id, caster_id,
		combat.ProtectionType.DAMAGE_REDUCE, { "reduction_pct": PROTECT_REDUCTION })
	combat.register_protection(caster_id, caster_id,
		combat.ProtectionType.DEATH_SHIELD, {})

	player_node.get_tree().create_timer(duration).timeout.connect(
		func() -> void:
			if not is_instance_valid(player_node):
				return
			if combat:
				combat.unregister_protection(caster_id, caster_id,
					combat.ProtectionType.DAMAGE_REDUCE)
				combat.unregister_protection(caster_id, caster_id,
					combat.ProtectionType.DEATH_SHIELD)
	)


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return ANIM_FALLBACK
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return ANIM_FALLBACK
	if not sprite.sprite_frames.has_animation(anim_name):
		return ANIM_FALLBACK
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return ANIM_FALLBACK
	return frame_count / fps
