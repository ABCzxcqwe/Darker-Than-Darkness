extends CharacterBody2D

# ── Asignados por HitboxService antes de add_child() ──────────────────
var attacker_id:  int     = -1
var attacker_node: Node   = null
var damage:       int     = 10
var attack_type:  String  = "normal"

var hit_limit:    int     = 1
var team_filter:  String  = "enemy"
var lifetime:     float   = 0.25
var speed:        float   = 0.0
var aim_mode:     String  = "fixed"
var detect_walls: bool    = false
var impact_lifetime: float = 0.0
var hitbox_max_range: float = 0.0

var on_hit_callback: Callable
var on_end_callback: Callable

# ── Configuración del DevilKnife ──────────────────────────────────────
var rotation_speed: float = 12.566
var bounce_on_wall: bool  = true

# ── Estado interno ─────────────────────────────────────────────────────
var _hit_count:   int    = 0
var _expired:     bool   = false
var _impacted:    bool   = false
var _direction:   Vector2 = Vector2.RIGHT
var _travel_distance: float = 0.0
var _hit_targets: Array  = []


func _ready() -> void:
	if not multiplayer.is_server():
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
		if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("travel"):
			anim_sprite.play("travel")
		return
	set_multiplayer_authority(1)
	var detector = $HurtboxDetector
	detector.collision_mask = collision_mask
	detector.area_entered.connect(_on_area_entered)
	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(_expire)


func set_direction(dir: Vector2) -> void:
	_direction = dir.normalized()


func _physics_process(delta: float) -> void:
	if _expired or _impacted:
		return
	if speed <= 0.0:
		return

	rotation += rotation_speed * delta

	var step: float = speed * delta

	if hitbox_max_range > 0.0:
		_travel_distance += step
		if _travel_distance >= hitbox_max_range:
			_do_impact(true)
			return

	if detect_walls:
		var motion = _direction * step
		var collision = move_and_collide(motion)
		if collision:
			var collider = collision.get_collider()
			if collider is StaticBody2D:
				if bounce_on_wall:
					_direction = _direction.bounce(collision.get_normal())
				else:
					_do_impact()
	else:
		global_position += _direction * step


func _on_area_entered(area: Area2D) -> void:
	if _expired or _impacted:
		return
	if not area.is_in_group("hurtbox"):
		return

	var target: Node = area.get_parent()
	if not target or not target.is_in_group("players"):
		return

	var target_id: int = target.get_multiplayer_authority()
	if target_id == attacker_id:
		return

	if not _passes_team_filter(target):
		return

	if _hit_targets.has(target_id):
		return
	_hit_targets.append(target_id)

	_hit_count += 1
	if on_hit_callback.is_valid():
		on_hit_callback.call(target)

	if hit_limit > 0 and _hit_count >= hit_limit:
		if impact_lifetime > 0.0:
			_do_impact()
		else:
			_expire()


func _do_impact(timeout_expire: bool = false) -> void:
	if _impacted:
		return
	_impacted = true
	set_physics_process(false)
	speed = 0.0

	var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("hit"):
		anim_sprite.play("hit")

	if timeout_expire:
		_expire()
	elif impact_lifetime > 0.0:
		get_tree().create_timer(impact_lifetime).timeout.connect(_expire)
	else:
		_expire()


func _expire() -> void:
	if _expired:
		return
	_expired = true
	set_physics_process(false)
	if on_end_callback.is_valid():
		on_end_callback.call(_hit_count)
	queue_free()


func _passes_team_filter(target: Node) -> bool:
	if team_filter == "all":
		return true
	var attacker_team := _get_attacker_team()
	var target_team: String = target.character_data.team if target.character_data else ""
	if team_filter == "enemy":
		return target_team != attacker_team
	if team_filter == "ally":
		return target_team == attacker_team
	return true


func _get_attacker_team() -> String:
	if attacker_node and attacker_node.character_data:
		return attacker_node.character_data.team
	return ""
