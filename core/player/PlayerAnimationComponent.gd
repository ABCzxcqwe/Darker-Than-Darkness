class_name PlayerAnimationComponent
extends Node

const MOVE_EPSILON: float = 0.1
const KRIS_CHARACTER_ID: int = 1

var player: CharacterBody2D = null


func initialize(body: CharacterBody2D) -> void:
	player = body


# ── Movement animation helpers ─────────────────────────────────────────

func select_movement_anim(is_moving: bool, is_running: bool, use_hurt: bool, move_dir: Vector2 = Vector2.ZERO) -> String:
	var frames = player.animated_sprite.sprite_frames if player.animated_sprite else null

	if _is_kris_pressing_down(move_dir):
		for anim_name: String in ["walk_down", "idle_down"]:
			if frames and frames.has_animation(anim_name):
				return anim_name

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

	for anim_name in prioritized:
		if frames and frames.has_animation(anim_name):
			return anim_name
	return "default"


func _is_kris_pressing_down(move_dir: Vector2) -> bool:
	if not player.character_data or player.character_data.id != KRIS_CHARACTER_ID:
		return false
	return move_dir.y > MOVE_EPSILON and absf(move_dir.y) >= absf(move_dir.x)


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
		if player.animated_sprite.sprite_frames.has_animation("stun"):
			player.animated_sprite.play("stun")
			player.last_animation = "stun"
		return
	player.animated_sprite.flip_h = not player.facing_right
	var anim_name = select_movement_anim(false, false, should_use_hurt_sprite())
	player.animated_sprite.play(anim_name)
	player.last_animation = anim_name


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
	
