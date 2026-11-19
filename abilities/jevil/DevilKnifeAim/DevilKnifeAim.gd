extends AbilityBase

## Devil Knife en formato Fase 2 (AIM).
##
## Normal: 1 disparo, 30 TP.
## En Rage: 2 disparos, 15 TP cada uno.
## Cooldown: 20 s al cerrar el AIM.
## X cancela durante el AIM, bloqueado durante la animación de lanzamiento.

const RAGE_SLOT_INDEX: int = 4
const RAGE_SHOT_COST: float = 15.0
const NORMAL_SHOT_COST: float = 30.0
const COOLDOWN: float = 20.0
const ANIM_FALLBACK: float = 0.4

static var _keep_alive: Array = []

var _caster_id: int = -1
var _slot_index: int = -1
var _player_node: Node = null
var _data: AbilityData = null
var _cd_svc: Node = null
var _cooldown_applied: bool = false
var _anim_token: int = 0


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return
	if not player_node.multiplayer.is_server():
		return
	if not data.has_fase2 or data.fase2_kind != AbilityData.Fase2Kind.AIM:
		push_warning("[DevilKnifeAim] has_fase2/kind no configurado en el .tres.")
		return

	var caster_id: int = PlayerLifecycleManager.get_owner_peer_id(player_node)
	var entry_slot: int = slot_index if slot_index >= 0 else 1
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

	var opened: bool = AbilityRouter.start_fase2(player_node, data, entry_slot)
	if opened and _is_rage(caster_id):
		# En Rage el AIM permite un segundo disparo.
		AbilityRouter.set_fase2_max_shots(caster_id, entry_slot, 2)


func _is_rage(caster_id: int) -> bool:
	var abs_svc = GameServiceLocator.ability_state
	return abs_svc != null and abs_svc.has_method("is_mode_active") \
		and abs_svc.is_mode_active(caster_id, RAGE_SLOT_INDEX)


func _fire(player_node: Node, data: AbilityData, direction: Vector2, entry_slot: int) -> void:
	var caster_id: int = PlayerLifecycleManager.get_owner_peer_id(player_node)
	var hs = GameServiceLocator.hitbox
	var tp_svc = GameServiceLocator.tp
	var cd = GameServiceLocator.cooldown
	if not hs or not tp_svc:
		AbilityRouter.abort_fase2(caster_id, entry_slot)
		return

	var is_rage := _is_rage(caster_id)
	var fire_cost: float = RAGE_SHOT_COST if is_rage else NORMAL_SHOT_COST
	if not tp_svc.consume_tp(caster_id, fire_cost):
		AbilityRouter.cancel_aim(caster_id, entry_slot)
		return

	_caster_id = caster_id
	_slot_index = entry_slot
	_player_node = player_node
	_data = data
	_cd_svc = cd
	_cooldown_applied = false

	var proj_dir: Vector2 = direction.normalized()
	if proj_dir == Vector2.ZERO:
		proj_dir = Vector2.RIGHT if player_node.facing_right else Vector2.LEFT

	var anim_name: String = data.fase2_fire_animation
	if anim_name != "":
		player_node.play_ability_animation(anim_name, entry_slot, proj_dir.x >= 0.0)
	var anim_dur := _get_anim_duration(player_node, anim_name)

	# X no puede cancelar durante el lanzamiento.
	AbilityRouter.mark_fase2_firing(caster_id, entry_slot, anim_dur)
	player_node.rpc("_sync_fase2_firing", true)

	hs.create({
		"attacker_id": caster_id,
		"attacker_node": player_node,
		"type": "projectile",
		"aim_mode": "fixed",
		"direction": proj_dir,
		"shape_scene": data.ability_scene,
		"damage": data.base_damage,
		"attack_type": data.attack_type,
		"hit_limit": 0,
		"team_filter": "enemy",
		"detect_walls": true,
		"custom_hitbox": true,
		"rotation_speed": 100,
		"bounce_on_wall": true,
		"lifetime": data.projectile_lifetime if data.projectile_lifetime > 0 else 2.0,
		"speed": data.projectile_speed if data.projectile_speed > 0 else 600.0,
		"offset": data.range_,
		"impact_lifetime": 0.3,
		"on_hit": func(target_node: Node) -> void:
			if is_instance_valid(target_node):
				var cmbt = GameServiceLocator.combat_mediator
				if cmbt:
					cmbt.apply_damage(player_node, target_node, data.base_damage, data.attack_type)
				if target_node.is_in_group("killer") and data.stun_duration > 0.0:
					var combat_stun = GameServiceLocator.combat_mediator
					if combat_stun:
						combat_stun.apply_stun(target_node, data.stun_duration, 0.0, player_node)
	})

	AbilityBase.register_active(caster_id, entry_slot, self)
	_remember_alive(caster_id, entry_slot)

	var should_close_aim: bool = AbilityRouter.register_fase2_shot(caster_id, entry_slot)
	if should_close_aim:
		# Cierra el AIM; on_fase2_end aplica el cooldown de 20 s.
		AbilityRouter.end_fase2_after_fire(caster_id, entry_slot, true)
	else:
		# Sigue apuntando para el segundo disparo de Rage.
		if cd and cd.has_method("release_lock"):
			cd.release_lock(caster_id, entry_slot)

	# Al terminar la animación de lanzamiento, volver a la pose de AIM si sigue.
	_anim_token += 1
	var anim_token: int = _anim_token
	player_node.get_tree().create_timer(anim_dur).timeout.connect(
		func(): _end_fire_anim(anim_token)
	)

	print("[DevilKnifeAim] Disparo | peer: ", caster_id, " | rage: ", is_rage,
		" | coste: ", fire_cost, " | cierra AIM: ", should_close_aim)


func _end_fire_anim(anim_token: int) -> void:
	if anim_token != _anim_token:
		return
	# Si ya hay una instancia más nueva gestionando el siguiente disparo de
	# Rage, no pisar su animación.
	if not _cooldown_applied:
		var active = AbilityBase.find_active_for_peer(_caster_id, _slot_index)
		if active != self:
			return
	if not is_instance_valid(_player_node):
		return
	_player_node.rpc("_sync_fase2_firing", false)
	if AbilityRouter.is_fase2_active(_caster_id, _slot_index):
		if _data and _data.prepare_animation != "":
			_player_node.play_prepare_animation(
				_data.prepare_animation, _slot_index, _player_node.facing_right)
	else:
		_player_node.rpc("_sync_cancel_ability")


## Hook de AbilityFase2: al cerrar/cancelar el AIM después de disparar,
## aplica el cooldown de 20 s.
func on_fase2_end(_reason: String, shots_fired: int) -> void:
	if shots_fired <= 0:
		return
	_finish()


func _finish() -> void:
	if _cooldown_applied:
		return
	_cooldown_applied = true
	_keep_alive.erase(self)

	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
		_cd_svc.start(_caster_id, _slot_index, COOLDOWN)

	print("[DevilKnifeAim] AIM cerrado | peer: ", _caster_id, " | cooldown: ", COOLDOWN)


func _remember_alive(caster_id: int, slot_index: int) -> void:
	# La instancia debe sobrevivir entre los dos disparos de Rage y hasta que
	# AbilityFase2 llame on_fase2_end (el registro de AbilityBase es WeakRef).
	for i in range(_keep_alive.size() - 1, -1, -1):
		var inst = _keep_alive[i]
		if not is_instance_valid(inst) \
				or (inst._caster_id == caster_id and inst._slot_index == slot_index):
			_keep_alive.remove_at(i)
	_keep_alive.append(self)


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
