extends AbilityBase

## Rude Buster en dos fases (TEST Susie LMS, base del sistema fase2 genérico).
## Fase 1 (sin fase2 activa): entra en fase2 — root (sin movimiento),
## free_look + aiming sync para M1/X en el cliente, SIN animación bloqueante
## (el estado se queda en IDLE para que el Router acepte la fase 2).
## Fase 2 (fase2 activa): M1 dispara el proyectil (gasta TP aquí, solo aquí).
## X cancela vía AbilityRouter.cancel_aim. Timeout / daño / stun (según
## flags del .tres) limpian solos.

const PROJECTILE_SPEED: float = 1000.0
const PROJECTILE_LIFETIME: float = 2.0
const IMPACT_LIFETIME: float = 0.3
const SPAWN_DELAY: float = 0.5

# Mantiene viva la instancia mientras la fase 2 sigue abierta (timeout y
# señales de daño/stun). Patrón igual que Teleport._keep_alive.
static var _keep_alive: Array = []


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
			_fire(player_node, data, direction, entry_slot)
			return

	_enter_fase2(player_node, data, entry_slot)


# ── Fase 1: entrar ────────────────────────────────────────────────────────

func _enter_fase2(player_node: Node, data: AbilityData, entry_slot: int) -> void:
	var caster_id: int = player_node.get_multiplayer_authority()
	var abs_svc = GameServiceLocator.ability_state
	var combat = GameServiceLocator.combat_mediator
	var cd = GameServiceLocator.cooldown

	var timeout: float = data.fase2_timeout if data.fase2_timeout > 0.0 else 12.0

	if combat:
		combat.apply_root(player_node, timeout)

	if abs_svc:
		abs_svc.activate_mode(caster_id, entry_slot, {
			"fase2": true,
			"kind": int(data.fase2_kind),
			"entry_slot": entry_slot,
			"cancel_on_damage": data.fase2_cancel_on_damage,
			"cancel_on_stun": data.fase2_cancel_on_stun,
		})

	# Retícula + M1/X en el cliente (Player.gd rama fase2). Se usa _sync_fase2
	# (any_peer): _sync_aiming_mode es authority y el motor descarta la llamada
	# del servidor en clientes remotos.
	player_node.rpc("_sync_effect", "free_look", true)
	player_node.rpc("_sync_fase2", entry_slot, true)

	# Pose de apuntado mantenida: ABILITY + animación en loop no auto-resetea
	# (PlayerAnimationComponent) y el Router ya no bloquea al slot en fase2,
	# así que es seguro. Al salir se restaura con _sync_cancel_ability.
	var pose: String = data.prepare_animation if data.prepare_animation != "" else "idle_prepare"
	player_node.play_ability_animation(pose, entry_slot, player_node.facing_right)

	# El Router hizo start_lock(entry) antes del dispatch: se libera para
	# que la fase 2 (mismo slot) quede pulsable. El cooldown real cae al
	# disparar (on_hit/on_end) o al cancelar (cancel_aim).
	if cd and cd.has_method("release_lock"):
		cd.release_lock(caster_id, entry_slot)

	_connect_interrupts(player_node, caster_id, entry_slot)

	if not _keep_alive.has(self):
		_keep_alive.append(self)
	var tree := player_node.get_tree()
	if tree:
		tree.create_timer(timeout + 0.5).timeout.connect(_on_timeout.bind(caster_id, entry_slot))

	print("[RudeBusterAim] Fase2 abierta | peer: ", caster_id, " | slot: ", entry_slot)


func _connect_interrupts(player_node: Node, caster_id: int, entry_slot: int) -> void:
	var combat = GameServiceLocator.combat_mediator
	if not combat:
		return
	if combat.has_signal("stun_applied") and not combat.stun_applied.is_connected(_on_stun):
		combat.stun_applied.connect(_on_stun)
	if combat.has_signal("damage_dealt") and not combat.damage_dealt.is_connected(_on_damage):
		combat.damage_dealt.connect(_on_damage)


func _on_stun(target_id: int, _duration: float) -> void:
	_maybe_interrupt(target_id, "stun")


func _on_damage(_attacker_id: int, target_id: int, _dmg: int, _atk_type: String) -> void:
	_maybe_interrupt(target_id, "damage")


func _maybe_interrupt(caster_id: int, cause: String) -> void:
	var abs_svc = GameServiceLocator.ability_state
	if not abs_svc:
		return
	for slot_index in range(5):
		if not abs_svc.is_mode_active(caster_id, slot_index):
			continue
		var md: Dictionary = abs_svc.get_mode_data(caster_id, slot_index)
		if not md.get("fase2", false):
			continue
		var wants_exit: bool = false
		if cause == "stun" and bool(md.get("cancel_on_stun", true)):
			wants_exit = true
		if cause == "damage" and bool(md.get("cancel_on_damage", false)):
			wants_exit = true
		if wants_exit:
			print("[RudeBusterAim] Fase2 interrumpida por ", cause, " | peer: ", caster_id)
			_exit_fase2(caster_id, slot_index, true)


func _on_timeout(caster_id: int, entry_slot: int) -> void:
	var abs_svc = GameServiceLocator.ability_state
	if not abs_svc or not abs_svc.is_mode_active(caster_id, entry_slot):
		_keep_alive.erase(self)
		return
	var md: Dictionary = abs_svc.get_mode_data(caster_id, entry_slot)
	if not md.get("fase2", false):
		_keep_alive.erase(self)
		return
	print("[RudeBusterAim] Timeout, cerrando fase2 | peer: ", caster_id)
	_exit_fase2(caster_id, entry_slot, true)
	_keep_alive.erase(self)


# ── Fase 2: disparar ──────────────────────────────────────────────────────

func _fire(player_node: Node, data: AbilityData, direction: Vector2, entry_slot: int) -> void:
	var caster_id: int = player_node.get_multiplayer_authority()
	var hs = GameServiceLocator.hitbox
	var tp_svc = GameServiceLocator.tp
	var cd = GameServiceLocator.cooldown
	if not hs:
		push_error("[RudeBusterAim] HitboxService no disponible.")
		_exit_fase2(caster_id, entry_slot, true)
		return

	var fire_cost: float = data.fase2_fire_tp_cost
	var fire_cd: float = data.fase2_fire_cooldown
	var fire_cd_fail: float = data.fase2_fire_cooldown_fail if data.fase2_fire_cooldown_fail > 0.0 else fire_cd
	var dmg: int = int(data.base_damage * data.evo_damage_multiplier)
	var atk_type: String = data.attack_type
	var stun_dur: float = data.stun_duration + data.evo_status_duration_bonus
	var tp_reward: float = data.tp_reward

	if fire_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, fire_cost):
			push_warning("[RudeBusterAim] TP insuficiente en fase 2 para peer ", caster_id)
			_exit_fase2(caster_id, entry_slot, false)
			if cd and cd.has_method("release_lock"):
				cd.release_lock(caster_id, entry_slot)
			return

	var proj_dir: Vector2 = direction.normalized()
	if proj_dir == Vector2.ZERO:
		proj_dir = Vector2.RIGHT if player_node.facing_right else Vector2.LEFT

	var facing_right: bool = proj_dir.x >= 0.0
	var fire_anim: String = data.fase2_fire_animation
	if fire_anim != "":
		player_node.play_ability_animation(fire_anim, entry_slot, facing_right)

	var anim_dur := _get_anim_duration(player_node, fire_anim)

	# Cierra la fase 2 al disparar (barra y modo se restauran ya) pero SIN
	# pisar la animación (keep_anim) y plantando los pies hasta que sale el
	# proyectil. El lock del entry se mantiene hasta on_hit/on_end.
	_exit_fase2(caster_id, entry_slot, false, true)
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
					"on_hit": func(target_node: Node) -> void:
						if not is_instance_valid(target_node):
							return
						if player_node.multiplayer.is_server():
							AudioManager.play_sfx_networked.rpc(SfxId.RUDEBUSTER_HIT, target_node.global_position.x, target_node.global_position.y)
						if dmg > 0:
							var combat_hit = GameServiceLocator.combat_mediator
							if combat_hit:
								combat_hit.apply_damage(player_node, target_node, dmg, atk_type)
						if target_node.is_in_group("killer"):
							var combat_cc = GameServiceLocator.combat_mediator
							if combat_cc and stun_dur > 0.0:
								combat_cc.apply_stun(target_node, stun_dur)
							if tp_reward > 0.0 and tp_svc:
								tp_svc.add_tp_custom(caster_id, tp_reward)
						if cd and cd.has_method("release_lock"):
							cd.release_lock(caster_id, entry_slot)
						if cd:
							cd.start(caster_id, entry_slot, fire_cd),
					"on_end": func(hit_count: int) -> void:
						if hit_count == 0:
							if cd and cd.has_method("release_lock"):
								cd.release_lock(caster_id, entry_slot)
							if cd:
								cd.start(caster_id, entry_slot, fire_cd_fail)
						print("[RudeBusterAim] Proyectil expiró | golpes: ", hit_count)
				})
				print("[RudeBusterAim] Fase 2 disparada | peer: ", caster_id, " | dir: ", proj_dir, " | dmg: ", dmg)
		)

	_keep_alive.erase(self)


# ── Salida común (NO toca el lock del entry: lo gestiona quien llama) ─────

func _exit_fase2(caster_id: int, entry_slot: int, with_cancel_cd: bool, keep_anim: bool = false) -> void:
	var abs_svc = GameServiceLocator.ability_state
	var combat = GameServiceLocator.combat_mediator
	var cd = GameServiceLocator.cooldown
	var player_node: Node = PlayerRegistry.get_player(caster_id)
	if abs_svc and abs_svc.is_mode_active(caster_id, entry_slot):
		abs_svc.deactivate_mode(caster_id, entry_slot)
	if combat and is_instance_valid(player_node):
		combat.remove_root(player_node)
	if is_instance_valid(player_node):
		player_node.rpc("_sync_fase2", entry_slot, false)
		player_node.rpc("_sync_effect", "free_look", false)
		# En ruta de disparo no se pisa la animación: el timer de anim_dur
		# ya programa el _sync_cancel_ability al terminar el tiro.
		if not keep_anim:
			player_node.rpc("_sync_cancel_ability")
	if with_cancel_cd and cd and cd.has_method("release_lock"):
		cd.release_lock(caster_id, entry_slot)
		var cancel_cd: float = 2.0
		if is_instance_valid(player_node):
			var pdata = _get_entry_data(player_node, entry_slot)
			if pdata and "fase2_cancel_cd" in pdata and pdata.fase2_cancel_cd > 0.0:
				cancel_cd = pdata.fase2_cancel_cd
		if cancel_cd > 0.0:
			cd.start(caster_id, entry_slot, cancel_cd)


func _get_entry_data(player_node: Node, entry_slot: int) -> AbilityData:
	var ch = player_node.get("character_data")
	if not ch:
		return null
	var slots: Array = ch.ability_slots
	if entry_slot < 0 or entry_slot >= slots.size():
		return null
	return slots[entry_slot]


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
