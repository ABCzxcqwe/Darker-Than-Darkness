extends AbilityBase

## Habilidad Carrusel (cierra el ciclo): tres aros elípticos IDÉNTICOS giran
## sincronizados, repartiendo el área de combate en tres bandas verticales
## iguales (fila superior, central e inferior), como las filas del carrusel de
## Deltarune. Los caballos del frente (elipse inferior) están iluminados y
## golpean; los del fondo están oscurecidos y son inofensivos. Sin cargas ni
## contenedores: los caballos aparecen directamente y se mueven con el patrón
## del aro. Como no posee evolved_version, al terminar el cast el slot se
## resetea a la fase base.

const ARENA_RADIUS: float = 600.0
const ARENA_SCENE := preload("res://Hitboxes/Jevil/CombatArena/scenes/CombatArena.tscn")
const CAROUSEL_CARD_SCENE := preload("res://Hitboxes/Jevil/CarouselRain/scenes/CarouselHitbox.tscn")
const SYMBOL_BOX_SCENE := preload("res://Hitboxes/Jevil/shared/scenes/AttackSymbolBox.tscn")

# Tres aros iguales, uno por banda vertical del área. Todos giran con la MISMA
# velocidad y fase (sincronizados) y montan HORSES_PER_RING caballos.
const RING_COUNT: int = 3
const HORSES_PER_RING: int = 7
# Los aros son idénticos: mismo radio X y mismo aplanado. El radio rebasa el
# borde del área (radio 600) unos 100 px para que el carrusel "salga" del cuadro.
const RING_RADIUS_X: float = 700.0
const RING_TILT: float = 0.375
# Los centros se reparten el alto del área (radio 600 → diámetro 1200) en 3
# bandas iguales: offsets en Y = -400, 0, +400.
const RING_BAND_SPAN: float = ARENA_RADIUS * 2.0 / 3.0
# Eleva los tres aros a la vez para que el carrusel quede arriba y deje un
# espacio seguro abajo del área.
const RING_RAISE: float = 200.0
# Velocidad angular común (rad/s): todos sincronizados.
const RING_ORBIT_SPEED: float = 0.7
# Bamboleo del aro (ola que viaja por el aro, hula-hula) — común a todos.
const RING_WOBBLE_SPEED: float = 2.0
const RING_WOBBLE_AMP: float = 150.0
# Giro del caballo sobre su propio eje (rad/s).
const HORSE_SPIN: float = 0
# Tiempo (s) antes de que la hitbox del caballo se active (telegraph visual).
const HITBOX_DELAY: float = 1.0
# Duración fija y configurable de toda la fase (root, silencio, protección y el
# timer de fin). Los aros giran durante toda la fase sin timers escalonados.
const DURATION: float = 9.0
# Los caballos viven medio segundo menos que el área de combate: terminan de
# desvanecerse justo antes de que el área desaparezca.
const HORSE_LIFETIME: float = DURATION - 0.5

var _active: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _arena: Node = null


func total_duration() -> float:
	return DURATION


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
func _run_phase(center: Vector2) -> void:
	if not is_instance_valid(_player_node):
		return

	_spawn_symbol_boxes(center)

	# Los 3 aros (idénticos y sincronizados) aparecen a la vez, uno por banda
	# vertical: cada caballo arranca sobre su elipse en su ángulo y rota al
	# mismo ritmo que los demás (misma velocidad y fase).
	for ring in range(RING_COUNT):
		var offset_y: float = lerpf(-RING_BAND_SPAN, RING_BAND_SPAN, float(ring) / float(RING_COUNT - 1)) - RING_RAISE
		var ring_center := center + Vector2(0.0, offset_y)
		for i in range(HORSES_PER_RING):
			var angle: float = TAU * float(i) / float(HORSES_PER_RING)
			_spawn_ring_horse(ring_center, RING_RADIUS_X, RING_ORBIT_SPEED, angle)


func _spawn_ring_horse(ring_center: Vector2, radius_x: float, orbit_speed: float, angle: float) -> void:
	if not is_instance_valid(_player_node):
		return

	var dmg: int = _data.base_damage if _data else 20
	var atk_type: String = _data.attack_type if _data else "normal"
	var pn := _player_node
	var cid := _caster_id
	var cmbt = GameServiceLocator.combat_mediator
	var hs = GameServiceLocator.hitbox
	if not hs:
		return

	var radius_y: float = radius_x * RING_TILT
	var spawn_pos := ring_center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)

	var hb = hs.create({
		"attacker_id": cid,
		"attacker_node": pn,
		"type": "projectile",
		"aim_mode": "fixed",
		"direction": Vector2.RIGHT,
		"shape_scene": CAROUSEL_CARD_SCENE,
		"damage": dmg,
		"attack_type": atk_type,
		"hit_limit": 0,
		"team_filter": "enemy",
		"lifetime": HORSE_LIFETIME,
		"speed": 0.0,
		"offset": 0.0,
		"impact_lifetime": 0.3,
		"custom_hitbox": true,
		"position": spawn_pos,
		"on_hit": func(target_node: Node) -> void:
			if is_instance_valid(target_node) and cmbt:
				cmbt.apply_damage(pn, target_node, dmg, atk_type)
	})
	if hb:
		hb.mode = "carousel_ring"
		hb.orbit_center = ring_center
		hb.orbit_angle = angle
		hb.orbit_speed = orbit_speed
		hb.ring_radius_x = radius_x
		hb.ring_radius_y = radius_y
		hb.wobble_speed = RING_WOBBLE_SPEED
		hb.wobble_amp = RING_WOBBLE_AMP
		hb.wobble_phase = 0.0
		hb.spin_speed = HORSE_SPIN
		hb.hitbox_delay = HITBOX_DELAY
		hb.entry_excess = 1.4
		hb.exit_fade_time = 0.4


func _spawn_symbol_boxes(center: Vector2) -> void:
	for i in range(4):
		var angle: float = TAU * float(i) / 4.0
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * (ARENA_RADIUS + 60.0)
		var box = _spawn_in_projectiles(SYMBOL_BOX_SCENE, pos)
		if box and box.has_method("setup"):
			box.setup("carousel", Color(0.95, 0.8, 0.3), angle)


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


func _spawn_in_projectiles(scene: PackedScene, pos: Vector2) -> Node:
	if not is_instance_valid(_player_node) or not _player_node.multiplayer.is_server():
		return null
	var container = _projectiles_container()
	if not container:
		return null
	var proj = scene.instantiate()
	proj.global_position = pos
	proj.set_multiplayer_authority(1)
	container.add_child(proj, true)
	return proj


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
## (sin evolved_version -> fase terminal, el ciclo se resetea a la base).
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
