extends "res://abilities/king/KingAbilityBase.gd"
class_name TopoAbility

const WAVE_COUNT: int = 5
const WAVE_INTERVAL: float = 1.5
const WARNING_TIME: float = 1.0
const SPEAR_HOLD: float = 1.5
const SPEARS_PER_SURVIVOR: int = 12
const WARNING_RADIUS: float = 110.0
const SPEAR_MIN_MULT: float = 2.0
const SPEAR_MAX_MULT: float = 5.0
# Duración de la animación king_topo: 8 frames / 5 fps = 1.6s (loop false)
const CAST_ANIM_DURATION: float = 1.6

const SIGNAL_TEX := preload("res://Characters/King/assets/Sprites/señal.png")
const WARNING_SCENE := preload("res://Hitboxes/King/Topo/WarningCircle.tscn")
const SPEAR_SCENE := preload("res://Hitboxes/King/Topo/TopoSpear.tscn")

static var _keep_alive: Array = []

var _active: bool = false
var _total_duration: float = 0.0


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not _cache_common(player_node, data, slot_index):
		return
	_active = true
	if not _consume_tp_or_fail():
		return
	var facing_right: bool = _get_facing_right(direction)
	# Duración total de oleadas (independiente del cast)
	var grow_time: float = 0.5
	var wave_life: float = WARNING_TIME + grow_time + SPEAR_HOLD + 0.5
	_total_duration = float(WAVE_COUNT - 1) * WAVE_INTERVAL + wave_life + 0.5
	# Cast: anim 1 vez, invulnerable solo durante anim, luego vuelve a IDLE controlable
	var anim_dur: float = CAST_ANIM_DURATION
	# Si la anim tiene duración distinta en SpriteFrames, usarla
	if is_instance_valid(_player_node) and _player_node.animated_sprite and _player_node.animated_sprite.sprite_frames:
		var frames = _player_node.animated_sprite.sprite_frames
		if frames.has_animation(data.action_animation):
			var speed: float = frames.get_animation_speed(data.action_animation)
			var count: int = frames.get_frame_count(data.action_animation)
			if speed > 0.0 and count > 0:
				anim_dur = float(count) / speed
	_play_anim_no_hold(data, slot_index, facing_right)
	_apply_root(anim_dur)
	_grant_invincibility(anim_dur)
	print("[Topo] king_topo anim_dur=", anim_dur, " total_oleadas=", _total_duration, " anim=", data.action_animation)
	var status_svc = GameServiceLocator.status_effect
	if status_svc:
		if status_svc.has_method("grant_stun_immunity"):
			status_svc.grant_stun_immunity(_caster_id, anim_dur)
		for survivor in _get_alive_survivors():
			if is_instance_valid(survivor):
				status_svc.apply(survivor, "sprint_disabled", { "duration": _total_duration })
	# Liberar cast tras la animación: King vuelve a IDLE y se puede mover
	var tree_cast := player_node.get_tree()
	if tree_cast:
		tree_cast.create_timer(anim_dur).timeout.connect(_release_cast)
	_keep_alive.append(self)
	AbilityBase.register_active(_caster_id, _slot_index, self)
	if _cd_svc and _cd_svc.has_method("release_lock"):
		_cd_svc.release_lock(_caster_id, _slot_index)
	_cd_svc.start(_caster_id, _slot_index, data.cooldown)
	for w in range(WAVE_COUNT):
		var delay: float = float(w) * WAVE_INTERVAL
		var tree := player_node.get_tree()
		if tree:
			tree.create_timer(delay).timeout.connect(_spawn_wave.bind(w))
	var tree_fin := player_node.get_tree()
	if tree_fin:
		tree_fin.create_timer(_total_duration).timeout.connect(_finish)
	else:
		await Engine.get_main_loop().create_timer(_total_duration).timeout
		_finish()
	print("[Topo] Habilidad iniciada | peer: ", _caster_id, " | oleadas: ", WAVE_COUNT, " | duración oleadas: ", _total_duration, " | cast: ", anim_dur)


func _release_cast() -> void:
	# Solo libera el root/invuln del cast; las oleadas siguen con _active=true
	if not is_instance_valid(_player_node):
		return
	_remove_root()
	# Invencibilidad del cast expira sola por timestamp, pero aseguramos limpieza si queda residual
	# No limpiamos antes de tiempo: _grant_invincibility ya puso invincible_until = now + anim_dur
	# Aquí solo sincronizamos cancel de anim para volver a IDLE (por si loop false no disparó on_anim_finished en cliente)
	if _player_node.has_method("reset_ability_state"):
		# Server ya volverá a IDLE vía animation_finished, pero forzamos sync a clientes
		_player_node.rpc("_sync_cancel_ability")
	var status_svc = GameServiceLocator.status_effect
	if status_svc and status_svc.has_method("grant_stun_immunity"):
		# No extender inmunidad: limpiar si sigue activa más allá del cast
		# (grant_stun_immunity con 0 limpia)
		if _active:
			# Mantener solo si aún estamos en cast; ya expiró, limpiar
			status_svc.grant_stun_immunity(_caster_id, 0.0)
	print("[Topo] Cast liberado → King controlable | peer: ", _caster_id)


func _spawn_wave(wave_idx: int) -> void:
	if not _active or not is_instance_valid(_player_node) or not _player_node.get_tree():
		return
	var survivors := _get_alive_survivors()
	if survivors.is_empty():
		survivors = [_player_node]
	for survivor in survivors:
		if not is_instance_valid(survivor):
			continue
		for i in range(SPEARS_PER_SURVIVOR):
			var angle: float = randf() * TAU
			var dist: float = randf_range(220.0, 440.0) if randf() >= 0.3 else randf_range(100.0, 180.0)
			var pos: Vector2 = survivor.global_position + Vector2(dist, 0).rotated(angle)
			_spawn_warning(pos)


func _spawn_warning(pos: Vector2) -> void:
	if not _active or not is_instance_valid(_player_node) or not _player_node.get_tree() or not _player_node.multiplayer.is_server():
		return
	# Hotfix: WarningCircle es visual puro (Node2D sin attacker_id) — spawn manual como en a3599f9
	# para no pasar por HitboxService que espera props de hitbox y crashea en _spawn_projectile:152.
	# TopoSpear sí sigue por HitboxService (es custom_hitbox compatible).
	var world = _player_node.get_tree().root.find_child("World", true, false)
	if not world:
		return
	var container = world.get_node_or_null("Projectiles")
	if not container:
		container = world
	var warning = WARNING_SCENE.instantiate()
	warning.global_position = pos
	var circle_duration: float = WARNING_TIME + SPEAR_HOLD + 1.0
	if "radius" in warning:
		warning.radius = WARNING_RADIUS
	if "duration" in warning:
		warning.duration = circle_duration
	elif warning.has_method("set_duration"):
		warning.set_duration(circle_duration)
	container.add_child(warning, true)
	var tree2 := _player_node.get_tree()
	if tree2:
		tree2.create_timer(WARNING_TIME).timeout.connect(_spawn_spear.bind(pos))


func _spawn_spear(pos: Vector2) -> void:
	if not _active or not is_instance_valid(_player_node) or not _player_node.get_tree() or not _player_node.multiplayer.is_server():
		return
	var hs = GameServiceLocator.hitbox
	if not hs:
		return
	var spear = hs.create({
		"attacker_id": _caster_id,
		"attacker_node": _player_node,
		"type": "projectile",
		"aim_mode": "fixed",
		"direction": Vector2.DOWN,
		"shape_scene": SPEAR_SCENE,
		"damage": _data.base_damage if _data and _data.base_damage > 0 else 10,
		"attack_type": _data.attack_type if _data else "normal",
		"team_filter": "enemy",
		"hit_limit": 1,
		"lifetime": 4.0,
		"speed": 0.0,
		"custom_hitbox": true,
		"position": pos,
	})
	if not spear:
		return
	var mult: float = float([2, 3, 4, 5].pick_random())
	print("[Topo] spear mult=", mult, " pos=", pos)
	if spear.has_method("setup_topo"):
		spear.setup_topo(self, _player_node, mult)


func _get_alive_survivors() -> Array:
	var result: Array = []
	if not is_instance_valid(_player_node) or not _player_node.get_tree():
		return result
	for n in _player_node.get_tree().get_nodes_in_group("survivor"):
		if not is_instance_valid(n) or n.health_state != "alive":
			continue
		result.append(n)
	return result


func _finish() -> void:
	if not _active:
		return
	_active = false
	var status_svc = GameServiceLocator.status_effect
	if status_svc:
		for survivor in _get_alive_survivors():
			if is_instance_valid(survivor):
				status_svc.remove_effect(survivor, "sprint_disabled")
		if status_svc.has_method("grant_stun_immunity"):
			status_svc.grant_stun_immunity(_caster_id, 0.0)
	# Asegurar limpieza de root por si el cast timer falló
	_remove_root()
	# Asegurar que King esté en IDLE si aún estaba en ABILITY (fallback)
	if is_instance_valid(_player_node) and _player_node.state == 2: # AnimState.ABILITY
		_player_node.rpc("_sync_cancel_ability")
	AbilityBase.unregister_active(_caster_id, _slot_index)
	_keep_alive.erase(self)
	print("[Topo] Finalizada | peer: ", _caster_id)


func _fail_cleanup() -> void:
	_active = false
	AbilityBase.unregister_active(_caster_id, _slot_index)
	var status_svc = GameServiceLocator.status_effect
	if status_svc and status_svc.has_method("grant_stun_immunity"):
		status_svc.grant_stun_immunity(_caster_id, 0.0)
	_remove_root()
	if is_instance_valid(_player_node) and Time.get_ticks_msec() < _player_node.invincible_until:
		_player_node.invincible_until = 0
		_player_node.rpc("_sync_invincibility", 0)
	super._fail_cleanup()
	print("[Topo] Fallo activación | peer: ", _caster_id)
