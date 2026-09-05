extends Area2D

var attacker_id: int = -1
var attacker_node: Node
var direction: Vector2 = Vector2.RIGHT

var speed: float = 700.0
var max_distance: float = 500.0
var sine_amplitude: float = 40.0
var sine_frequency: float = 3.0
var lifetime_after_arrival: float = 2.0

var slow_magnitude: float = 0.0
var slow_duration: float = 0.0
var mine_tp_amount: float = 15.0

var on_hit_callback: Callable
var on_end_callback: Callable

var _start_position: Vector2
var _traveled: float = 0.0
var _arrived: bool = false
var _hit: bool = false
var _expired: bool = false
var _mine_mode: bool = false
var _end_called: bool = false

var _show_indicator: bool = false
var _indicator_time: float = 0.0


func _ready() -> void:
	if not multiplayer.is_server():
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
		if anim and anim.sprite_frames and anim.sprite_frames.has_animation("travel"):
			anim.play("travel")
		return

	_start_position = global_position
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _expired or _hit or _arrived:
		return

	var step: float = speed * delta
	_traveled += step

	if _traveled >= max_distance:
		_traveled = max_distance
		_arrived = true
		set_physics_process(false)
		_on_shot_completed(false)
		_enter_mine_mode()
		return

	var forward: Vector2 = _start_position + direction * _traveled
	var lateral_vec: Vector2 = direction.rotated(PI / 2.0)
	var lateral_offset: float = sin(_traveled * sine_frequency * 0.01) * sine_amplitude
	global_position = forward + lateral_vec * lateral_offset


func _process(delta: float) -> void:
	if _show_indicator:
		_indicator_time += delta
		queue_redraw()


func _draw() -> void:
	if not _show_indicator:
		return

	var base_radius: float = 48.0
	var pulse: float = 1.0 + sin(_indicator_time * 2.5) * 0.05
	var alpha: float = 0.2 + sin(_indicator_time * 1.8) * 0.12

	draw_circle(Vector2.ZERO, base_radius * pulse, Color(1.0, 0.15, 0.15, alpha))
	draw_arc(Vector2.ZERO, base_radius * pulse, 0.0, TAU, 48, Color(1.0, 0.0, 0.0, 0.5), 2.0)


@rpc("any_peer", "call_local", "reliable")
func _sync_indicator(should_show: bool) -> void:
	_show_indicator = should_show
	if should_show:
		_indicator_time = 0.0
	queue_redraw()


func _on_shot_completed(hit_flag: bool) -> void:
	if _end_called:
		return
	_end_called = true
	if on_end_callback.is_valid():
		on_end_callback.call(hit_flag)


func _enter_mine_mode() -> void:
	if _hit or _expired:
		return
	_mine_mode = true
	add_to_group("fluffy_mines")

	var col_shape: CollisionShape2D = $CollisionShape2D
	if col_shape:
		col_shape.scale = Vector2(1.5, 1.5)

	var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
	if anim_sprite:
		anim_sprite.stop()

	rpc("_sync_indicator", true)


func _handle_mine_hit(target: Node) -> void:
	var tp_svc = GameServiceLocator.tp
	if not tp_svc:
		return
	var target_id = target.get_multiplayer_authority()
	if target.is_in_group("killer"):
		if tp_svc.consume_tp(target_id, mine_tp_amount):
			tp_svc.add_tp_custom(attacker_id, mine_tp_amount)
			var combat = GameServiceLocator.combat_mediator
			if combat:
				combat.apply_slow(target, slow_duration, slow_magnitude)
	elif target.is_in_group("survivor"):
		tp_svc.add_tp_custom(target_id, mine_tp_amount)


func _on_area_entered(area: Area2D) -> void:
	if _expired or _hit:
		print("[FluffyProj] _on_area_entered ignorado: _expired=", _expired, " _hit=", _hit)
		return
	if not area.is_in_group("hurtbox"):
		print("[FluffyProj] area no es hurtbox: ", area.name, " groups: ", area.get_groups())
		return

	var target: Node = area.get_parent()
	print("[FluffyProj] area_entered | target: ", target, " | grupos: ", target.get_groups() if target else "null", " | attacker_id: ", attacker_id)
	if not target or not target.is_in_group("players"):
		print("[FluffyProj] target no es players o es null")
		return
	if target.get_multiplayer_authority() == attacker_id:
		print("[FluffyProj] self-hit ignorado")
		return

	print("[FluffyProj] GOLPE válido | mine_mode=", _mine_mode, " | on_hit_callback válido=", on_hit_callback.is_valid(), " | target: ", target.name)
	_hit = true
	set_physics_process(false)

	if _mine_mode:
		remove_from_group("fluffy_mines")
		_handle_mine_hit(target)
	else:
		if on_hit_callback.is_valid():
			on_hit_callback.call(target)
		else:
			print("[FluffyProj] ERROR: on_hit_callback NO es válido!")

	_expire()


func _expire() -> void:
	if _expired:
		return
	_expired = true
	set_physics_process(false)
	remove_from_group("fluffy_mines")
	if not _end_called:
		_end_called = true
		if on_end_callback.is_valid():
			on_end_callback.call(_hit)
	queue_free()
