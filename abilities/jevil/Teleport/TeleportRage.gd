extends AbilityBase

# TeleportRage — Evolución de Teleport para modo Rage de Jevil.
# 8 teleports aleatorios a survivors enemigos, anillo 200-400px, sin paredes,
# 1 pike más rápido por teleport disparado por Jevil REAL desde new_pos
# (fantasma solo visual width->0), pauses RageFX + rage_blink, cancelable.

const MAX_TELEPORTS: int = 8
const TIME_BETWEEN_TELEPORTS: float = 0.25
const GHOST_SHOOT_DELAY: float = 0.5
const GHOST_LIFE_AFTER_SHOOT: float = 0.5
const TELEPORT_INVIS_DELAY: float = 0.1
const TELEPORT_DELAY: float = 0.2
const PIKE_IMPACT_LIFETIME: float = 0.3
const ROOT_DURATION: float = 6.5
const RING_MIN: float = 200.0
const RING_MAX: float = 400.0
const WALL_MARGIN: float = 35.0
const PIKE_SPEED_MULT: float = 1.6

static var _keep_alive: Array = []

var _active: bool = false
var _teleports_done: int = 0
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _current_target: Node = null
var _hs = null
var _cd_svc = null
var _combat = null

# Pausa RageFX/blink
var _had_rage_blink: bool = false
var _had_rage_fx: bool = false

# Ghost scene
const GHOST_SCENE: PackedScene = preload("res://abilities/jevil/Teleport/JevilGhost.tscn")


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	_player_node = player_node
	_caster_id = player_node.get_multiplayer_authority()
	_data = data
	_slot_index = slot_index
	_active = true
	_teleports_done = 0
	_had_rage_blink = false
	_had_rage_fx = false

	var tp_svc = GameServiceLocator.tp
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(_caster_id, data.tp_cost):
			return

	_cd_svc = GameServiceLocator.cooldown
	_hs = GameServiceLocator.hitbox
	_combat = GameServiceLocator.combat_mediator

	if _combat:
		_combat.apply_root(_player_node, ROOT_DURATION)
		if not _combat.stun_applied.is_connected(_on_jevil_stunned):
			_combat.stun_applied.connect(_on_jevil_stunned)
		if not _combat.damage_dealt.is_connected(_on_jevil_damaged):
			_combat.damage_dealt.connect(_on_jevil_damaged)

	# Pausar Synchronizer
	var sync = _player_node.get_node_or_null("Synchronizer")
	if sync:
		sync.set_process(false)
		sync.set_physics_process(false)

	# Pausar Rage visuales (blink + FX)
	if is_instance_valid(_player_node):
		if _player_node.active_effects.has("rage_blink"):
			_had_rage_blink = true
			_player_node.rpc("_sync_effect", "rage_blink", false)
		if _player_node.get_node_or_null("RageFX") != null:
			_had_rage_fx = true
			_player_node.rpc("_rpc_rage_vfx_hide")

	print("[TeleportRage] Activado | caster: ", _caster_id, " | slot: ", _slot_index)
	_keep_alive.append(self)
	_run()


func _run() -> void:
	while _active and _teleports_done < MAX_TELEPORTS:
		if not _find_and_prepare():
			break
		if not await _do_teleport():
			break
		if not await _do_attack():
			break
		_teleports_done += 1
		print("[TeleportRage] Ataque completado ", _teleports_done, "/", MAX_TELEPORTS)
		if _teleports_done < MAX_TELEPORTS:
			if not await _wait(TIME_BETWEEN_TELEPORTS):
				return
	if is_instance_valid(_player_node):
		await _player_node.get_tree().create_timer(1.0).timeout
	_finish()


func _find_and_prepare() -> bool:
	if not _active or not is_instance_valid(_player_node):
		_finish()
		return false
	_current_target = _find_random_target()
	if not _current_target:
		print("[TeleportRage] No hay target vivo, terminando.")
		_finish()
		return false
	print("[TeleportRage] Teleport ", _teleports_done + 1, "/", MAX_TELEPORTS, " -> ", _current_target.name)
	return true


func _do_teleport() -> bool:
	var old_pos: Vector2 = _player_node.global_position if is_instance_valid(_player_node) else Vector2.ZERO
	_set_visible(false)

	if not await _wait(TELEPORT_INVIS_DELAY):
		_set_visible(true)
		return false

	if not _active or not is_instance_valid(_player_node) or not is_instance_valid(_current_target):
		print("[TeleportRage] Cancelado en _do_teleport (nodo inválido)")
		_set_visible(true)
		return false

	var target_pos: Vector2 = _current_target.global_position
	var angle: float = randf() * TAU
	var radius: float = randf_range(RING_MIN, RING_MAX)
	var desired_pos: Vector2 = target_pos + Vector2(cos(angle), sin(angle)) * radius

	var dir_to_target: Vector2 = (target_pos - desired_pos).normalized()
	if dir_to_target == Vector2.ZERO:
		dir_to_target = Vector2.RIGHT

	var safe_pos: Vector2 = _find_safe_position_ring(desired_pos, target_pos, dir_to_target, angle, radius)
	_player_node.global_position = safe_pos
	_player_node.facing_right = dir_to_target.x >= 0.0
	_player_node.rpc("_sync_server_position", safe_pos)

	print("[TeleportRage] Teletransportado a ", safe_pos, " (deseado: ", desired_pos, ")")

	_set_visible(true)
	if _data and _data.prepare_animation != "":
		_player_node.play_prepare_animation(_data.prepare_animation, _slot_index, _player_node.facing_right)

	# Fantasma solo visual en old_pos (no dispara)
	_spawn_ghost_visual(old_pos, dir_to_target)
	# Jevil REAL dispara 1 pike desde new_pos hacia el target actual (fixed, sin perseguir)
	_shoot_from_new_pos(safe_pos, _current_target)

	return true


func _find_safe_position_ring(desired: Vector2, target_pos: Vector2, dir_to_target: Vector2, base_angle: float, base_radius: float) -> Vector2:
	if not is_instance_valid(_player_node):
		return desired
	var space_state = _player_node.get_world_2d().direct_space_state
	# Helper para raycast target -> punto
	var do_ray := func(p: Vector2) -> bool:
		var query = PhysicsRayQueryParameters2D.create(target_pos, p)
		query.collision_mask = 1
		query.exclude = [_player_node, _current_target]
		var result = space_state.intersect_ray(query)
		return result.is_empty()

	if do_ray.call(desired):
		return desired

	# Probar offsets alrededor del anillo
	var offsets_deg: Array = [22.5, -22.5, 45.0, -45.0, 67.5, -67.5, 90.0, -90.0, 135.0, -135.0, 180.0]
	for off in offsets_deg:
		var a2: float = base_angle + deg_to_rad(off)
		var p2: Vector2 = target_pos + Vector2(cos(a2), sin(a2)) * base_radius
		if do_ray.call(p2):
			return p2

	# Fallback: intentar punto más cercano al target dentro del anillo mínimo
	var fallback: Vector2 = target_pos + dir_to_target * RING_MIN
	if do_ray.call(fallback):
		return fallback

	# Último recurso: ray con margen
	var query2 = PhysicsRayQueryParameters2D.create(target_pos, desired)
	query2.collision_mask = 1
	query2.exclude = [_player_node, _current_target]
	var result2 = space_state.intersect_ray(query2)
	if result2.is_empty():
		return desired
	var hit_pos: Vector2 = result2.position
	var dist_to_target: float = target_pos.distance_to(hit_pos)
	if dist_to_target < WALL_MARGIN * 2:
		return desired
	return hit_pos + dir_to_target * WALL_MARGIN


func _spawn_ghost_visual(old_pos: Vector2, dir: Vector2) -> void:
	if not is_instance_valid(_player_node):
		return
	_player_node.rpc("_rpc_jevil_ghost", old_pos, dir)


func _shoot_from_new_pos(new_pos: Vector2, target_node: Node) -> void:
	if not _hs or not is_instance_valid(_player_node) or not is_instance_valid(target_node):
		return
	if not _data:
		return
	if _player_node.multiplayer.is_server():
		AudioManager.play_sfx_networked.rpc(SfxId.JEVIL_OH, new_pos.x, new_pos.y)

	var dmg: int = _data.base_damage if _data else 10
	var pike_speed: float = _data.projectile_speed * PIKE_SPEED_MULT if _data.projectile_speed > 0 else 550.0 * PIKE_SPEED_MULT
	var pike_lifetime: float = _data.projectile_lifetime if _data.projectile_lifetime > 0 else 2.0
	var pike_max_range: float = _data.projectile_max_range if _data else 0.0

	var pike_dir: Vector2 = (target_node.global_position - new_pos).normalized()
	if pike_dir == Vector2.ZERO:
		pike_dir = Vector2.RIGHT

	var hs = _hs
	var combat = _combat
	var pn: Node = _player_node
	var d: AbilityData = _data

	hs.create({
		"attacker_id": _caster_id,
		"attacker_node": pn,
		"type": "projectile",
		"aim_mode": "fixed",
		"direction": pike_dir,
		"shape_scene": d.ability_scene,
		"damage": dmg,
		"attack_type": d.attack_type if d else "normal",
		"hit_limit": 1,
		"team_filter": "enemy",
		"lifetime": pike_lifetime,
		"speed": pike_speed,
		"hitbox_max_range": pike_max_range,
		"impact_lifetime": PIKE_IMPACT_LIFETIME,
		"detect_walls": true,
		"offset": 0.0,
		"position": new_pos,
		"on_hit": func(hit_target: Node) -> void:
			if is_instance_valid(hit_target) and is_instance_valid(pn) and combat:
				combat.apply_damage(pn, hit_target, dmg, d.attack_type if d else "normal")
	})


func _do_attack() -> bool:
	if not await _wait(TELEPORT_DELAY):
		return false
	if not _active or not is_instance_valid(_player_node) or not is_instance_valid(_current_target):
		print("[TeleportRage] Cancelado en _do_attack (nodo inválido)")
		return false
	# El pike ya está programado desde el ghost; aquí solo reproducir anim si corresponde
	if _data and _data.action_animation != "" and is_instance_valid(_player_node):
		_player_node.play_ability_animation(_data.action_animation, _slot_index, _player_node.facing_right)
	return true


func _wait(delay: float) -> bool:
	var tree = _player_node.get_tree() if is_instance_valid(_player_node) else null
	if not tree:
		return false
	await tree.create_timer(delay).timeout
	return _active


func _find_random_target():
	if not is_instance_valid(_player_node):
		return null
	var tree = _player_node.get_tree()
	if not tree:
		return null
	var survivors = tree.get_nodes_in_group("survivor")
	var alive := []
	for s in survivors:
		if is_instance_valid(s):
			var hp_svc = GameServiceLocator.health
			if hp_svc and hp_svc.is_alive(s.get_multiplayer_authority()):
				alive.append(s)
	if alive.is_empty():
		return null
	return alive[randi() % alive.size()]


func _on_jevil_stunned(target_id: int, _duration: float) -> void:
	if target_id != _caster_id or not _active:
		return
	print("[TeleportRage] Cancelado por stun")
	_finish()


func _on_jevil_damaged(_attacker_id: int, target_id: int, _final_damage: int, _attack_type: String) -> void:
	if target_id != _caster_id or not _active:
		return
	print("[TeleportRage] Cancelado por daño")
	_finish()


func _set_visible(v: bool) -> void:
	if is_instance_valid(_player_node):
		_player_node.visible = v


func _finish() -> void:
	if not _active:
		return
	_active = false

	print("[TeleportRage] Finalizando | slot: ", _slot_index)

	_set_visible(true)

	if _combat and is_instance_valid(_player_node):
		_combat.remove_root(_player_node)

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_server_position", _player_node.global_position)
		var sync = _player_node.get_node_or_null("Synchronizer")
		if sync:
			sync.set_process(true)
			sync.set_physics_process(true)

	# Restaurar Rage visuales si siguen en Rage
	if is_instance_valid(_player_node):
		var abs_svc = GameServiceLocator.ability_state
		var still_rage: bool = abs_svc != null and abs_svc.is_mode_active(_caster_id, 4)
		if still_rage:
			if _had_rage_blink:
				_player_node.rpc("_sync_effect", "rage_blink", true)
			if _had_rage_fx:
				_player_node.rpc("_rpc_rage_vfx_show")
		_had_rage_blink = false
		_had_rage_fx = false

	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
		_cd_svc.start(_caster_id, _slot_index, _data.cooldown if _data else 25.0)

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_cancel_ability")

	if _combat:
		if _combat.stun_applied.is_connected(_on_jevil_stunned):
			_combat.stun_applied.disconnect(_on_jevil_stunned)
		if _combat.damage_dealt.is_connected(_on_jevil_damaged):
			_combat.damage_dealt.disconnect(_on_jevil_damaged)

	_keep_alive.erase(self)
