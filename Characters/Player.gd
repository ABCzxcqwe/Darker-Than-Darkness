# res://characters/Player.gd
class_name Player
extends CharacterBody2D

signal ability_used(ability_index: int)

enum AnimState { IDLE, PREPARE, ABILITY, STUNNED }

const HURT_FLASH_DURATION_MS: int = 300
const HEAL_FLASH_DURATION_MS: int = 300
const LOW_HP_THRESHOLD: float = 0.25
@onready var synchronizer      = $Synchronizer
@onready var animated_sprite   = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var world_c           = $CollisionShape2D
@onready var hurtbox_c         = $Hurtbox/CollisionShape2D
@onready var name_tag: PanelContainer = $NameTag

@onready var interaction: PlayerInteractionComponent = $PlayerInteractionComponent
@onready var animation_component: PlayerAnimationComponent = $PlayerAnimationComponent
var movement_component: PlayerMovementComponent

var character_data:   CharacterData
var health:           int    = 0
var health_state:     String = "alive"
var last_animation:   String = "idle_horizontal"
var facing_right:     bool   = true
var invincible_until: int    = 0
var hurt_flash_until: int    = 0
var heal_flash_until: int    = 0
var _original_modulate: Color

var facing: Vector2 = Vector2.RIGHT

var active_effects: Dictionary = {}
var state: int       = AnimState.IDLE
var active_ability_slot: int = -1
var _latest_aim_dir: Vector2 = Vector2.RIGHT
var _secret_heal_used: bool = false
var _pending_selection_slot: int = -1
var aiming_slot: int = -1
var _last_slot_request_time: Dictionary = {}


func _ready() -> void:
	print("[Player] _ready() | nombre: ", name, " | autoridad: ", is_multiplayer_authority())

	movement_component = $PlayerMovementComponent
	interaction.initialize(self)
	animation_component.initialize(self)
	movement_component.initialize(self)
	if character_data:
		movement_component.speed = character_data.speed

	if not synchronizer:
		push_error("[Player] No se encontró 'Synchronizer'. Revisa player.tscn")

	if character_data:
		add_to_group(character_data.team)
		if character_data.team == "killer":
			add_to_group(GroupNames.KILLER)

	add_to_group(GroupNames.PLAYERS)

	if not is_multiplayer_authority():
		if $Camera2D:
			$Camera2D.enabled = false
	else:
		var listener = AudioListener2D.new()
		add_child(listener)
		listener.make_current()

	if character_data:
		PlayerRegistry.register(get_multiplayer_authority(), self)
		if multiplayer.is_server():
			PlayerLifecycleManager.register_player(self, get_multiplayer_authority(), character_data)

	if animated_sprite and animated_sprite.animation_finished.is_connected(_on_anim_finished) == false:
		animated_sprite.animation_finished.connect(_on_anim_finished)

	if animated_sprite:
		_original_modulate = animated_sprite.modulate

	_setup_name_tag()


func _setup_name_tag() -> void:
	var peer_id := get_multiplayer_authority()

	if is_multiplayer_authority():
		name_tag.visible = false
		return

	var name_str = LobbyManager.players.get(peer_id, {}).get("name", "Jugador %d" % peer_id)
	var name_label: Label = name_tag.get_node("NameLabel")
	name_label.text = name_str

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color.WHITE
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	name_tag.add_theme_stylebox_override("panel", style)

	var font := preload("res://Fonts/deltarune font.ttf")
	name_label.add_theme_font_override("font", font)
	name_label.add_theme_font_size_override("font_size", 12)




func _process(_delta: float) -> void:
	if not animated_sprite:
		return
	if health_state == "dead":
		return

	var now := Time.get_ticks_msec()
	var target_modulate := _original_modulate

	if now < invincible_until and state != AnimState.ABILITY:
		var _show := (sin(now * 0.015) * 0.5 + 0.5) > 0.35
		target_modulate.a = _original_modulate.a if _show else 0.2

	if now < heal_flash_until:
		var strength = float(heal_flash_until - now) / HEAL_FLASH_DURATION_MS
		target_modulate *= Color(1.0, 1.0, 1.0).lerp(Color(0.5, 1.5, 0.5), strength)

	if not animated_sprite.modulate.is_equal_approx(target_modulate):
		animated_sprite.modulate = target_modulate

	if state == AnimState.IDLE and character_data and character_data.id == 4 and last_animation == "idle_horizontal":
		animated_sprite.position.y = sin(Time.get_ticks_msec() * 0.005) * 16.0
	else:
		animated_sprite.position.y = 0.0


# ── Rescate ───────────────────────────────────────────────────────────

func _try_revive() -> void:
	var my_data := character_data
	var _range: float = my_data.revive_range if my_data else 80.0

	var closest_target = interaction.find_closest_revivable_target(_range)
	if not closest_target: return

	if multiplayer.is_server():
		GameServiceLocator.revive.request_revive(self, closest_target)
	else:
		rpc_id(1, "_request_revive", closest_target.get_multiplayer_authority())


@rpc("any_peer", "reliable")
func _request_revive(target_peer_id: int) -> void:
	var caller_id := multiplayer.get_remote_sender_id()
	if caller_id != get_multiplayer_authority(): return

	var rescuer_node := interaction.get_self_on_server()
	var target_node  := PlayerRegistry.get_player(target_peer_id)
	if not rescuer_node or not target_node: return

	GameServiceLocator.revive.request_revive(rescuer_node, target_node)


@rpc("any_peer", "reliable")
func _request_cancel_revive() -> void:
	var caller_id := multiplayer.get_remote_sender_id()
	if caller_id != get_multiplayer_authority(): return
	GameServiceLocator.revive.cancel_revive(get_multiplayer_authority())


func _exit_tree() -> void:
	var peer_id : int = -1
	if multiplayer.multiplayer_peer != null:
		peer_id = get_multiplayer_authority()
	if peer_id != -1:
		PlayerLifecycleManager.unregister_player(peer_id, self)


# ── Input ─────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return

	if interaction.is_spectator:
		interaction.handle_spectator_input(event)
		return

	if health_state != "alive": return

	var action_map = {
		"ability_1": 1,
		"ability_2": 2,
		"ability_3": 3,
		"ability_4": 4,
		"ability_0": 0,
	}
	var mouse_dir: Vector2

	if event.is_action_pressed("confirm") and aiming_slot >= 0:
		print("[Player] Confirmando habilidad de apuntado | slot: ", aiming_slot)
		mouse_dir = (get_global_mouse_position() - global_position).normalized()
		if multiplayer.is_server():
			AbilityRouter.request_ability(aiming_slot, mouse_dir)
		else:
			AbilityRouter.rpc_id(1, "request_ability", aiming_slot, mouse_dir)
		aiming_slot = -1
		return

	for action in action_map:
		if event.is_action_pressed(action):
			var slot: int = action_map[action]
			print("[Player] Tecla detectada | action: ", action, " | slot: ", slot,
				  " | state: ", state, " | pending_slot: ", _pending_selection_slot,
				  " | active_slot: ", active_ability_slot)

			var now := Time.get_ticks_msec()
			if _last_slot_request_time.has(slot) and now - _last_slot_request_time[slot] < 150:
				print("[Player] Ignorado (debounce) | slot: ", slot)
				return
			_last_slot_request_time[slot] = now

			if aiming_slot >= 0:
				print("[Player] En aim mode | action: ", action, " | slot presionado: ", slot, " | aiming_slot: ", aiming_slot)
				if action == "ability_0":
					print("[Player] M1 detectado en aim mode → disparando slot ", aiming_slot)
					mouse_dir = (get_global_mouse_position() - global_position).normalized()
					if multiplayer.is_server():
						AbilityRouter.request_ability(aiming_slot, mouse_dir)
					else:
						AbilityRouter.rpc_id(1, "request_ability", aiming_slot, mouse_dir)
					aiming_slot = -1
					print("[Player] aiming_slot reseteado a -1, retornando")
					return
				elif slot == aiming_slot:
					print("[Player] Misma tecla detectada en aim mode → cancelando slot ", aiming_slot)
					var peer_id = get_multiplayer_authority()
					if multiplayer.is_server():
						AbilityRouter.cancel_aim(peer_id, aiming_slot)
					else:
						AbilityRouter.rpc_id(1, "cancel_aim", peer_id, aiming_slot)
					aiming_slot = -1
					print("[Player] Cancelación enviada, aiming_slot reseteado")
					return
				else:
					print("[Player] Otra tecla en aim mode, ignorando")
					return

			if _pending_selection_slot == slot:
				print("[Player] Menú abierto para este slot, cancelando selección.")
				var huds := get_tree().get_nodes_in_group(GroupNames.GAME_HUD)
				if not huds.is_empty():
					huds[0].cancel_selection()
				return

			mouse_dir = (get_global_mouse_position() - global_position).normalized()

			if multiplayer.is_server():
				print("[Player] Llamando Router.request_ability (servidor) | slot: ", slot)
				AbilityRouter.request_ability(slot, mouse_dir)
			else:
				print("[Player] Enviando RPC request_ability al servidor | slot: ", slot)
				AbilityRouter.rpc_id(1, "request_ability", slot, mouse_dir)
			ability_used.emit(slot)
			break

	if event.is_action_pressed("secret_ability"):
		if multiplayer.is_server():
			_activate_secret_heal()
		else:
			rpc_id(1, "_request_secret_heal")

	if event.is_action_pressed("interact"):
		_try_revive()

	if event.is_action_released("interact"):
		if multiplayer.is_server():
			GameServiceLocator.revive.cancel_revive(get_multiplayer_authority())
		else:
			rpc_id(1, "_request_cancel_revive")


# ── Selección contextual (server -> cliente) ──────────────────────────

@rpc("any_peer", "call_local", "reliable")
func _open_ability_selection(slot: int, title: String, selection_type: int = 0) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if not is_multiplayer_authority():
		return

	if multiplayer.is_server():
		_play_ability_prepare(slot)
	else:
		rpc_id(1, "_server_prepare_ability", slot)

	_pending_selection_slot = slot
	var huds := get_tree().get_nodes_in_group(GroupNames.GAME_HUD)
	if huds.is_empty():
		return
	var filter_peer_id: int = -1
	if selection_type == 0: # ALLY
		filter_peer_id = get_multiplayer_authority()

	var can_target_self: bool = false
	if character_data and slot >= 0 and slot < character_data.ability_slots.size():
		var ad: AbilityData = character_data.ability_slots[slot]
		if ad:
			can_target_self = ad.can_target_self

	huds[0].request_selection(
		title,
		func(target_peer_id: int) -> void:
			if _pending_selection_slot == slot:
				_pending_selection_slot = -1
				if multiplayer.is_server():
					AbilityRouter._dispatch_with_target(slot, target_peer_id, get_multiplayer_authority())
				else:
					rpc_id(1, "_confirm_ability_selection", slot, target_peer_id),
		func() -> void:
			if _pending_selection_slot == slot:
				_pending_selection_slot = -1
				if multiplayer.is_server():
					_cancel_ability_selection(slot)
				else:
					rpc_id(1, "_cancel_ability_selection", slot),
		filter_peer_id,
		can_target_self
	)


func _play_ability_prepare(slot: int) -> void:
	if not character_data or slot < 0 or slot >= character_data.ability_slots.size():
		return
	var ability_data: AbilityData = character_data.ability_slots[slot]
	if not ability_data:
		return

	if ability_data.prepare_animation != "" and ability_data.prepare_animation != null:
		GameServiceLocator.combat_mediator.apply_root(self, 30.0)
		play_prepare_animation(ability_data.prepare_animation, slot, facing_right)


@rpc("any_peer", "call_remote", "reliable")
func _confirm_ability_selection(slot: int, target_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	AbilityRouter._dispatch_with_target(slot, target_peer_id, get_multiplayer_authority())


@rpc("any_peer", "call_remote", "reliable")
func _server_prepare_ability(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	_play_ability_prepare(slot)


@rpc("any_peer", "call_remote", "reliable")
func _cancel_ability_selection(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return

	if state == AnimState.PREPARE and active_ability_slot == slot:
		GameServiceLocator.combat_mediator.remove_root(self)
		rpc("_sync_cancel_ability")

	print("[Ability] Selección cancelada: slot ", slot, " | peer: ", get_multiplayer_authority())


# ── Configuración de personaje ────────────────────────────────────────

func set_character(char_id: int) -> void:
	var data: CharacterData = CharacterRegistry.get_character(char_id)
	if not data: return

	character_data = data
	health         = data.max_health
	health_state   = "alive"
	if movement_component:
		movement_component.speed = data.speed

	add_to_group(data.team)
	if data.team == "killer":
		add_to_group(GroupNames.KILLER)
	add_to_group(GroupNames.PLAYERS)

	call_deferred("_apply_character_visuals_and_collision", data)


func _apply_character_visuals_and_collision(data: CharacterData) -> void:
	if $AnimatedSprite2D:
		$AnimatedSprite2D.sprite_frames = data.animation_frames
	_setup_collision_layers(data)


func _setup_collision_layers(data: CharacterData) -> void:
	if data.team == "killer":
		collision_layer = 4
		collision_mask  = 1
		hurtbox.collision_layer = 16
		hurtbox.collision_mask  = 0
	else:
		collision_layer = 2
		collision_mask  = 1
		hurtbox.collision_layer = 8
		hurtbox.collision_mask  = 0

	var ws := RectangleShape2D.new()
	ws.size = Vector2(data.size_x, data.size_y)
	world_c.shape = ws
	world_c.position = Vector2(data.position_x, data.position_y)

	var hs := CapsuleShape2D.new()
	hs.radius = data.h_size_x
	hs.height = data.h_size_y
	hurtbox_c.shape = hs
	hurtbox_c.position = Vector2(data.h_position_x, data.h_position_y)


# ── Movimiento delegado a PlayerMovementComponent ────────────────────


# ── Física (solo espectador) ─────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	if interaction.is_spectator:
		interaction.update_spectator_camera(_delta)


# ── Animación de habilidades ──────────────────────────────────────────

func _on_anim_finished() -> void:
	animation_component.on_anim_finished()


func _restore_idle() -> void:
	animation_component.restore_idle()


func _end_stun() -> void:
	animation_component.end_stun()


# ── Muerte definitiva ────────────────────────────────────────────────

func _disable_corpse() -> void:
	interaction.disable_corpse()


func _prepare_spectator_mode() -> void:
	interaction.prepare_spectator_mode()


func _handle_spectator_input(event: InputEvent) -> void:
	interaction.handle_spectator_input(event)


func _update_spectator_camera(_delta: float) -> void:
	interaction.update_spectator_camera(_delta)


func _get_corpse_container() -> Node:
	return interaction.get_corpse_container()


func play_ability_animation(anim_name: String, slot_index: int, facing_right_override: bool = true) -> void:
	if not multiplayer.is_server():
		return
	if anim_name == "":
		return

	animation_component.apply_ability_anim_state(anim_name, facing_right_override, slot_index, AnimState.ABILITY)

	for peer_id in multiplayer.get_peers():
		rpc_id(peer_id, "_sync_ability_anim", anim_name, facing_right_override, slot_index)


@rpc("any_peer", "reliable")
func _sync_ability_anim(anim_name: String, facing_right_override: bool, slot_index: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 1:
		return

	animation_component.apply_ability_anim_state(anim_name, facing_right_override, slot_index, AnimState.ABILITY)


func play_prepare_animation(anim_name: String, slot_index: int, facing_right_override: bool = true) -> void:
	if not multiplayer.is_server():
		return
	if anim_name == "":
		return

	animation_component.apply_ability_anim_state(anim_name, facing_right_override, slot_index, AnimState.PREPARE)

	for peer_id in multiplayer.get_peers():
		rpc_id(peer_id, "_sync_prepare_anim", anim_name, facing_right_override, slot_index)


@rpc("any_peer", "reliable")
func _sync_prepare_anim(anim_name: String, facing_right_override: bool, slot_index: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 1:
		return

	animation_component.apply_ability_anim_state(anim_name, facing_right_override, slot_index, AnimState.PREPARE)


func reset_ability_state() -> void:
	animation_component.reset_ability_state()


@rpc("any_peer", "call_local", "reliable")
func _sync_cancel_ability() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	reset_ability_state()


@rpc("any_peer", "unreliable")
func _sync_aim_dir(dir: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	if dir != Vector2.ZERO:
		_latest_aim_dir = dir


@rpc("any_peer", "call_remote", "reliable")
func _request_secret_heal() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	_activate_secret_heal()


func _activate_secret_heal() -> void:
	if not multiplayer.is_server():
		return
	if _secret_heal_used:
		return
	if health_state != "alive" or health <= 0:
		return
	if character_data and health >= character_data.max_health:
		return
	if state != AnimState.IDLE:
		return

	_secret_heal_used = true

	var data := preload("res://abilities/shared/SecretHeal.tres")
	if not data:
		return
	var handler := preload("res://abilities/shared/secret_heal.gd").new()
	handler.activate(self, data, Vector2.ZERO, -1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn_secret_visual(caster_peer_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return

	var survivor := PlayerRegistry.get_player(caster_peer_id) as Node2D
	if not survivor:
		return

	var frames := preload("res://abilities/shared/animations.tres")
	if not frames:
		return

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.play("spamton_angel")
	sprite.position = Vector2(0, -60.0)
	sprite.z_index = 10
	survivor.add_child(sprite)

	get_tree().create_timer(SECRET_HEAL_DURATION).timeout.connect(
		func():
			if is_instance_valid(sprite):
				sprite.queue_free()
	)


# ── Sincronización desde el servidor ──────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func _sync_health(new_health: int, invincibility_duration_ms: int) -> void:
	if health_state == "dead":
		return

	var old_health = health
	var _old_state = health_state

	health = new_health
	invincible_until = Time.get_ticks_msec() + invincibility_duration_ms
	if new_health < old_health:
		hurt_flash_until = Time.get_ticks_msec() + HURT_FLASH_DURATION_MS
		if is_multiplayer_authority():
			$Camera2D.shake(5.0, 0.2)
	elif new_health > old_health:
		heal_flash_until = Time.get_ticks_msec() + HEAL_FLASH_DURATION_MS

	var should_be_state = ""
	if health <= 0:
		should_be_state = "downed"
	else:
		should_be_state = "alive"

	if health_state != should_be_state and should_be_state != "":
		health_state = should_be_state
		if multiplayer.is_server():
			GameServiceLocator.health.player_state_changed.emit(get_multiplayer_authority(), health_state)
	else:
		print("[Client] Sync health: %d -> %d (state: %s, peer: %s)" % [old_health, health, health_state, name])

	if health_state == "downed":
		movement_component.speed = 0
		if animated_sprite and last_animation != "life_down":
			var anim := "life_down"
			if animated_sprite.sprite_frames and not animated_sprite.sprite_frames.has_animation(anim):
				anim = "idle_horizontal" if animated_sprite.sprite_frames.has_animation("idle_horizontal") else "default"
			animated_sprite.play(anim)
			last_animation = anim
	elif health_state == "dead":
		movement_component.speed = 0
		if animated_sprite and is_instance_valid(animated_sprite):
			var anim := "player_dead"
			if animated_sprite.sprite_frames and not animated_sprite.sprite_frames.has_animation(anim):
				anim = "idle_horizontal" if animated_sprite.sprite_frames.has_animation("idle_horizontal") else "default"
			animated_sprite.play(anim)
			last_animation = anim
		interaction.disable_corpse()
		interaction.prepare_spectator_mode()
	elif character_data and health_state == "alive":
		movement_component.speed = character_data.speed
		if animated_sprite and last_animation in ["player_dead", "life_down"]:
			animation_component.restore_idle()


@rpc("any_peer", "call_local", "reliable")
func _sync_speed(new_speed: float) -> void:
	movement_component.speed = new_speed


@rpc("authority", "call_local", "reliable")
func _sync_aiming_mode(slot: int, active: bool) -> void:
	aiming_slot = slot if active else -1


@rpc("any_peer", "call_local", "reliable")
func _sync_invincibility(duration_ms: int) -> void:
	invincible_until = Time.get_ticks_msec() + duration_ms


@rpc("any_peer", "call_local", "reliable")
func _sync_effect(effect_name: String, active: bool) -> void:
	if active:
		active_effects[effect_name] = true
		if effect_name == "stun":
			state = AnimState.STUNNED
			if animated_sprite.sprite_frames.has_animation("stun"):
				animated_sprite.play("stun")
			else:
				animated_sprite.play("idle_horizontal")
	else:
		active_effects.erase(effect_name)
		if effect_name == "stun" and state == AnimState.STUNNED:
			if animated_sprite.sprite_frames.has_animation("stun_end"):
				animated_sprite.play("stun_end")
			else:
				animation_component.end_stun()


@rpc("any_peer", "call_local", "reliable")
func _sync_state(new_state: String, new_health: int) -> void:
	health_state = new_state
	health = new_health

	match new_state:
		"alive":
			if character_data:
				movement_component.speed = character_data.speed
			animation_component.restore_idle()
		"downed":
			movement_component.speed = 0
			if animated_sprite:
				var anim := "life_down"
				if animated_sprite.sprite_frames and not animated_sprite.sprite_frames.has_animation(anim):
					anim = "idle_horizontal" if animated_sprite.sprite_frames.has_animation("idle_horizontal") else "default"
				animated_sprite.play(anim)
				last_animation = anim
		"dead":
			movement_component.speed = 0
			if animated_sprite and is_instance_valid(animated_sprite):
				var anim := "player_dead"
				if animated_sprite.sprite_frames and not animated_sprite.sprite_frames.has_animation(anim):
					anim = "idle_horizontal" if animated_sprite.sprite_frames.has_animation("idle_horizontal") else "default"
				animated_sprite.play(anim)
				last_animation = anim
				if synchronizer:
					synchronizer.queue_free()
				animated_sprite.reparent(interaction.get_corpse_container(), true)
				animated_sprite.z_index = 2
			interaction.disable_corpse()
			interaction.prepare_spectator_mode()
			if name_tag:
				name_tag.visible = false

	if multiplayer.is_server():
		GameServiceLocator.health.player_state_changed.emit(get_multiplayer_authority(), new_state)


@rpc("any_peer", "call_local", "reliable")
func _sync_escape() -> void:
	var caller = multiplayer.get_remote_sender_id()
	if caller != 0 and caller != 1:
		return
	health_state = "escaped"
	visible = false
	if name_tag:
		name_tag.visible = false
	interaction.disable_corpse()
	interaction.prepare_spectator_mode()
	if multiplayer.is_server():
		var coord = GameServiceLocator.map_event_coordinator
		if not coord.has_player_escaped(get_multiplayer_authority()):
			coord._register_escaped(get_multiplayer_authority())
		var hp_svc = GameServiceLocator.health
		if hp_svc and hp_svc.has_method("set_escaped"):
			hp_svc.set_escaped(get_multiplayer_authority(), health, character_data.max_health)


@rpc("any_peer", "reliable")
func _request_sprint(sprinting: bool) -> void:
	if not multiplayer.is_server():
		return
	GameServiceLocator.stamina.set_sprinting(get_multiplayer_authority(), sprinting)


@rpc("authority", "call_local", "reliable")
func _sync_forced_position(new_pos: Vector2, locked: bool) -> void:
	global_position = new_pos
	if locked:
		state = AnimState.ABILITY
		active_ability_slot = -1  # sin slot específico, solo bloqueo
	else:
		state = AnimState.IDLE


## El servidor fuerza una posición en el cliente (usado por habilidades como Teleport).
@rpc("any_peer", "call_local", "reliable")
func _sync_server_position(pos: Vector2) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	global_position = pos


@rpc("any_peer", "call_local", "reliable")
func _sync_show_aoe_indicator(center: Vector2) -> void:
	var world = get_tree().root.find_child("World", true, false)
	if not world:
		return
	var existing = world.find_child("DiamondRainAOE_local", true, false)
	if existing:
		existing.queue_free()
	var indicator = Node2D.new()
	indicator.name = "DiamondRainAOE_local"
	indicator.global_position = center
	indicator.set_script(preload("res://abilities/jevil/scripts/AoEIndicator.gd"))
	world.add_child(indicator)


@rpc("any_peer", "call_local", "reliable")
func _sync_hide_aoe_indicator() -> void:
	var world = get_tree().root.find_child("World", true, false)
	if not world:
		return
	var existing = world.find_child("DiamondRainAOE_local", true, false)
	if existing:
		existing.queue_free()


@rpc("any_peer", "call_local", "reliable")
func _sync_show_pacify_indicator(center: Vector2, area_radius: float) -> void:
	var world = get_tree().root.find_child("World", true, false)
	if not world:
		return
	var existing = world.find_child("PacifyAOE_local", true, false)
	if existing:
		existing.queue_free()
	var indicator = Node2D.new()
	indicator.name = "PacifyAOE_local"
	indicator.global_position = center
	indicator.set_script(preload("res://abilities/jevil/scripts/AoEIndicator.gd"))
	indicator.radius = area_radius
	indicator.color = Color(0.3, 0.5, 1.0)
	world.add_child(indicator)


@rpc("any_peer", "call_local", "reliable")
func _sync_hide_pacify_indicator() -> void:
	var world = get_tree().root.find_child("World", true, false)
	if not world:
		return
	var existing = world.find_child("PacifyAOE_local", true, false)
	if existing:
		existing.queue_free()


const SECRET_HEAL_DURATION: float = 1.5
