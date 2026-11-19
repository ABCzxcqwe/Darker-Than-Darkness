extends AbilityBase

## Fluffy Filling en formato Fase 2 (AIM), siguiendo el patrón de RudeBusterAim.
##
## Flujo:
##   1. El jugador activa la habilidad -> se abre AIM (no consume TP).
##   2. Cada disparo consume `fase2_fire_tp_cost` (10 TP).
##   3. Click = 1 disparo; mantener M1 = auto-fire cada `fase2_fire_cadence`.
##   4. El AIM se cierra al alcanzar `fase2_max_shots` (2) o si el jugador
##      cancela con X (bloqueado mientras dura la animación de disparo).
##   5. El cooldown dinámico (12 + 1.5 * minas) se aplica al cerrar el AIM.
##
## La orquestación de timers, lockout, movimiento, cancelaciones e i-frames
## vive en AbilityRouter/AbilityFase2. Esta habilidad solo decide cuándo abrir
## el AIM, qué patrón de proyectiles lanzar y cuándo aplicar su cooldown.

const PROJECTILE_SPEED: float = 700.0
const PROJECTILE_MAX_DISTANCE: float = 500.0
const SINE_AMPLITUDE: float = 40.0
const SINE_FREQUENCY: float = 3.0
const LIFETIME_AFTER_ARRIVAL: float = 2.0
const TP_PER_HIT: float = 15.0
const FIRE_INTERVAL: float = 0.5
const CAST_BUFFER: float = 0.3
const COOLDOWN_BASE: float = 12.0
const COOLDOWN_PER_MINE: float = 1.5
const SLOW_MAGNITUDE: float = 0.5
const SLOW_DURATION: float = 3.0
const DEFAULT_SLOT: int = 3

static var _projectile_container: Node = null

var _caster_id: int = -1
var _slot_index: int = -1
var _total_hits: int = 0
var _active: bool = false
var _cooldown_applied: bool = false
var _cast_token: int = 0
var _tp_svc = null
var _cd_svc = null
var _data: AbilityData = null
var _player_node: Node = null
var _container: Node = null
var _shape_scene: PackedScene = null


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return
	if not player_node.multiplayer.is_server():
		return
	if not data.has_fase2 or data.fase2_kind != AbilityData.Fase2Kind.AIM:
		push_warning("[FluffyFillingAim] has_fase2/kind no configurado en el .tres.")
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
	var hs = GameServiceLocator.hitbox
	var tp_svc = GameServiceLocator.tp
	var cd = GameServiceLocator.cooldown
	if not hs or not tp_svc:
		AbilityRouter.abort_fase2(caster_id, entry_slot)
		return

	var fire_cost: float = data.fase2_fire_tp_cost
	if fire_cost > 0.0 and not tp_svc.consume_tp(caster_id, fire_cost):
		# Sin TP: cerrar el AIM. Si ya hubo disparos, on_fase2_end aplicará
		# el cooldown dinámico; si no, el router usa fase2_cancel_cd.
		AbilityRouter.cancel_aim(caster_id, entry_slot)
		return

	_data = data
	_player_node = player_node
	_caster_id = caster_id
	_slot_index = entry_slot
	_tp_svc = tp_svc
	_cd_svc = cd
	_active = true
	_cooldown_applied = false
	_total_hits = 0

	var fire_dir: Vector2 = direction.normalized()
	if fire_dir == Vector2.ZERO:
		fire_dir = Vector2.RIGHT if player_node.facing_right else Vector2.LEFT

	_container = _get_container(player_node)
	_shape_scene = data.ability_scene
	if not _container or not _shape_scene:
		push_error("[FluffyFillingAim] No se encontró container o shape_scene.")
		AbilityRouter.abort_fase2(caster_id, entry_slot)
		return

	var fire_anim: String = data.fase2_fire_animation
	if fire_anim != "":
		player_node.play_ability_animation(fire_anim, entry_slot, fire_dir.x >= 0.0)
	player_node.rpc("_sync_fase2_firing", true)
	var anim_dur := _get_anim_duration(player_node, fire_anim)

	var projectile_count: int = _get_projectile_count(data)
	var total_cast: float = anim_dur + FIRE_INTERVAL * max(0, projectile_count - 1) + CAST_BUFFER

	# Mientras dura el cast, X no puede cancelar.
	AbilityRouter.mark_fase2_firing(caster_id, entry_slot, total_cast)

	# La instancia queda registrada para que AbilityFase2 llame on_fase2_end
	# al cerrar/cancelar el AIM y podamos aplicar el cooldown dinámico.
	AbilityBase.register_active(caster_id, entry_slot, self)

	# Contar el disparo y decidir si el AIM se cierra (máximo alcanzado).
	var should_close_aim: bool = AbilityRouter.register_fase2_shot(caster_id, entry_slot)

	var combat = GameServiceLocator.combat_mediator
	if combat:
		combat.apply_root(player_node, total_cast)

	# Programar los proyectiles de este disparo (1 o 2 según la evolución).
	var shot_dir: Vector2 = fire_dir
	var fire_start: float = anim_dur * 0.3
	for i in range(projectile_count):
		player_node.get_tree().create_timer(fire_start + FIRE_INTERVAL * i).timeout.connect(
			func(): _fire_shot(shot_dir)
		)

	if should_close_aim:
		# Cierra el AIM; AbilityFase2 llama on_fase2_end -> cooldown dinámico.
		AbilityRouter.end_fase2_after_fire(caster_id, entry_slot, true)
	else:
		# Sigue apuntando: liberar el lock del slot para el próximo disparo y
		# restaurar la pose de AIM al terminar la animación de disparo.
		if cd and cd.has_method("release_lock"):
			cd.release_lock(caster_id, entry_slot)

	# Al terminar el cast: quitar root y restaurar pose de AIM si sigue activo.
	_cast_token += 1
	var cast_token: int = _cast_token
	player_node.get_tree().create_timer(total_cast).timeout.connect(
		func(): _end_cast(cast_token)
	)

	print("[FluffyFillingAim] Disparo | peer: ", caster_id,
		" | dir: ", fire_dir, " | proyectiles: ", projectile_count,
		" | cierra AIM: ", should_close_aim)


func _fire_shot(shot_dir: Vector2) -> void:
	if not is_instance_valid(_player_node):
		return
	if not _container or not _shape_scene:
		return

	var projectile = _shape_scene.instantiate()
	projectile.attacker_id = _caster_id
	projectile.attacker_node = _player_node
	projectile.direction = shot_dir
	projectile.speed = PROJECTILE_SPEED
	projectile.max_distance = PROJECTILE_MAX_DISTANCE
	projectile.sine_amplitude = SINE_AMPLITUDE
	projectile.sine_frequency = SINE_FREQUENCY
	projectile.lifetime_after_arrival = LIFETIME_AFTER_ARRIVAL
	projectile.set_multiplayer_authority(_player_node.get_tree().get_multiplayer().get_unique_id())

	projectile.collision_layer = 32
	projectile.collision_mask = 8 | 16

	projectile.on_hit_callback = _on_projectile_hit
	projectile.on_end_callback = _on_projectile_end
	projectile.slow_magnitude = SLOW_MAGNITUDE
	projectile.slow_duration = SLOW_DURATION
	projectile.mine_tp_amount = TP_PER_HIT

	var parent_2d := _container as Node2D
	var projectile_2d := projectile as Node2D
	if parent_2d and projectile_2d:
		projectile_2d.position = parent_2d.to_local(_player_node.global_position)
	elif projectile_2d:
		projectile_2d.global_position = _player_node.global_position
	_container.add_child(projectile, true)
	if not parent_2d and projectile_2d:
		projectile_2d.global_position = _player_node.global_position


# ── Fin del cast ────────────────────────────────────────────────────────────

func _end_cast(cast_token: int) -> void:
	# Si ya arrancó un disparo posterior, este cast viejo no debe pisar su
	# root/animación.
	if cast_token != _cast_token:
		return
	if not is_instance_valid(_player_node):
		return

	_player_node.rpc("_sync_fase2_firing", false)

	var combat = GameServiceLocator.combat_mediator
	if combat:
		combat.remove_root(_player_node)

	# Si el AIM sigue abierto, volver a la pose de apuntado. Si se cerró,
	# limpiar el efecto de apuntado y la animación de habilidad.
	if AbilityRouter.is_fase2_active(_caster_id, _slot_index):
		if _data and _data.prepare_animation != "":
			_player_node.play_prepare_animation(
				_data.prepare_animation, _slot_index, _player_node.facing_right)
	else:
		_active = false
		_player_node.rpc("_sync_effect", "free_look", false)
		_player_node.rpc("_sync_cancel_ability")


## Hook de AbilityFase2: se llama al cerrar o cancelar el AIM.
## Si hubo al menos un disparo, aplica el cooldown dinámico (minas incluidas).
func on_fase2_end(_reason: String, shots_fired: int) -> void:
	if shots_fired <= 0:
		return
	_finish_ability()


func _finish_ability() -> void:
	if _cooldown_applied:
		return
	_cooldown_applied = true
	_active = false

	if not is_instance_valid(_player_node):
		return

	var active_mines := _count_active_mines()
	var cd_value: float = COOLDOWN_BASE + COOLDOWN_PER_MINE * active_mines

	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
		_cd_svc.start(_caster_id, _slot_index, cd_value)

	print("[FluffyFillingAim] AIM cerrado | hits: ", _total_hits,
		" | minas activas: ", active_mines, " | cooldown: ", cd_value, "s")


# ── Callbacks del proyectil ─────────────────────────────────────────────────

func _on_projectile_hit(target_node: Node) -> void:
	if not is_instance_valid(target_node):
		return
	if not _tp_svc:
		return

	var health_svc = GameServiceLocator.health
	var target_id: int = PlayerLifecycleManager.get_owner_peer_id(target_node)

	if health_svc and not health_svc.is_alive(target_id):
		return

	if target_node.is_in_group("killer"):
		var taken: bool = _tp_svc.consume_tp(target_id, TP_PER_HIT)
		if taken:
			_tp_svc.add_tp_custom(_caster_id, TP_PER_HIT)
			var combat = GameServiceLocator.combat_mediator
			if combat:
				combat.apply_slow(target_node, SLOW_DURATION, SLOW_MAGNITUDE)
	elif target_node.is_in_group("survivor"):
		_tp_svc.add_tp_custom(target_id, TP_PER_HIT)


func _on_projectile_end(hit_flag: bool) -> void:
	if hit_flag:
		_total_hits += 1


# ── Helpers ─────────────────────────────────────────────────────────────────

func _count_active_mines() -> int:
	var tree = _player_node.get_tree() if is_instance_valid(_player_node) else null
	if not tree:
		return 0
	var count := 0
	for mine in tree.get_nodes_in_group("fluffy_mines"):
		if is_instance_valid(mine):
			var attacker_id = mine.get("attacker_id") if "attacker_id" in mine else -1
			if attacker_id == _caster_id:
				count += 1
	return count


func _get_projectile_count(data: AbilityData) -> int:
	if data and data.projectile_count > 0:
		return data.projectile_count
	return 1


func _get_container(player_node: Node) -> Node:
	if not is_instance_valid(_projectile_container):
		var world = player_node.get_tree().root.find_child("World", true, false)
		_projectile_container = world.get_node_or_null("Projectiles") if world else null
	return _projectile_container


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return 0.5
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return 0.5
	if not sprite.sprite_frames.has_animation(anim_name):
		return 0.5
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return 0.5
	return frame_count / fps
