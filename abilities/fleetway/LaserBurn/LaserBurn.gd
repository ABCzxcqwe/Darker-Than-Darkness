extends AbilityBase
## Láser Ígneo — habilidad de prueba de Fleetway Supersonic.
##
## Fase 1 (AIM): el caster queda anclado y carga durante fase2_charge_time.
## Fase 2 (M1): consume TP, crea el rayo y entra en CHANNEL durante
## fase2_channel_time. El rayo sigue el cursor y aplica burn (sin daño directo).
##
## Toda la orquestación de timers, lockouts, movilidad y cancelación vive en
## AbilityRouter. Esta clase solo dispara y corta el rayo.

const BEAM_FALLBACK_LIFETIME: float = 4.0
const BEAM_END_GRACE: float = 0.75

var _beam_ref: WeakRef = null


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return
	if not player_node.multiplayer.is_server():
		return
	if not data.has_fase2 or data.fase2_kind != AbilityData.Fase2Kind.AIM:
		push_warning("[LaserBurn] has_fase2/kind no configurado en el .tres.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()
	var entry_slot: int = slot_index if slot_index >= 0 else 0
	var abs_svc = GameServiceLocator.ability_state

	if abs_svc and abs_svc.is_mode_active(caster_id, entry_slot):
		var md: Dictionary = abs_svc.get_mode_data(caster_id, entry_slot)
		if md.get("fase2", false):
			# El Router ya validó carga/phase antes de despachar. Esta guarda
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
		push_error("[LaserBurn] HitboxService no disponible.")
		AbilityRouter.abort_fase2(caster_id, entry_slot)
		return

	var fire_cost: float = data.fase2_fire_tp_cost
	if fire_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, fire_cost):
			push_warning("[LaserBurn] TP insuficiente en fase 2 para peer ", caster_id)
			AbilityRouter.abort_fase2(caster_id, entry_slot)
			return

	var aim_dir: Vector2 = direction.normalized()
	if aim_dir == Vector2.ZERO:
		aim_dir = _get_fallback_aim(player_node)

	var facing_right: bool = aim_dir.x >= 0.0
	var fire_anim: String = data.fase2_fire_animation
	if fire_anim != "":
		player_node.play_ability_animation(fire_anim, entry_slot, facing_right)

	var anim_dur := _get_anim_duration(player_node, fire_anim)
	AbilityRouter.apply_fase2_fire_iframes(player_node, entry_slot, anim_dur)

	# El rayo mantiene viva esta instancia mediante on_end_callback para poder
	# recibir on_fase2_channel_stop() cuando el Router cierre la canalización.
	AbilityBase.register_active(caster_id, entry_slot, self)

	var channel_time: float = data.fase2_channel_time if data.fase2_channel_enabled else 0.0
	var beam_lifetime: float = channel_time + BEAM_END_GRACE if channel_time > 0.0 else BEAM_FALLBACK_LIFETIME

	var beam = hs.create({
		"attacker_id": caster_id,
		"attacker_node": player_node,
		"type": "projectile",
		"custom_hitbox": true,
		"aim_mode": "fixed",
		"direction": aim_dir,
		"shape_scene": data.ability_scene,
		"damage": 0,
		"attack_type": data.attack_type,
		"team_filter": "enemy",
		"hit_limit": 0,
		"lifetime": beam_lifetime,
		"speed": 0.0,
		"offset": 0.0,
		"hitbox_max_range": data.range_,
		"detect_walls": true,
		"impact_lifetime": 0.0,
		# Lambdas (no Callable.bind): capturan `self` y mantienen viva esta
		# instancia RefCounted durante toda la vida del rayo.
		"on_hit": func(target_node: Node) -> void:
			_on_beam_hit(target_node, data),
		"on_end": func(burn_count: int, reason: String) -> void:
			_on_beam_end(burn_count, reason),
	})

	if not beam:
		push_error("[LaserBurn] No se pudo crear el rayo.")
		AbilityRouter.abort_fase2(caster_id, entry_slot)
		return

	# Referencia fuerte a esta habilidad dentro del hitbox (patrón
	# LanzaProjectile/TopoSpear): mantiene viva la instancia RefCounted
	# mientras el rayo exista y permite recibir on_fase2_channel_stop().
	if beam.has_method("setup_laser"):
		beam.setup_laser(self, player_node, aim_dir, data.burn_reapply_interval)

	# Refuerzo: HitboxService ya asigna estos campos antes de add_child(), pero
	# si el rayo entró al árbol por otra vía (replicación/auto-spawn), nos
	# aseguramos de que el servidor tenga el caster correcto.
	if "attacker_node" in beam:
		beam.attacker_node = player_node
	if "attacker_id" in beam:
		beam.attacker_id = caster_id
	if beam.has_method("server_initialize"):
		beam.server_initialize()

	_beam_ref = weakref(beam)

	if data.fase2_channel_enabled:
		AbilityRouter.start_fase2_channel(caster_id, entry_slot)
	else:
		AbilityRouter.end_fase2_after_fire(caster_id, entry_slot, true)
		var combat_lock = GameServiceLocator.combat_mediator
		if combat_lock and is_instance_valid(player_node):
			combat_lock.apply_root(player_node, anim_dur)

	print("[LaserBurn] Rayo disparado | peer: ", caster_id, " | dir: ", aim_dir,
			" | burn: ", data.burn_dps, " dps / ", data.burn_duration, "s")


func _get_fallback_aim(player_node: Node) -> Vector2:
	var latest = player_node.get("_latest_aim_dir")
	if latest is Vector2 and latest.length_squared() > 0.0:
		return latest.normalized()
	var facing = player_node.get("facing_right")
	if facing is bool:
		return Vector2.RIGHT if facing else Vector2.LEFT
	return Vector2.RIGHT


## Callable del HurtboxDetector del rayo (el hitbox avisa al primer contacto
## con cada objetivo). El burn se aplica aquí, igual que RudeBusterAim aplica
## sus efectos en _on_projectile_hit.
func _on_beam_hit(target: Node, data: AbilityData) -> void:
	if not is_instance_valid(target) or not data:
		return
	var status = GameServiceLocator.status_effect
	if not status or not status.has_method("apply"):
		return
	status.apply(target, "burn", {
		"duration": data.burn_duration,
		"dps": data.burn_dps,
		"tick_interval": data.burn_tick_interval,
		"tick_damage": data.burn_tick_damage,
		"max_stacks": data.burn_max_stacks,
	})
	print("[LaserBurn] Burn aplicado | target: ", target.get_multiplayer_authority(),
			" | dps: ", data.burn_dps, " | dur: ", data.burn_duration)


func _on_beam_end(_burn_count: int, _reason: String) -> void:
	_beam_ref = null


## Hook del Router al terminar/cancelar la canalización.
func on_fase2_channel_stop(reason: String) -> void:
	if _beam_ref:
		var beam = _beam_ref.get_ref()
		if is_instance_valid(beam) and beam.has_method("stop_beam"):
			beam.stop_beam(reason)
	_beam_ref = null
	print("[LaserBurn] Canalización detenida | motivo: ", reason)


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return 0.0
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return 0.0
	if not sprite.sprite_frames.has_animation(anim_name):
		return 0.0
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return 0.0
	return frame_count / fps
