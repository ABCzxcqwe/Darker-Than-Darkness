extends AbilityBase
class_name LanzaAbility

# ── Constantes de la mecánica de la lanza ────────────────────────────
const LANZA_SPEED: float      = 2200.0   # avance de la cabeza (px/s)
const ROOT_DURATION: float    = 20.0    # root durante toda la habilidad (se libera al resolver)
const IFRAME_DURATION: float  = 2.5     # invencibilidad al inicio de la habilidad (seg)
const CANCEL_GRACE_SEC: float = 1.5     # ventana donde E no cancela (anti doble-press)

# Evita que el RefCounted sea recolectado mientras la habilidad está activa.
static var _keep_alive: Array = []


static func find_active_for(player_node: Node, slot_index: int) -> LanzaAbility:
	for inst in _keep_alive:
		if inst._active and inst._player_node == player_node and inst._slot_index == slot_index:
			return inst
	return null


var _active: bool = false
var _canceled: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _lance: Node = null
var _cd_svc: Node = null
var _combat: Node = null
var _activated_at_msec: int = 0


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	_player_node = player_node
	_caster_id = player_node.get_multiplayer_authority()
	_data = data
	_slot_index = slot_index
	_active = true

	var tp_svc = GameServiceLocator.tp
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(_caster_id, data.tp_cost):
			_fail_cleanup()
			return

	_cd_svc = GameServiceLocator.cooldown
	_combat = GameServiceLocator.combat_mediator

	var facing_right: bool = direction.x >= 0.0 or direction == Vector2.ZERO

	# King se queda en el último frame de la animación hasta resolver.
	player_node.play_ability_animation(data.action_animation, _slot_index, facing_right)
	player_node.hold_ability_anim = true
	player_node.rpc("_sync_ability_hold", true)

	if _combat:
		_combat.apply_root(_player_node, ROOT_DURATION)

	# Iframes al inicio: King se vuelve invencible mientras apunta la lanza.
	_grant_iframes()

	# Apuntar la lanza en la dirección del apuntado (mouse).
	var lance_dir: Vector2 = direction.normalized()
	if lance_dir == Vector2.ZERO:
		lance_dir = Vector2.RIGHT if facing_right else Vector2.LEFT

	_activated_at_msec = Time.get_ticks_msec()
	_keep_alive.append(self)
	AbilityBase.register_active(_caster_id, _slot_index, self)

	var spawn_delay: float = data.spawn_delay if data.spawn_delay > 0.0 else 0.0
	if player_node.get_tree():
		player_node.get_tree().create_timer(spawn_delay).timeout.connect(
			func(): _spawn_lance(lance_dir)
		)

	print("[Lanza] Habilidad iniciada | peer: ", _caster_id, " | dir: ", lance_dir, " | grace: ", CANCEL_GRACE_SEC, "s")


func _grant_iframes() -> void:
	if not is_instance_valid(_player_node):
		return
	var ms: int = int(IFRAME_DURATION * 1000.0)
	_player_node.invincible_until = Time.get_ticks_msec() + ms
	_player_node.rpc("_sync_invincibility", ms)


func _caster_is_stunned() -> bool:
	var status = GameServiceLocator.status_effect
	if status and status.has_method("is_stunned"):
		return status.is_stunned(_caster_id)
	if is_instance_valid(_player_node):
		return _player_node.active_effects.has("stun")
	return false


func _spawn_lance(lance_dir: Vector2) -> void:
	if not _active or not is_instance_valid(_player_node):
		_resolve(false)
		return

	# Si King fue stuneado durante el spawn_delay, la habilidad se cancela.
	if _caster_is_stunned():
		print("[Lanza] Cancelada — King stuneado durante el delay | peer: ", _caster_id)
		_resolve(false)
		return

	var hs = GameServiceLocator.hitbox
	if not hs:
		_resolve(false)
		return

	var portal := hs.create({
		"attacker_id": _caster_id,
		"attacker_node": _player_node,
		"type": "projectile",
		"aim_mode": "fixed",
		"direction": lance_dir,
		"shape_scene": _data.ability_scene if _data else null,
		"attack_type": _data.attack_type if _data else "normal",
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
		_resolve(false)
		return

	_lance = portal
	var origin: Vector2 = _player_node.global_position
	portal.global_position = origin
	portal.origin = origin
	portal.setup_lanza(self, _player_node, lance_dir)

	print("[Lanza] Lanza lanzada desde ", origin)


# ── Resolución (llamada por el proyectil) ────────────────────────────
func resolve(success: bool) -> void:
	_resolve(success)


func can_cancel_now() -> bool:
	if not _active:
		return false
	return Time.get_ticks_msec() - _activated_at_msec >= int(CANCEL_GRACE_SEC * 1000.0)


# ── Cancelación manual (presionar "E" de nuevo) ──────────────────────
func cancel_early() -> void:
	if not _active:
		return
	if not can_cancel_now():
		var elapsed := (Time.get_ticks_msec() - _activated_at_msec) / 1000.0
		print("[Lanza] Cancel bloqueado por grace period | elapsed: ", elapsed, "s / ", CANCEL_GRACE_SEC, "s")
		return
	_canceled = true
	if is_instance_valid(_lance) and _lance.has_method("_resolve"):
		_lance._resolve(false)
	else:
		_resolve(false)


func _resolve(success: bool) -> void:
	if not _active:
		return
	_active = false

	if _combat and is_instance_valid(_player_node):
		_combat.remove_root(_player_node)

	if is_instance_valid(_player_node):
		_player_node.hold_ability_anim = false
		_player_node.rpc("_sync_cancel_ability")

	# Cooldown: si conectó usa el normal; si falló en blanco, el cooldown_fail.
	# Si la canceló el jugador, cuenta como usada → cooldown completo.
	var cd: float = _data.cooldown
	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
		if not success and not _canceled and _data.cooldown_fail > 0.0:
			cd = _data.cooldown_fail
		_cd_svc.start(_caster_id, _slot_index, cd)

	print("[Lanza] Resuelta | peer: ", _caster_id, " | éxito: ", success, " | cooldown: ", cd)
	AbilityBase.unregister_active(_caster_id, _slot_index)
	_keep_alive.erase(self)


func _fail_cleanup() -> void:
	_active = false
	AbilityBase.unregister_active(_caster_id, _slot_index)
	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
	print("[Lanza] Fallo en activación | peer: ", _caster_id)
