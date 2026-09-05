extends AbilityBase

## Habilidad Corazones: cargas con forma de corazón aparecen a los lados,
## FUERA del área de combate, repartidas en una ventana de tiempo fija con
## instantes aleatorios (sin solapamientos). Caen en vertical; un segundo antes
## de explotar se DETIENEN (SFX + anillo del radio de explosión) y al acabar
## explotan dañando en área. Al explotar sueltan 4 corazones que forman un
## cuadrado que gira alrededor del punto de explosión mientras su centro AVANZA
## EN LÍNEA RECTA hacia el survivor más cercano EN EL MOMENTO de la explosión
## (no lo persigue). El cuadrado es más grande y dura más para que el jugador
## pueda verlo venir y esquivarlo por el hueco central.

const ARENA_RADIUS: float = 600.0
const ARENA_SCENE := preload("res://Hitboxes/Jevil/CombatArena/scenes/CombatArena.tscn")
const HEART_CHARGE_SCENE := preload("res://Hitboxes/Jevil/HeartRain/scenes/HeartHitbox.tscn")
const MINI_HEART_SCENE := preload("res://Hitboxes/Jevil/HeartRain/scenes/MiniHeartHitbox.tscn")

# ══ TUNING (Heart Chaos) ═══════════════════════════════════════════════
# Número de cargas que caen.
const CHARGE_COUNT: int = 18
# Ventana (s) total en la que se reparten las apariciones: cada carga elige un
# instante aleatorio dentro de la ventana (puntos ordenados) → nunca coinciden
# y el ritmo promedio es ventana / (count-1).
const CHARGE_SPAWN_WINDOW: float = 9
# Ventana aleatoria (s) antes de que la carga explote tras aparecer.
const CHARGE_MIN_FUSE: float = 2.0
const CHARGE_MAX_FUSE: float = 4.0
# Cuánto antes de explotar la carga se DETIENE (deja de caer), suena el SFX de
# aviso y se muestra el anillo del radio de explosión (reemplaza al parpadeo).
const STOP_BEFORE_EXPLODE: float = 1.0
# Velocidad (px/s) de caída vertical de cada carga.
const FALL_SPEED: float = 350.0
# Radio (px) del daño en área al explotar y cuánto dura el hitbox de explosión.
const EXPLOSION_RADIUS: float = 140.0
const EXPLOSION_LIFETIME: float = 0.35
# Cuánto más arriba cae la carga (más allá del borde superior del área):
# a mayor valor, más tiempo es visible antes de entrar a la zona jugable.
const CHARGE_SPAWN_Y_EXTRA: float = 200.0
# Franja horizontal de aparición FUERA del área de combate (paredes en ±600):
# las cargas spawnean a los lados del recinto, nunca dentro del cuadro.
const CHARGE_SPAWN_X_MIN: float = 700.0
const CHARGE_SPAWN_X_MAX: float = 800.0
# Nº de corazones que forman el cuadrado al explotar.
const MINI_HEART_COUNT: int = 4
# Velocidad de giro de cada corazón sobre su propio eje.
const MINI_HEART_SPIN: float = 0.0
# Duración (s) del cuadrado de corazones.
const MINI_HEART_LIFETIME: float = 10
# Radio (px) del cuadrado de corazones (~hueco central para esquivar):
# a mayor valor, más grande el cuadrado y más separados sus corazones.
const HEART_SQUARE_RADIUS: float = 120.0
# Velocidad de rotación del cuadrado alrededor de su centro.
const HEART_SQUARE_SPIN: float = 2.5
# Velocidad (px/s) de avance en línea recta del centro del cuadrado hacia
# el survivor más cercano OBSERVADO EN EL MOMENTO de la explosión (no chase).
const HEART_SQUARE_TRANSLATE_SPEED: float = 500.0

# Duración fija y configurable de toda la fase (root, silencio, protección y
# el timer de fin). Única perilla del estado activo: cubre la ventana de
# spawn + fuse máx + vida del cuadrado con buffer, y termina unos segundos
# antes del peor caso (los corazones residuales siguen en vuelo y el killer
# recupera el control antes).
const PHASE_DURATION: float = 13.0

var _active: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _arena: Node = null


func total_duration() -> float:
	return PHASE_DURATION


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
		# Silencio: bloquea cualquier habilidad (incluido M1) durante la fase para
		# que el melee no pueda borrar el root con su on_end. (Server chequea
		# is_silenced ANTES del estado de animación, así vale aunque esté IDLE.)
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

	# Reparto los instantes de aparición como puntos aleatorios ordenados dentro
	# de la ventana fija: nunca coinciden en el tiempo y el ritmo es estable.
	var spawn_times: Array = []
	for i in range(CHARGE_COUNT):
		spawn_times.append(randf() * CHARGE_SPAWN_WINDOW)
	spawn_times.sort()

	for i in range(CHARGE_COUNT):
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var x: float = center.x + side * randf_range(CHARGE_SPAWN_X_MIN, CHARGE_SPAWN_X_MAX)
		var pos: Vector2 = Vector2(x, center.y - ARENA_RADIUS - CHARGE_SPAWN_Y_EXTRA)
		var fuse: float = randf_range(CHARGE_MIN_FUSE, CHARGE_MAX_FUSE)
		var delay: float = spawn_times[i]
		_player_node.get_tree().create_timer(delay).timeout.connect(
			func():
				_spawn_charge(pos, fuse, center)
		)


func _spawn_charge(pos: Vector2, fuse: float, _center: Vector2) -> void:
	if not is_instance_valid(_player_node):
		return

	var charge = _spawn_in_projectiles(HEART_CHARGE_SCENE, pos)
	if not charge:
		return

	var dmg: int = _data.base_damage if _data else 20
	var atk_type: String = _data.attack_type if _data else "normal"
	var pn := _player_node
	var cid := _caster_id
	var cmbt = GameServiceLocator.combat_mediator

	charge.attacker_id = cid
	charge.attacker_node = pn
	charge.damage = dmg
	charge.attack_type = atk_type
	charge.team_filter = "enemy"
	charge.fuse = fuse
	charge.blink_duration = 0.0
	charge.stop_before_explode = STOP_BEFORE_EXPLODE
	charge.falling = true
	charge.fall_speed = FALL_SPEED
	charge.explosion_radius = EXPLOSION_RADIUS
	charge.explosion_lifetime = EXPLOSION_LIFETIME
	charge.on_explode = func(_charge: Node) -> void:
		_on_charge_exploded(_charge.global_position, pn, cid, dmg, atk_type, cmbt)


func _on_charge_exploded(explosion_pos: Vector2, pn: Node, cid: int, dmg: int, atk_type: String, cmbt: Node) -> void:
	# La propia carga ya aplica el daño en área al explotar (explosion_radius).
	# Aquí solo se calcula la dirección fija del cuadrado de corazones.

	# Dirección de traslación fijada AL EXPLOTAR hacia el survivor más cercano.
	# Si no hay survivor o el target coincide con el centro, se usa una
	# dirección fija constante (RIGHT) para que el cuadrado NUNCA se quede
	# clavado orbitando en el mismo punto.
	var translate_dir: Vector2 = Vector2.RIGHT
	if is_instance_valid(_arena) and _arena.has_method("nearest_survivor"):
		var target: Node2D = _arena.nearest_survivor(explosion_pos)
		if target:
			var aim_dir: Vector2 = target.global_position - explosion_pos
			if aim_dir != Vector2.ZERO:
				translate_dir = aim_dir.normalized()

	_spawn_heart_square(explosion_pos, translate_dir, pn, cid, dmg, atk_type, cmbt)


func _spawn_heart_square(center_pos: Vector2, translate_dir: Vector2, pn: Node, cid: int, dmg: int, atk_type: String, cmbt: Node) -> void:
	var hs = GameServiceLocator.hitbox
	if not hs:
		return

	# El cuadrado se orienta hacia la dirección de traslación.
	var base_angle: float = translate_dir.angle() if translate_dir != Vector2.ZERO else 0.0

	for i in range(MINI_HEART_COUNT):
		var hb = hs.create({
			"attacker_id": cid,
			"attacker_node": pn,
			"type": "projectile",
			"aim_mode": "fixed",
			"direction": Vector2.RIGHT,
			"shape_scene": MINI_HEART_SCENE,
			"damage": dmg,
			"attack_type": atk_type,
			"hit_limit": 1,
			"team_filter": "enemy",
			"lifetime": MINI_HEART_LIFETIME,
			"speed": 0.0,
			"offset": 0.0,
			"impact_lifetime": 0.3,
			"custom_hitbox": true,
			"position": center_pos,
			"on_hit": func(target_node: Node) -> void:
				if is_instance_valid(target_node) and cmbt:
					cmbt.apply_damage(pn, target_node, dmg, atk_type)
		})
		if hb:
			hb.mode = "orbit"
			hb.orbit_center = center_pos
			hb.orbit_radius = HEART_SQUARE_RADIUS
			hb.orbit_speed = HEART_SQUARE_SPIN
			hb.orbit_angle = base_angle + float(i) * TAU / 4.0
			hb.orbit_angle_set = true
			hb.spin_speed = MINI_HEART_SPIN
			hb.orbit_translate = translate_dir * HEART_SQUARE_TRANSLATE_SPEED


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


## Avanza o resetea la evolución del slot según la cadena del AbilityData.
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
