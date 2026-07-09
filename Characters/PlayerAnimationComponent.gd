class_name PlayerAnimationComponent
extends Node

var player: CharacterBody2D = null


func initialize(body: CharacterBody2D) -> void:
	player = body


# ── Movement animation helpers ─────────────────────────────────────────

func select_movement_anim(is_moving: bool, is_running: bool, use_hurt: bool) -> String:
	var prioritized: Array[String] = []

	if use_hurt:
		if is_running:
			prioritized = ["run_hurt_horizontal", "run_horizontal", "walk_hurt_horizontal", "walk_horizontal", "idle_hurt_horizontal", "idle_horizontal"]
		elif is_moving:
			prioritized = ["walk_hurt_horizontal", "walk_horizontal", "idle_hurt_horizontal", "idle_horizontal"]
		else:
			prioritized = ["idle_hurt_horizontal", "idle_horizontal"]
	else:
		if is_running:
			prioritized = ["run_horizontal", "walk_horizontal", "idle_horizontal"]
		elif is_moving:
			prioritized = ["walk_horizontal", "idle_horizontal"]
		else:
			prioritized = ["idle_horizontal"]

	var frames = player.animated_sprite.sprite_frames if player.animated_sprite else null
	for anim_name in prioritized:
		if frames and frames.has_animation(anim_name):
			return anim_name
	return "default"


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
	player.animated_sprite.flip_h = not player.facing_right
	var anim_name = select_movement_anim(false, false, should_use_hurt_sprite())
	player.animated_sprite.play(anim_name)
	player.last_animation = anim_name


func end_stun() -> void:
	player.state = Player.AnimState.IDLE
	restore_idle()

func on_anim_finished() -> void:
	if player.state == Player.AnimState.STUNNED:
		if player.animated_sprite.animation == "stun_end":
			end_stun()
	elif player.state == Player.AnimState.ABILITY or player.state == Player.AnimState.PREPARE:
		player.state = Player.AnimState.IDLE
		player.active_ability_slot = -1
		restore_idle()


# ── Ability animation helpers ──────────────────────────────────────────

func apply_ability_anim_state(anim_name: String, facing_right_override: bool, slot_index: int, anim_state: int) -> void:
	if anim_name == "":
		return
	player.facing_right = facing_right_override
	player.facing = Vector2.RIGHT if player.facing_right else Vector2.LEFT
	player.animated_sprite.flip_h = not player.facing_right
	player.animated_sprite.play(anim_name)
	player.state = anim_state
	player.active_ability_slot = slot_index


func reset_ability_state() -> void:
	player.state = Player.AnimState.IDLE
	player.active_ability_slot = -1
	restore_idle()
