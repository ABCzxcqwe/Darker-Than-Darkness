extends AbilityBase

## Lanza de King en formato Fase 2 (AIM).
##
## Flujo:
##   1. Activar -> AIM (12 TP para entrar, no se consumen).
##   2. M1 -> dispara la lanza (12 TP) y el AIM queda abierto para que X
##      pueda cancelar durante el recorrido/hook.
##   3. X durante AIM/recorrido/hook -> la lanza vuelve a King.
##   4. X durante el agarre -> bloqueado. Un stun sí cancela y suelta.
##
## Cooldowns:
##   - 3 s: falla, no acierta, o se cancela durante el recorrido / spawn.
##   - 6.5 s: hook completado, o cancelado durante el arrastre a la pared.
##   - 20 s: agarre completado o interrumpido por stun.

const LANZA_SPEED: float = 4400.0
const ROOT_DURATION: float = 20.0
const IFRAME_DURATION: float = 2.5
const DEFAULT_SLOT: int = 1
const SPAWN_DELAY_FALLBACK: float = 1.0

var _active: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _lance: Node = null
var _cd_svc: Node = null
var _combat: Node = null
var _lance_dir: Vector2 = Vector2.RIGHT
var _outcome_resolved: bool = false
var _cooldown_applied: bool = false


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return
	if not player_node.multiplayer.is_server():
		return
	if not data.has_fase2 or data.fase2_kind != AbilityData.Fase2Kind.AIM:
		push_warning("[LanzaAim] has_fase2/kind no configurado en el .tres.")
		return

	var caster_id: int = PlayerLifecycleManager.get_owner_peer_id(player_node)
	var entry_slot: int = slot_index if slot_index >= 0 else DEFAULT_SLOT
	var abs_svc = GameServiceLocator.ability_state

	if abs_svc and abs_svc.is_mode_active(caster_id, entry_slot):
		var md: Dictionary = abs_svc.get_mode_data(caster_id, entry_slot)
		if md.get("fase2", false):
			if String(md.get("phase", "aim")) != "aim":
				return
			if Time.get_ticks_msec() < int(md.get("charge_ready_ms", 0)):
				return
			_fire(player_node, data, direction, entry_slot)
			return

	AbilityRouter.start_fase2(player_node, data, entry_slot)


# ── Disparo ─────────────────────────────────────────────────────────────────

func _fire(player_node: Node, data: AbilityData, direction: Vector2, entry_slot: int) -> void:
	var caster_id: int = PlayerLifecycleManager.get_owner_peer_id(player_node)
	var tp_svc = GameServiceLocator.tp
	if data.fase2_fire_tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.fase2_fire_tp_cost):
			AbilityRouter.cancel_aim(caster_id, entry_slot)
			return

	_player_node = player_node
	_caster_id = caster_id
	_slot_index = entry_slot
	_data = data
	_cd_svc = GameServiceLocator.cooldown
	_combat = GameServiceLocator.combat_mediator
	_active = true
	_outcome_resolved = false
	_cooldown_applied = false

	var facing_right: bool = direction.x >= 0.0 or direction == Vector2.ZERO
	var fire_anim: String = data.fase2_fire_animation
	if fire_anim != "":
		player_node.play_ability_animation(fire_anim, entry_slot, facing_right)
	player_node.rpc("_sync_fase2_firing", true)
	player_node.hold_ability_anim = true
	player_node.rpc("_sync_ability_hold", true)

	if _combat:
		_combat.apply_root(player_node, ROOT_DURATION)

	_grant_iframes()

	_lance_dir = direction.normalized()
	if _lance_dir == Vector2.ZERO:
		_lance_dir = Vector2.RIGHT if facing_right else Vector2.LEFT

	AbilityBase.register_active(caster_id, entry_slot, self)

	# El AIM se mantiene abierto a propósito: X debe poder cancelar durante
	# el recorrido/hook. register_fase2_shot bloquea un segundo disparo y
	# clear_fase2_timeout evita que el timeout del AIM corte la lanza en vuelo.
	AbilityRouter.register_fase2_shot(caster_id, entry_slot)
	AbilityRouter.clear_fase2_timeout(caster_id, entry_slot)

	var spawn_delay: float = data.spawn_delay if data.spawn_delay > 0.0 else SPAWN_DELAY_FALLBACK
	player_node.get_tree().create_timer(spawn_delay).timeout.connect(
		func(): _spawn_lance()
	)

	print("[LanzaAim] Habilidad iniciada | peer: ", caster_id,
		" | dir: ", _lance_dir, " | spawn: ", spawn_delay)


func _grant_iframes() -> void:
	if not is_instance_valid(_player_node):
		return
	var ms: int = int(IFRAME_DURATION * 1000.0)
	_player_node.invincible_until = Time.get_ticks_msec() + ms
	_player_node.rpc("_sync_invincibility", ms)


func _spawn_lance() -> void:
	if not _active or not is_instance_valid(_player_node):
		return
	if not _data:
		resolve_with_reason("fail")
		return

	var hs = GameServiceLocator.hitbox
	if not hs:
		resolve_with_reason("fail")
		return

	var portal := hs.create({
		"attacker_id": _caster_id,
		"attacker_node": _player_node,
		"type": "projectile",
		"aim_mode": "fixed",
		"direction": _lance_dir,
		"shape_scene": _data.ability_scene,
		"attack_type": _data.attack_type,
		"hit_limit": 0,
		"team_filter": "enemy",
		"lifetime": ROOT_DURATION,
		"speed": LANZA_SPEED,
		"hitbox_max_range": 0.0,
		"offset": 0.0,
		"custom_hitbox": true,
		"detect_walls": true,
	})

	if not portal:
		resolve_with_reason("fail")
		return

	_lance = portal
	var origin_pos: Vector2 = _player_node.global_position
	portal.global_position = origin_pos
	portal.origin = origin_pos
	portal.setup_lanza(self, _player_node, _lance_dir)

	print("[LanzaAim] Lanza lanzada desde ", origin_pos)


# ── Hook desde el proyectil ─────────────────────────────────────────────────

## La lanza atrapó a alguien: X deja de poder cancelar.
func on_lance_grab() -> void:
	AbilityRouter.mark_fase2_firing(_caster_id, _slot_index, 999.0)


## Llamado por LanzaAimProjectile al terminar o retraerse.
func resolve_with_reason(reason: String) -> void:
	if _outcome_resolved:
		return
	_outcome_resolved = true

	var cooldown_value := _cooldown_for(reason)
	_finish(cooldown_value)

	# Cerrar el AIM si sigue abierto (en cancel/stun ya se cerró).
	if AbilityRouter.is_fase2_active(_caster_id, _slot_index):
		AbilityRouter.end_fase2_after_fire(_caster_id, _slot_index, true)

	print("[LanzaAim] Resuelta | peer: ", _caster_id, " | motivo: ", reason,
		" | cooldown: ", cooldown_value)


func _cooldown_for(reason: String) -> float:
	if reason.contains("grab"):
		return 20.0
	if reason.contains("hook"):
		return 6.5
	return 3.0


## Hook de AbilityFase2 al cerrar/cancelar el AIM.
func on_fase2_end(reason: String, shots_fired: int) -> void:
	if _outcome_resolved:
		return
	if shots_fired <= 0:
		# Cancelación/stun antes de disparar: el router ya aplicó 3 s.
		return

	if is_instance_valid(_lance):
		# "stun" para que el proyectil distinga stun de cancelación manual.
		var cancel_reason := "stun" if reason == "stun" else "cancel"
		_lance.cancel_with_reason(cancel_reason)
	else:
		# Sigue en el spawn delay: abortar el spawn y limpiar root/anims.
		_finish(3.0)


func cancel_early() -> void:
	if not _active:
		return
	if AbilityRouter.is_fase2_active(_caster_id, _slot_index):
		AbilityRouter.cancel_aim(_caster_id, _slot_index)
	elif is_instance_valid(_lance):
		_lance.cancel_with_reason("cancel")


func _finish(cooldown_value: float) -> void:
	if _cooldown_applied:
		return
	_cooldown_applied = true
	_active = false

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_fase2_firing", false)
		if _combat:
			_combat.remove_root(_player_node)
		_player_node.hold_ability_anim = false
		_player_node.rpc("_sync_cancel_ability")

	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
		_cd_svc.start(_caster_id, _slot_index, cooldown_value)

	print("[LanzaAim] Fin | peer: ", _caster_id, " | cooldown: ", cooldown_value)
