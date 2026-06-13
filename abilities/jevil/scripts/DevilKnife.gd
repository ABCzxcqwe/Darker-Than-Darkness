extends AbilityBase

const AIM_TIMEOUT: float = 8.0

var _active: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	print("[DevilKnife] activate() | peer: ", player_node.get_multiplayer_authority() if is_instance_valid(player_node) else -1, " | slot: ", slot_index)
	if not is_instance_valid(player_node):
		print("[DevilKnife] activate() → player_node inválido, saliendo")
		return

	_player_node = player_node
	_caster_id = player_node.get_multiplayer_authority()
	_data = data
	_slot_index = slot_index

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if abs_svc and abs_svc.is_mode_active(_caster_id, _slot_index):
		print("[DevilKnife] activate() → modo activo detectado, lanzando")
		_launch(direction)
		return

	print("[DevilKnife] activate() → entrando en modo apuntado")
	_enter_aim()


func _enter_aim() -> void:
	print("[DevilKnife] _enter_aim() | peer: ", _caster_id, " | slot: ", _slot_index)
	if not is_instance_valid(_player_node):
		print("[DevilKnife] _enter_aim() → player_node inválido")
		return

	_active = true

	var combat = GameServiceLocator.get_service("CombatMediator")
	if combat:
		combat.apply_root(_player_node, AIM_TIMEOUT + 1.0)
		print("[DevilKnife] _enter_aim() → combat root aplicado")

	_player_node.rpc("_sync_effect", "free_look", true)
	_player_node.rpc("_sync_aiming_mode", _slot_index, true)
	print("[DevilKnife] _enter_aim() → RPCs de sync enviados (free_look, aiming_mode)")

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if abs_svc:
		abs_svc.activate_mode(_caster_id, _slot_index, {})
		print("[DevilKnife] _enter_aim() → modo activado en AbilityStateService")

	var cd = GameServiceLocator.get_service("CooldownService")
	if cd and cd.has_method("release_lock"):
		cd.release_lock(_caster_id, _slot_index)
		print("[DevilKnife] _enter_aim() → lock liberado")

	print("[DevilKnife] Modo apuntado activado | peer: ", _caster_id, " | slot: ", _slot_index)
	print("[DevilKnife] _enter_aim() → programando timeout de ", AIM_TIMEOUT, "s...")

	_player_node.get_tree().create_timer(AIM_TIMEOUT).timeout.connect(
		func():
			print("[DevilKnife] _enter_aim() → timeout despertó | _active: ", _active)
			if _active:
				print("[DevilKnife] Tiempo de apuntado agotado | peer: ", _caster_id)
				_cancel_aim()
	)


func _launch(direction: Vector2) -> void:
	print("[DevilKnife] _launch() | peer: ", _caster_id, " | dir: ", direction)
	_active = true
	if not is_instance_valid(_player_node):
		print("[DevilKnife] _launch() → player_node inválido, cancelando")
		_cancel_aim()
		return

	var combat = GameServiceLocator.get_service("CombatMediator")
	var tp_svc = GameServiceLocator.get_service("TPService")
	var hs = GameServiceLocator.get_service("HitboxService")

	if _data and _data.tp_cost > 0.0 and tp_svc:
		print("[DevilKnife] _launch() → verificando TP cost: ", _data.tp_cost)
		if not tp_svc.consume_tp(_caster_id, _data.tp_cost):
			print("[DevilKnife] _launch() → TP insuficiente, cancelando")
			_cancel_aim()
			return
		print("[DevilKnife] _launch() → TP consumido")

	if combat:
		combat.apply_root(_player_node, 2.0)
		print("[DevilKnife] _launch() → combat root aplicado (2s)")

	if _data and _data.action_animation != "":
		print("[DevilKnife] _launch() → reproduciendo animación: ", _data.action_animation)
		_player_node.play_ability_animation(_data.action_animation, _slot_index, _player_node.facing_right)

	var sprite: AnimatedSprite2D = _player_node.get_node_or_null("AnimatedSprite2D")
	var anim_dur: float = 0.3
	if sprite and sprite.sprite_frames and _data and _data.action_animation != "" and sprite.sprite_frames.has_animation(_data.action_animation):
		anim_dur = sprite.sprite_frames.get_frame_count(_data.action_animation) / sprite.sprite_frames.get_animation_speed(_data.action_animation)

	print("[DevilKnife] _launch() → programando timer de ", anim_dur, "s...")

	var pn := _player_node
	var cid := _caster_id
	var sid := _slot_index
	var d := _data
	var dir := direction

	_player_node.get_tree().create_timer(anim_dur).timeout.connect(
		func():
			_on_anim_timer(pn, cid, sid, d, dir)
	)


func _on_anim_timer(pn: Node, cid: int, sid: int, d: AbilityData, dir: Vector2) -> void:
	print("[DevilKnife] _on_anim_timer() | peer: ", cid)
	if not is_instance_valid(pn):
		print("[DevilKnife] _on_anim_timer() → player_node inválido")
		_cancel_aim()
		return

	var cmbt = GameServiceLocator.get_service("CombatMediator")
	var hss = GameServiceLocator.get_service("HitboxService")

	var proj_dir: Vector2 = dir.normalized()
	if proj_dir == Vector2.ZERO:
		proj_dir = Vector2.RIGHT if pn.facing_right else Vector2.LEFT
		print("[DevilKnife] _on_anim_timer() → dirección zero, usando facing: ", proj_dir)

	print("[DevilKnife] _on_anim_timer() → creando proyectil | dir: ", proj_dir, " | hs: ", hss)

	if hss:
		print("[DevilKnife] _on_anim_timer() → llamando hs.create()...")
		hss.create({
			"attacker_id": cid,
			"attacker_node": pn,
			"type": "projectile",
			"aim_mode": "fixed",
			"direction": proj_dir,
			"shape_scene": d.ability_scene if d else null,
			"damage": d.base_damage if d else 10,
			"attack_type": d.attack_type if d else "normal",
			"hit_limit": 1,
			"team_filter": "enemy",
			"lifetime": d.projectile_lifetime if d and d.projectile_lifetime > 0 else 2.0,
			"speed": d.projectile_speed if d and d.projectile_speed > 0 else 600.0,
			"offset": d.range_ if d else 80.0,
			"impact_lifetime": 0.3,
			"on_hit": func(target_node: Node) -> void:
				print("[DevilKnife] on_hit | target: ", target_node)
				if is_instance_valid(target_node) and cmbt:
					cmbt.apply_damage(pn, target_node, d.base_damage if d else 10, d.attack_type if d else "normal")
					if target_node.is_in_group("killer"):
						var status = GameServiceLocator.get_service("StatusEffectService")
						var stun_dur = (d.stun_duration + d.evo_status_duration_bonus) if d else 0.0
						if status and stun_dur > 0.0:
							status.apply(target_node, "stun", { "duration": stun_dur })
		})
		print("[DevilKnife] _on_anim_timer() → hs.create() ejecutado")
	else:
		print("[DevilKnife] _on_anim_timer() → hs es null, NO se creó el proyectil")

	print("[DevilKnife] Cuchillo lanzado | peer: ", cid, " | dir: ", proj_dir)
	_finish()


func _cancel_aim() -> void:
	print("[DevilKnife] _cancel_aim() | peer: ", _caster_id, " | _active: ", _active)
	if not _active:
		print("[DevilKnife] _cancel_aim() → ya inactivo, saliendo")
		return
	_active = false
	print("[DevilKnife] _cancel_aim() → _active = false")

	if is_instance_valid(_player_node):
		print("[DevilKnife] _cancel_aim() → limpiando estado en player")
		_player_node.rpc("_sync_aiming_mode", _slot_index, false)
		_player_node.rpc("_sync_effect", "free_look", false)

		var combat = GameServiceLocator.get_service("CombatMediator")
		if combat:
			combat.remove_root(_player_node)
			print("[DevilKnife] _cancel_aim() → combat root removido")

		var abs_svc = GameServiceLocator.get_service("AbilityStateService")
		if abs_svc and abs_svc.is_mode_active(_caster_id, _slot_index):
			abs_svc.deactivate_mode(_caster_id, _slot_index)
			print("[DevilKnife] _cancel_aim() → modo desactivado")

		var cd = GameServiceLocator.get_service("CooldownService")
		if cd and cd.has_method("release_lock"):
			cd.release_lock(_caster_id, _slot_index)
			print("[DevilKnife] _cancel_aim() → lock liberado")

		_player_node.rpc("_sync_cancel_ability")
		print("[DevilKnife] _cancel_aim() → sync_cancel_ability enviado")
	else:
		print("[DevilKnife] _cancel_aim() → player_node inválido, no se limpia")


func _finish() -> void:
	print("[DevilKnife] _finish() | peer: ", _caster_id, " | _active: ", _active)
	if not _active:
		print("[DevilKnife] _finish() → ya inactivo, saliendo")
		return
	_active = false
	print("[DevilKnife] _finish() → _active = false")

	if is_instance_valid(_player_node):
		print("[DevilKnife] _finish() → limpiando estado en player")
		_player_node.rpc("_sync_aiming_mode", _slot_index, false)
		_player_node.rpc("_sync_effect", "free_look", false)

		var combat = GameServiceLocator.get_service("CombatMediator")
		if combat:
			combat.remove_root(_player_node)
			print("[DevilKnife] _finish() → combat root removido")

		var abs_svc = GameServiceLocator.get_service("AbilityStateService")
		if abs_svc and abs_svc.is_mode_active(_caster_id, _slot_index):
			abs_svc.deactivate_mode(_caster_id, _slot_index)
			print("[DevilKnife] _finish() → modo desactivado")

		var cd = GameServiceLocator.get_service("CooldownService")
		if cd:
			if cd.has_method("release_lock"):
				cd.release_lock(_caster_id, _slot_index)
				print("[DevilKnife] _finish() → lock liberado")
			cd.start(_caster_id, _slot_index, _data.cooldown if _data else 10.0)
			print("[DevilKnife] _finish() → cooldown iniciado: ", _data.cooldown if _data else 10.0)

		_player_node.rpc("_sync_cancel_ability")
		print("[DevilKnife] _finish() → sync_cancel_ability enviado")
	else:
		print("[DevilKnife] _finish() → player_node inválido, no se limpia")
