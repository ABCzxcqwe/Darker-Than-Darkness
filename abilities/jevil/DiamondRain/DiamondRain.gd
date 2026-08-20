extends AbilityBase

## Fase base del ciclo: lluvia de diamantes que caen del cielo y atraviesan
## el área de combate hasta salir por debajo del recuadro.

const ARENA_RADIUS: float = 600.0
const ARENA_SCENE := preload("res://Hitboxes/Jevil/CombatArena/scenes/CombatArena.tscn")

const DIAMOND_COUNT: int = 60
const DIAMOND_SPEED: float = 600.0
const SPAWN_INTERVAL: float = 0.08
const DIAMOND_SPAWN_MARGIN: float = 80.0
const DIAMOND_HOVER: float = 1.0
const CENTER_SAFE_RADIUS: float = 200.0
const BELOW_BOX_OVERTRAVEL: float = 200.0

var _active: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _arena: Node = null


func total_duration() -> float:
	var max_fall: float = (ARENA_RADIUS + DIAMOND_SPAWN_MARGIN) + (ARENA_RADIUS + BELOW_BOX_OVERTRAVEL)
	var fall_time: float = max_fall / DIAMOND_SPEED
	return float(DIAMOND_COUNT - 1) * SPAWN_INTERVAL + DIAMOND_HOVER + fall_time + 0.5


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
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

	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, _slot_index, player_node.facing_right)

	var combat = GameServiceLocator.combat_mediator
	if combat:
		combat.apply_root(_player_node, total_duration())

	var status = GameServiceLocator.status_effect
	if status:
		status.grant_stun_immunity(_caster_id, total_duration())
		status.apply(_player_node, "invisibility", { "duration": total_duration() })
		status.apply(_player_node, "damage_reduction", { "duration": total_duration(), "magnitude": 0.9 })
		status.apply(_player_node, "silence", { "duration": total_duration() })

	var target_center = player_node.global_position

	_spawn_arena(target_center)
	_run_phase(target_center)

	var cd = GameServiceLocator.cooldown
	if cd:
		cd.release_lock(_caster_id, _slot_index)
		if _data and _data.cooldown > 0.0:
			cd.start(_caster_id, _slot_index, _data.cooldown)

	player_node.get_tree().create_timer(total_duration()).timeout.connect(
		func():
			_finish_ability()
	)

	print("[", get_script().resource_path.get_file(), "] Fase iniciada | peer: ", _caster_id, " | centro: ", target_center)


# ── Ataque ───────────────────────────────────────────────────────────────
func _run_phase(target_center: Vector2) -> void:
	if not is_instance_valid(_player_node):
		return

	var hs = GameServiceLocator.hitbox
	var cmbt = GameServiceLocator.combat_mediator
	var pn := _player_node
	var cid := _caster_id
	var d := _data

	for i in range(DIAMOND_COUNT):
		pn.get_tree().create_timer(i * SPAWN_INTERVAL).timeout.connect(
			func():
				_spawn_diamond(pn, cid, d, hs, cmbt, target_center)
		)


func _spawn_diamond(pn: Node, cid: int, d: AbilityData, hs: Node, cmbt: Node, target_center: Vector2) -> void:
	if not is_instance_valid(pn) or not hs:
		return

	var target_point = _random_point_in_arena(target_center)
	var spawn_pos = Vector2(target_point.x, target_center.y - ARENA_RADIUS - DIAMOND_SPAWN_MARGIN)
	var fall_distance: float = (target_center.y + ARENA_RADIUS + BELOW_BOX_OVERTRAVEL) - spawn_pos.y
	var fall_time: float = fall_distance / DIAMOND_SPEED

	var dmg: int = d.base_damage if d else 20
	var atk_type: String = d.attack_type if d else "normal"

	var config = {
		"attacker_id": cid,
		"attacker_node": pn,
		"type": "projectile",
		"aim_mode": "fixed",
		"direction": Vector2.DOWN,
		"shape_scene": d.ability_scene if d else null,
		"damage": dmg,
		"attack_type": atk_type,
		"hit_limit": 1,
		"team_filter": "enemy",
		"lifetime": DIAMOND_HOVER + fall_time + 0.3,
		"speed": 0.0,
		"offset": 0.0,
		"impact_lifetime": 0.3,
		"hitbox_max_range": fall_distance,
		"position": spawn_pos,
		"on_hit": func(target_node: Node) -> void:
			if is_instance_valid(target_node) and cmbt:
				cmbt.apply_damage(pn, target_node, dmg, atk_type)
	}

	var hitbox = hs.create(config)
	if hitbox:
		hitbox.rotation = 0.0
		pn.get_tree().create_timer(DIAMOND_HOVER).timeout.connect(
			func():
				if is_instance_valid(hitbox):
					hitbox.speed = DIAMOND_SPEED
		)


func _random_point_in_arena(center: Vector2) -> Vector2:
	var p = center + Vector2(randf_range(-ARENA_RADIUS, ARENA_RADIUS), randf_range(-ARENA_RADIUS, ARENA_RADIUS))
	if p.distance_to(center) < CENTER_SAFE_RADIUS:
		p = center + Vector2(randf_range(-ARENA_RADIUS, ARENA_RADIUS), randf_range(-ARENA_RADIUS, ARENA_RADIUS))
	return p


# ── Arena (elemento compartido) ─────────────────────────────────────────
func _spawn_arena(center: Vector2) -> void:
	if not is_instance_valid(_player_node) or not _player_node.multiplayer.is_server():
		return
	var container = _projectiles_container()
	if not container:
		return
	var arena = ARENA_SCENE.instantiate()
	arena.configure(center, ARENA_RADIUS)
	arena.set_multiplayer_authority(1)
	container.add_child(arena, true)
	_arena = arena


func _clear_arena() -> void:
	if is_instance_valid(_arena):
		if _arena.has_method("_rpc_disappear"):
			_arena.rpc("_rpc_disappear")
		else:
			_arena.queue_free()
	_arena = null


func _projectiles_container() -> Node:
	if not is_instance_valid(_player_node):
		return null
	var world = _player_node.get_tree().root.find_child("World", true, false)
	if not world:
		return null
	return world.get_node_or_null("Projectiles")


# ── Finalización ─────────────────────────────────────────────────────────
func _finish_ability() -> void:
	if not _active:
		return
	_active = false

	_clear_arena()

	var combat = GameServiceLocator.combat_mediator
	if combat and is_instance_valid(_player_node):
		combat.remove_root(_player_node)

	var status = GameServiceLocator.status_effect
	if status:
		status.grant_stun_immunity(_caster_id, 0.0)
		if _player_node.multiplayer.is_server() and is_instance_valid(_player_node):
			status.remove_effect(_player_node, "silence")
			status.remove_effect(_player_node, "invisibility")
			status.remove_effect(_player_node, "damage_reduction")

	_advance_stage()

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_cancel_ability")

	print("[", get_script().resource_path.get_file(), "] Fase finalizada | peer: ", _caster_id)


## Avanza o resetea la evolución del slot según la cadena del AbilityData
## (si no hay evolved_version, es la fase terminal y se resetea el ciclo).
func _advance_stage() -> void:
	if not is_instance_valid(_player_node) or not _player_node.multiplayer.is_server():
		return
	var evo = GameServiceLocator.evolution
	if not evo:
		return
	if _data and _data.evolved_version != null:
		evo.evolve_slot(_caster_id, _slot_index)
	else:
		evo.reset_slot(_caster_id, _slot_index)


func _fail_cleanup() -> void:
	_active = false
	_clear_arena()
	var cd = GameServiceLocator.cooldown
	if cd:
		cd.release_lock(_caster_id, _slot_index)
	print("[", get_script().resource_path.get_file(), "] Fallo en activación | peer: ", _caster_id)
