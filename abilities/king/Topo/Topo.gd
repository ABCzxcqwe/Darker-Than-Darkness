extends AbilityBase
class_name TopoAbility

# King Topo — Undyne style: X activa king_topo (inmune, último frame), luego 5 oleadas
# cada 1.5s: señal.png warning alrededor de survivors -> lanza2 2-5x crece vertical -> hold 1.5s -> retrae

const WAVE_COUNT: int = 5
const WAVE_INTERVAL: float = 1.5      # intervalo entre inicios de oleadas
const WARNING_TIME: float = 1.0       # señal visible antes de lanza
const SPEAR_HOLD: float = 1.5         # tras altura máxima (1.5s)
const SPEARS_PER_SURVIVOR: int = 8
const WARNING_RADIUS: float = 110.0
const SPEAR_MIN_MULT: float = 2.0
const SPEAR_MAX_MULT: float = 5.0

# Texturas aviso
const SIGNAL_TEX := preload("res://Characters/King/assets/Sprites/señal.png")

static var _keep_alive: Array = []

var _active: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _cd_svc: Node = null
var _combat: Node = null
var _total_duration: float = 0.0


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
	# Reproduce king_topo y congela en último frame
	player_node.play_ability_animation(data.action_animation, _slot_index, facing_right)
	player_node.hold_ability_anim = true
	player_node.rpc("_sync_ability_hold", true)

	# Cálculo duración total: warning primera oleada + 5 oleadas * (grow+hold+retract) + buffer
	var grow_time: float = 0.5
	var wave_life: float = WARNING_TIME + grow_time + SPEAR_HOLD + 0.5
	_total_duration = float(WAVE_COUNT - 1) * WAVE_INTERVAL + wave_life + 0.5
	if data.cast_duration > 0.0:
		_total_duration = maxf(_total_duration, data.cast_duration)

	if _combat:
		_combat.apply_root(_player_node, _total_duration)

	_grant_invincibility(_total_duration)

	# Aplicar sprint_disabled a todos los survivors durante la duración total
	var status_svc = GameServiceLocator.status_effect
	if status_svc:
		for survivor in _get_alive_survivors():
			if is_instance_valid(survivor):
				status_svc.apply(survivor, "sprint_disabled", { "duration": _total_duration })

	_keep_alive.append(self)

	# Cooldown diferido
	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
		_cd_svc.start(_caster_id, _slot_index, data.cooldown)

	# Lanzar oleadas — usar bind() para capturar w por valor (evita closure por referencia que congelaba)
	for w in range(WAVE_COUNT):
		var delay: float = float(w) * WAVE_INTERVAL
		var tree := player_node.get_tree()
		if tree:
			tree.create_timer(delay).timeout.connect(_spawn_wave.bind(w))

	# Finalización — timer robusto aunque player_node se libere
	var tree_fin := player_node.get_tree()
	if tree_fin:
		tree_fin.create_timer(_total_duration).timeout.connect(_finish)
	else:
		# Fallback si el árbol no está disponible (evita hold infinito que congelaba todo)
		await Engine.get_main_loop().create_timer(_total_duration).timeout
		_finish()

	print("[Topo] Habilidad iniciada | peer: ", _caster_id, " | oleadas: ", WAVE_COUNT, " | duración: ", _total_duration)


func _grant_invincibility(duration: float) -> void:
	if not is_instance_valid(_player_node):
		return
	var ms: int = int(duration * 1000.0)
	_player_node.invincible_until = Time.get_ticks_msec() + ms
	_player_node.rpc("_sync_invincibility", ms)


func _spawn_wave(wave_idx: int) -> void:
	if not _active or not is_instance_valid(_player_node):
		return
	if not _player_node.get_tree():
		return

	var survivors := _get_alive_survivors()
	if survivors.is_empty():
		# Sin survivors, spawnea alrededor de King
		survivors = [_player_node]

	for survivor in survivors:
		if not is_instance_valid(survivor):
			continue
		# 8 posiciones random cloud doble rango (280-440), algunas cerca/lejos, no círculo perfecto
		for i in range(SPEARS_PER_SURVIVOR):
			var angle: float = randf() * TAU
			var dist: float = randf_range(100.0, 440.0)
			# Mezcla cerca/lejos: 30% cerca 100-180, 70% lejos 200-440
			if randf() < 0.3:
				dist = randf_range(100.0, 180.0)
			else:
				dist = randf_range(220.0, 440.0)
			var offset := Vector2(dist, 0).rotated(angle)
			var pos: Vector2 = survivor.global_position + offset
			_spawn_warning(pos, wave_idx, i)


func _spawn_warning(pos: Vector2, wave_idx: int, spear_idx: int) -> void:
	if not is_instance_valid(_player_node) or not _player_node.get_tree():
		return
	if not is_instance_valid(_player_node) or not _player_node.multiplayer.is_server():
		return

	var world = _player_node.get_tree().root.find_child("World", true, false)
	if not world:
		return
	var container = world.get_node_or_null("Projectiles")
	if not container:
		container = world

	var warning_scene := preload("res://Hitboxes/King/Topo/WarningCircle.tscn")
	var warning = warning_scene.instantiate()
	warning.global_position = pos
	# Duración del círculo sincronizada con lanza: visible hasta que lanza desaparezca (1.5s hold + grow/retract)
	var circle_duration: float = WARNING_TIME + SPEAR_HOLD + 1.0
	if "radius" in warning:
		warning.radius = WARNING_RADIUS
	if "duration" in warning:
		warning.duration = circle_duration
	elif warning.has_method("set_duration"):
		warning.set_duration(circle_duration)
	container.add_child(warning, true)

	# Tras warning, spawnea lanza — bind pos por valor
	var tree2 := _player_node.get_tree()
	if tree2:
		tree2.create_timer(WARNING_TIME).timeout.connect(_spawn_spear.bind(pos))


func _spawn_spear(pos: Vector2) -> void:
	if not _active or not is_instance_valid(_player_node):
		return
	if not is_instance_valid(_player_node) or not _player_node.multiplayer.is_server():
		return
	if not _player_node.get_tree():
		return

	var world = _player_node.get_tree().root.find_child("World", true, false)
	if not world:
		return
	var container = world.get_node_or_null("Projectiles")
	if not container:
		container = world

	var spear_scene := preload("res://Hitboxes/King/Topo/TopoSpear.tscn")
	var spear = spear_scene.instantiate()
	spear.global_position = pos
	spear.origin = pos
	spear.attacker_id = _caster_id
	spear.attacker_node = _player_node
	spear.damage = _data.base_damage if _data and _data.base_damage > 0 else 10
	spear.attack_type = _data.attack_type if _data else "normal"
	spear.team_filter = "enemy"
	# Mult 2-5x (entero aleatorio: 2, 3, 4 o 5)
	var mult: float = float([2, 3, 4, 5].pick_random())
	if spear.has_method("setup_topo"):
		spear.setup_topo(self, _player_node, mult)
	# HitboxService no necesario: directamente add, pero setear layers
	container.add_child(spear, true)

	# Sincroniza hurtbox layers (HitboxService lo hace, aquí manual)
	var area := spear.get_node_or_null("Hurtbox") as Area2D
	if area:
		area.collision_layer = 32
		area.collision_mask = 8


func _get_alive_survivors() -> Array:
	var result: Array = []
	if not is_instance_valid(_player_node) or not _player_node.get_tree():
		return result
	for n in _player_node.get_tree().get_nodes_in_group("survivor"):
		if not is_instance_valid(n):
			continue
		if n.health_state != "alive":
			continue
		result.append(n)
	return result


func _finish() -> void:
	if not _active:
		return
	_active = false

	# Remover sprint_disabled de todos los survivors
	var status_svc = GameServiceLocator.status_effect
	if status_svc:
		for survivor in _get_alive_survivors():
			if is_instance_valid(survivor):
				status_svc.remove_effect(survivor, "sprint_disabled")

	if _combat and is_instance_valid(_player_node):
		_combat.remove_root(_player_node)

	if is_instance_valid(_player_node):
		_player_node.hold_ability_anim = false
		_player_node.rpc("_sync_cancel_ability")

	_keep_alive.erase(self)
	print("[Topo] Finalizada | peer: ", _caster_id)


func _fail_cleanup() -> void:
	_active = false
	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
	print("[Topo] Fallo activación | peer: ", _caster_id)
