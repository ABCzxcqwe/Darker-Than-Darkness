extends AbilityBase

## Rude Buster en dos fases (base del sistema fase2 genérico).
##
## La orquestación (timers, lockout, movimiento, cancelaciones, i-frames)
## vive en AbilityRouter. Esta habilidad solo decide:
##   - cuándo entrar en fase 2,
##   - qué efecto ejecutar al disparar,
##   - cuándo y con qué cooldown termina el disparo.
##
## Fase 1: abre AIM (M1 dispara, X cancela) sin gastar TP.
## Fase 2: consume TP, dispara el proyectil y cierra la fase.

const PROJECTILE_SPEED: float = 1000.0
const PROJECTILE_LIFETIME: float = 2.0
const IMPACT_LIFETIME: float = 0.3
const SPAWN_DELAY: float = 0.5


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return
	if not player_node.multiplayer.is_server():
		return
	if not data.has_fase2 or data.fase2_kind != AbilityData.Fase2Kind.AIM:
		push_warning("[RudeBusterAim] has_fase2/kind no configurado en el .tres.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()
	var entry_slot: int = slot_index if slot_index >= 0 else 1
	var abs_svc = GameServiceLocator.ability_state

	if abs_svc and abs_svc.is_mode_active(caster_id, entry_slot):
		var md: Dictionary = abs_svc.get_mode_data(caster_id, entry_slot)
		if md.get("fase2", false):
			# El Router ya valida carga/phase antes de despachar; esta guarda
			# evita disparar si la habilidad se invoca por otra vía.
			if String(md.get("phase", "aim")) != "aim":
				return
			if Time.get_ticks_msec() < int(md.get("charge_ready_ms", 0)):
				return
			_fire(player_node, data, direction, entry_slot)
			return

	AbilityRouter.start_fase2(player_node, data, entry_slot)


# ── Disparo ─────────────────────────────────────────────────────────────────

func _fire(player_node: Node, data: AbilityData, direction: Vector2, entry_slot: int) -> void:
	var caster_id: int = player_node.get_multiplayer_authority()
	var hs = GameServiceLocator.hitbox
	var tp_svc = GameServiceLocator.tp
	if not hs:
		push_error("[RudeBusterAim] HitboxService no disponible.")
		AbilityRouter.abort_fase2(caster_id, entry_slot)
		return

	var fire_cost: float = data.fase2_fire_tp_cost
	var fire_cd: float = data.fase2_fire_cooldown
	var fire_cd_fail: float = data.fase2_fire_cooldown_fail if data.fase2_fire_cooldown_fail > 0.0 else fire_cd
	var dmg: int = int(data.base_damage * data.evo_damage_multiplier)
	var atk_type: String = data.attack_type
	var stun_dur: float = data.stun_duration + data.evo_status_duration_bonus
	var tp_reward: float = data.tp_reward
	var channel_enabled: bool = data.fase2_channel_enabled

	if fire_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, fire_cost):
			push_warning("[RudeBusterAim] TP insuficiente en fase 2 para peer ", caster_id)
			AbilityRouter.abort_fase2(caster_id, entry_slot)
			return

	var proj_dir: Vector2 = direction.normalized()
	if proj_dir == Vector2.ZERO:
		proj_dir = Vector2.RIGHT if player_node.facing_right else Vector2.LEFT

	var facing_right: bool = proj_dir.x >= 0.0
	var fire_anim: String = data.fase2_fire_animation
	if fire_anim != "":
		player_node.play_ability_animation(fire_anim, entry_slot, facing_right)

	var anim_dur := _get_anim_duration(player_node, fire_anim)

	# I-frames calculados antes de cerrar la fase: el Router necesita leer
	# mode_data (fire_iframes_mode / extra).
	AbilityRouter.apply_fase2_fire_iframes(player_node, entry_slot, anim_dur)

	# La instancia que dispara queda registrada para poder recibir
	# on_fase2_channel_stop() si la habilidad tiene fase CHANNEL.
	AbilityBase.register_active(caster_id, entry_slot, self)

	if data.fase2_channel_enabled:
		# Fase 3: el Router mantiene el modo, aplica movilidad de canal y
		# programa el fin. La habilidad debe cortar su efecto en
		# on_fase2_channel_stop(reason).
		AbilityRouter.start_fase2_channel(caster_id, entry_slot)
	else:
		# Cierra la fase al disparar (barra y modo se restauran) pero SIN pisar
		# la animación (keep_anim). El lock del entry se mantiene hasta
		# on_hit/on_end.
		AbilityRouter.end_fase2_after_fire(caster_id, entry_slot, true)

		var combat_lock = GameServiceLocator.combat_mediator
		if combat_lock and is_instance_valid(player_node):
			combat_lock.apply_root(player_node, anim_dur + SPAWN_DELAY)

		if is_instance_valid(player_node) and player_node.multiplayer.is_server():
			player_node.get_tree().create_timer(anim_dur).timeout.connect(
				func() -> void:
					if is_instance_valid(player_node):
						player_node.rpc("_sync_cancel_ability")
			)

	if is_instance_valid(player_node) and player_node.multiplayer.is_server():
		player_node.get_tree().create_timer(SPAWN_DELAY).timeout.connect(
			func() -> void:
				if not is_instance_valid(player_node) or not is_instance_valid(hs):
					return
				AudioManager.play_sfx_networked.rpc(SfxId.RUDEBUSTER_SWING, player_node.global_position.x, player_node.global_position.y)
				hs.create({
					"attacker_id": caster_id,
					"attacker_node": player_node,
					"type": "projectile",
					"aim_mode": "fixed",
					"direction": proj_dir,
					"shape_scene": data.ability_scene,
					"damage": dmg,
					"attack_type": atk_type,
					"team_filter": "enemy",
					"hit_limit": 1,
					"lifetime": PROJECTILE_LIFETIME,
					"speed": PROJECTILE_SPEED,
					"offset": 0.0,
					"impact_lifetime": IMPACT_LIFETIME,
					# Lambdas (no Callable.bind): capturan `self` y mantienen viva
					# esta instancia RefCounted mientras el proyectil exista.
					"on_hit": func(target_node: Node) -> void:
						_on_projectile_hit(target_node, caster_id, entry_slot,
								player_node, dmg, atk_type, stun_dur, tp_reward,
								fire_cd, channel_enabled),
					"on_end": func(hit_count: int) -> void:
						_on_projectile_end(hit_count, caster_id, entry_slot,
								fire_cd_fail, channel_enabled),
				})
				print("[RudeBusterAim] Fase 2 disparada | peer: ", caster_id, " | dir: ", proj_dir, " | dmg: ", dmg)
		)


## Callable del proyectil. Los argumentos bound se agregan después de los que
## envía HitboxService (target_node).
func _on_projectile_hit(target_node: Node, caster_id: int, entry_slot: int,
		player_node: Node, dmg: int, atk_type: String, stun_dur: float,
		tp_reward: float, fire_cd: float, channel_enabled: bool) -> void:
	if not is_instance_valid(target_node):
		return
	if is_instance_valid(player_node) and player_node.multiplayer.is_server():
		AudioManager.play_sfx_networked.rpc(SfxId.RUDEBUSTER_HIT,
				target_node.global_position.x, target_node.global_position.y)
	if dmg > 0 and is_instance_valid(player_node):
		var combat_hit = GameServiceLocator.combat_mediator
		if combat_hit:
			combat_hit.apply_damage(player_node, target_node, dmg, atk_type)
	if target_node.is_in_group("killer"):
		var combat_cc = GameServiceLocator.combat_mediator
		if combat_cc and stun_dur > 0.0:
			combat_cc.apply_stun(target_node, stun_dur)
		var tp_svc = GameServiceLocator.tp
		if tp_reward > 0.0 and tp_svc:
			tp_svc.add_tp_custom(caster_id, tp_reward)
	# En CHANNEL el lock y el cooldown los gestiona el Router al terminar.
	if not channel_enabled:
		var cd = GameServiceLocator.cooldown
		if cd and cd.has_method("release_lock"):
			cd.release_lock(caster_id, entry_slot)
		if cd:
			cd.start(caster_id, entry_slot, fire_cd)


## Callable de fin del proyectil. HitboxService pasa hit_count.
func _on_projectile_end(hit_count: int, caster_id: int, entry_slot: int,
		fire_cd_fail: float, channel_enabled: bool) -> void:
	if not channel_enabled and hit_count == 0:
		var cd = GameServiceLocator.cooldown
		if cd and cd.has_method("release_lock"):
			cd.release_lock(caster_id, entry_slot)
		if cd:
			cd.start(caster_id, entry_slot, fire_cd_fail)
	print("[RudeBusterAim] Proyectil expiró | golpes: ", hit_count)


## Hook de fase CHANNEL. RudeBusterAim no canaliza; una variante que active
## fase2_channel_enabled debe sobreescribir esto para cortar su rayo/ticks/VFX.
func on_fase2_channel_stop(_reason: String) -> void:
	pass


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return PROJECTILE_LIFETIME
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return PROJECTILE_LIFETIME
	if not sprite.sprite_frames.has_animation(anim_name):
		return PROJECTILE_LIFETIME
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return PROJECTILE_LIFETIME
	return frame_count / fps
