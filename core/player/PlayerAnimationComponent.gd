class_name PlayerAnimationComponent
extends Node

const MOVE_EPSILON: float = 0.1
const DIRECTIONAL_ANIM_PREFIXES := ["move_", "walk_", "run_", "idle_"]
const DIRECTIONAL_ANIM_SUFFIXES := ["_down", "_up", "_left", "_right"]

var player: CharacterBody2D = null


func initialize(body: CharacterBody2D) -> void:
	player = body


# ── Movement animation helpers ─────────────────────────────────────────

func is_directional_anim(anim_name: String) -> bool:
	for prefix: String in DIRECTIONAL_ANIM_PREFIXES:
		if anim_name.begins_with(prefix):
			for suffix: String in DIRECTIONAL_ANIM_SUFFIXES:
				if anim_name.ends_with(suffix):
					return true
			return false
	return false


func is_move_anim(anim_name: String) -> bool:
	return anim_name.begins_with("move_") and is_directional_anim(anim_name)


func _has_usable_animation(frames, anim_name: String) -> bool:
	return frames != null and frames.has_animation(anim_name) and frames.get_frame_count(anim_name) > 0


func _direction_from_vector(dir: Vector2) -> String:
	if absf(dir.x) >= absf(dir.y):
		return "right" if dir.x > 0.0 else "left"
	return "down" if dir.y > 0.0 else "up"


func resolve_direction(move_dir: Vector2) -> String:
	if move_dir.length() > MOVE_EPSILON:
		return _direction_from_vector(move_dir)
	if player and player.last_move_dir.length() > MOVE_EPSILON:
		return _direction_from_vector(player.last_move_dir)
	return "down"


func select_movement_anim(is_moving: bool, is_running: bool, use_hurt: bool, move_dir: Vector2 = Vector2.ZERO) -> String:
	var frames = player.animated_sprite.sprite_frames if player.animated_sprite else null
	var direction := resolve_direction(move_dir)
	var prioritized: Array[String] = []

	if is_moving:
		prioritized.append("move_" + direction)
		if is_running:
			prioritized.append("run_" + direction)
		prioritized.append("walk_" + direction)
	else:
		prioritized.append("idle_" + direction)

	if use_hurt:
		if is_running:
			prioritized.append_array(["run_hurt_horizontal", "run_horizontal", "walk_hurt_horizontal", "walk_horizontal", "idle_hurt_horizontal", "idle_horizontal"])
		elif is_moving:
			prioritized.append_array(["walk_hurt_horizontal", "walk_horizontal", "idle_hurt_horizontal", "idle_horizontal"])
		else:
			prioritized.append_array(["idle_hurt_horizontal", "idle_horizontal"])
	else:
		if is_running:
			prioritized.append_array(["run_horizontal", "walk_horizontal", "idle_horizontal"])
		elif is_moving:
			prioritized.append_array(["walk_horizontal", "idle_horizontal"])
		else:
			prioritized.append_array(["idle_horizontal"])

	if not is_moving:
		prioritized.append("move_" + direction)

	for anim_name in prioritized:
		if _has_usable_animation(frames, anim_name):
			return anim_name
	return "default"


func apply_movement_anim(anim_name: String, is_moving: bool) -> void:
	if anim_name == "" or anim_name == "default":
		return
	var sprite: AnimatedSprite2D = player.animated_sprite
	if not sprite:
		return
	var directional := is_directional_anim(anim_name)
	var current_anim := str(sprite.animation)
	sprite.flip_h = false if directional else not player.facing_right

	if not is_moving and is_move_anim(anim_name):
		if current_anim != anim_name:
			sprite.play(anim_name)
		if sprite.is_playing():
			sprite.pause()
		sprite.frame = 0
		player.last_animation = anim_name
		return

	if current_anim != anim_name or not sprite.is_playing():
		sprite.play(anim_name)
	player.last_animation = anim_name


func should_use_hurt_sprite() -> bool:
	var now = Time.get_ticks_msec()
	if now < player.hurt_flash_until:
		return true
	if player.character_data and player.health > 0:
		return player.health <= player.character_data.max_health * Player.LOW_HP_THRESHOLD
	else:
		return false


# ── Animation state machine ────────────────────────────────────────────

func restore_idle() -> void:
	if player.health_state != "alive":
		return
	if player.active_effects.has("stun"):
		player.state = Player.AnimState.STUNNED
		if _has_usable_animation(player.animated_sprite.sprite_frames, "stun"):
			player.animated_sprite.play("stun")
			player.last_animation = "stun"
		return
	var anim_name = select_movement_anim(false, false, should_use_hurt_sprite())
	apply_movement_anim(anim_name, false)


func end_stun() -> void:
	player.state = Player.AnimState.IDLE
	restore_idle()
	# Si el stun no canceló la fase 2 (flag configurable), recuperar la pose
	# y el estado ABILITY para que la movilidad RESTRICTED siga aplicándose.
	if player.fase2_active and player.has_method("restore_fase2_pose"):
		player.restore_fase2_pose()

func on_anim_finished() -> void:
	if player.state == Player.AnimState.STUNNED:
		if player.animated_sprite.animation == "stun_end":
			end_stun()
	elif player.state == Player.AnimState.ABILITY:
		var anim_name = player.animated_sprite.animation
		if player.animated_sprite.sprite_frames and player.animated_sprite.sprite_frames.has_animation(anim_name) and player.animated_sprite.sprite_frames.get_animation_loop(anim_name):
			return
		if player.hold_ability_anim:
			return
		player.state = Player.AnimState.IDLE
		player.active_ability_slot = -1
		restore_idle()
	elif player.state == Player.AnimState.PREPARE:
		player.state = Player.AnimState.IDLE
		player.active_ability_slot = -1
		restore_idle()
	elif player.state == Player.AnimState.EMOTE:
		var anim_name = player.animated_sprite.animation
		if player.animated_sprite.sprite_frames and player.animated_sprite.sprite_frames.has_animation(anim_name) and player.animated_sprite.sprite_frames.get_animation_loop(anim_name):
			return
		player.state = Player.AnimState.IDLE
		player._active_emote_slot = -1
		restore_idle()


# ── Ability animation helpers ──────────────────────────────────────────

func apply_ability_anim_state(anim_name: String, facing_right_override: bool, slot_index: int, anim_state: int) -> void:
	if anim_name == "":
		return
	player.hold_ability_anim = false
	var frames = player.animated_sprite.sprite_frames
	if frames and not frames.has_animation(anim_name):
		push_warning("[PlayerAnimation] Animación '%s' no existe, se cancela la habilidad." % anim_name)
		player.state = Player.AnimState.IDLE
		player.active_ability_slot = -1
		restore_idle()
		return
	player.facing_right = facing_right_override
	player.facing = Vector2.RIGHT if player.facing_right else Vector2.LEFT
	player.animated_sprite.flip_h = not player.facing_right
	player.animated_sprite.play(anim_name)
	player.state = anim_state
	if anim_state in [Player.AnimState.ABILITY, Player.AnimState.PREPARE]:
		player.active_ability_slot = slot_index


func reset_ability_state() -> void:
	player.hold_ability_anim = false
	if player.active_effects.has("stun"):
		player.state = Player.AnimState.STUNNED
		restore_idle()
		return
	player.state = Player.AnimState.IDLE
	player.active_ability_slot = -1
	restore_idle()
	
