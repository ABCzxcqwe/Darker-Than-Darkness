extends Area2D

var attacker_id: int = -1
var attacker_node: Node
var direction: Vector2 = Vector2.RIGHT

var speed: float = 700.0
var max_distance: float = 500.0
var sine_amplitude: float = 40.0
var sine_frequency: float = 3.0
var lifetime_after_arrival: float = 2.0

var on_hit_callback: Callable
var on_end_callback: Callable

var _start_position: Vector2
var _traveled: float = 0.0
var _arrived: bool = false
var _hit: bool = false
var _expired: bool = false


func _ready() -> void:
	if not multiplayer.is_server():
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
		if anim and anim.sprite_frames and anim.sprite_frames.has_animation("travel"):
			anim.play("travel")
		print("[FluffyProj] _ready CLIENTE | pos: ", global_position)
		return

	_start_position = global_position
	area_entered.connect(_on_area_entered)

	var total_lifetime: float = (max_distance / speed) + lifetime_after_arrival + 0.5
	print("[FluffyProj] _ready SERVER | pos: ", global_position, " | dir: ", direction, " | lifetime: ", total_lifetime, " | on_hit valido: ", on_hit_callback.is_valid(), " | on_end valido: ", on_end_callback.is_valid())
	get_tree().create_timer(total_lifetime).timeout.connect(_expire)


func _physics_process(delta: float) -> void:
	if _expired or _hit or _arrived:
		return

	var step: float = speed * delta
	_traveled += step

	if _traveled >= max_distance:
		_traveled = max_distance
		_arrived = true
		set_physics_process(false)
		var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
		if anim and anim.sprite_frames and anim.sprite_frames.has_animation("idle"):
			anim.play("idle")
		get_tree().create_timer(lifetime_after_arrival).timeout.connect(_expire)
		return

	var forward: Vector2 = _start_position + direction * _traveled
	var lateral_vec: Vector2 = direction.rotated(PI / 2.0)
	var lateral_offset: float = sin(_traveled * sine_frequency * 0.01) * sine_amplitude
	global_position = forward + lateral_vec * lateral_offset


func _on_area_entered(area: Area2D) -> void:
	print("[FluffyProj] _on_area_entered | _expired: ", _expired, " | _hit: ", _hit, " | area grupo hurtbox: ", area.is_in_group("hurtbox"))
	if _expired or _hit:
		return
	if not area.is_in_group("hurtbox"):
		return

	var target: Node = area.get_parent()
	print("[FluffyProj] target: ", target, " | grupo players: ", target.is_in_group("players") if target else "no target", " | target_id: ", target.get_multiplayer_authority() if target else -1, " | attacker_id: ", attacker_id)
	if not target or not target.is_in_group("players"):
		return
	if target.get_multiplayer_authority() == attacker_id:
		print("[FluffyProj] self-hit ignorado")
		return

	_hit = true
	set_physics_process(false)

	print("[FluffyProj] GOLPEÓ a: ", target.name, " | on_hit_callback valido: ", on_hit_callback.is_valid())
	if on_hit_callback.is_valid():
		on_hit_callback.call(target)

	var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("hit"):
		anim.play("hit")

	_expire()


func _expire() -> void:
	print("[FluffyProj] _expire | _expired: ", _expired, " | _hit: ", _hit, " | on_end valido: ", on_end_callback.is_valid())
	if _expired:
		return
	_expired = true
	set_physics_process(false)
	if on_end_callback.is_valid():
		on_end_callback.call(_hit)
	queue_free()
