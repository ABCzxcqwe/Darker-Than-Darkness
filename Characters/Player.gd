# res://characters/Player.gd
extends CharacterBody2D

signal ability_used(ability_index: int)

enum AnimState { IDLE, PREPARE, ABILITY }

@export var speed = 200
@onready var synchronizer      = $Synchronizer
@onready var animated_sprite   = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var world_c           = $CollisionShape2D
@onready var hurtbox_c         = $Hurtbox/CollisionShape2D

var character_data:   CharacterData
var health:           int    = 0
var health_state:     String = "alive"
var last_animation:   String = "idle_horizontal"
var facing_right:     bool   = true
var invincible_until: int    = 0

var facing: Vector2 = Vector2.RIGHT

var active_effects: Dictionary = {}
var state: int       = AnimState.IDLE
var active_ability_slot: int = -1
var _pending_selection_slot: int = -1
var aiming_slot: int = -1
var _is_sprinting: bool = false
var is_spectator: bool = false


func _ready() -> void:
	print("[Player] _ready() | nombre: ", name, " | autoridad: ", is_multiplayer_authority())

	if not synchronizer:
		push_error("[Player] No se encontró 'Synchronizer'. Revisa player.tscn")

	if character_data:
		add_to_group(character_data.team)
		if character_data.team == "killer":
			add_to_group("killer")

	add_to_group("players")

	if not is_multiplayer_authority():
		if $Camera2D:
			$Camera2D.enabled = false
	else:
		var listener = AudioListener2D.new()
		add_child(listener)
		listener.make_current()

	if multiplayer.is_server():
		var hs = GameServiceLocator.get_service("HealthService")
		if hs:
			if hs.has_method("register"):
				hs.register(self)
			elif hs.has_method("register_survivor"):
				hs.call("register_survivor", self)
		var ss = GameServiceLocator.get_service("StatusEffectService")
		if ss: ss.register(self)
		var es = GameServiceLocator.get_service("EvolutionService")
		if es: es.register_player(get_multiplayer_authority())
		var abs_svc = GameServiceLocator.get_service("AbilityStateService")
		if abs_svc:
			abs_svc.register_player(get_multiplayer_authority(), character_data)
		var stam_svc = GameServiceLocator.get_service("StaminaService")
		if stam_svc:
			stam_svc.register_player(get_multiplayer_authority(), character_data)

	if animated_sprite and animated_sprite.animation_finished.is_connected(_on_anim_finished) == false:
		animated_sprite.animation_finished.connect(_on_anim_finished)


# ── Rescate ───────────────────────────────────────────────────────────

func _try_revive() -> void:
	var my_data := character_data
	var _range: float = my_data.revive_range if my_data else 80.0

	var closest_target: Node = null
	var closest_dist:   float = _range + 1.0

	for player in get_tree().get_nodes_in_group("players"):
		if player == self: continue
		if not player.is_in_group("survivor"): continue
		if player.health_state != "downed": continue

		var dist := global_position.distance_to(player.global_position)
		if dist < closest_dist:
			closest_dist   = dist
			closest_target = player

	if not closest_target: return

	if multiplayer.is_server():
		var revive_svc = GameServiceLocator.get_service("ReviveService")
		if revive_svc: revive_svc.request_revive(self, closest_target)
	else:
		rpc_id(1, "_request_revive", closest_target.get_multiplayer_authority())


@rpc("any_peer", "reliable")
func _request_revive(target_peer_id: int) -> void:
	var caller_id := multiplayer.get_remote_sender_id()
	if caller_id != get_multiplayer_authority(): return

	var rescuer_node := _get_self_on_server()
	var target_node  := get_tree().root.find_child(str(target_peer_id), true, false)
	if not rescuer_node or not target_node: return

	var revive_svc = GameServiceLocator.get_service("ReviveService")
	if revive_svc: revive_svc.request_revive(rescuer_node, target_node)


@rpc("any_peer", "reliable")
func _request_cancel_revive() -> void:
	var caller_id := multiplayer.get_remote_sender_id()
	if caller_id != get_multiplayer_authority(): return
	var revive_svc = GameServiceLocator.get_service("ReviveService")
	if revive_svc:
		revive_svc.cancel_revive(get_multiplayer_authority())


func _get_self_on_server() -> Node:
	return get_tree().root.find_child(str(get_multiplayer_authority()), true, false)


func _exit_tree() -> void:
	var peer_id : int = -1
	if multiplayer.multiplayer_peer != null:
		peer_id = get_multiplayer_authority()

	var hs = GameServiceLocator.get_service("HealthService")
	if hs and peer_id != -1: hs.unregister(peer_id)
	var ss = GameServiceLocator.get_service("StatusEffectService")
	if ss: ss.unregister(self)
	var tp = GameServiceLocator.get_service("TPService")
	if tp and peer_id != -1: tp.unregister_player(peer_id)
	var es = GameServiceLocator.get_service("EvolutionService")
	if es and peer_id != -1: es.unregister_player(peer_id)
	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if abs_svc and peer_id != -1: abs_svc.unregister_player(peer_id)
	var stam_svc = GameServiceLocator.get_service("StaminaService")
	if stam_svc and peer_id != -1: stam_svc.unregister_player(peer_id)
	var cd = GameServiceLocator.get_service("CooldownService")
	if cd and peer_id != -1 and cd.has_method("clear_player"):
		cd.clear_player(peer_id)


# ── Input ─────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return
	if health_state != "alive": return

	var action_map = {
		"ability_1": 1,
		"ability_2": 2,
		"ability_3": 3,
		"ability_4": 4,
		"ability_0": 0,
	}

	if event.is_action_pressed("confirm") and aiming_slot >= 0:
		print("[Player] Confirmando habilidad de apuntado | slot: ", aiming_slot)
		var mouse_dir = (get_global_mouse_position() - global_position).normalized()
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

			if _pending_selection_slot == slot:
				print("[Player] Menú abierto para este slot, cancelando selección.")
				var huds := get_tree().get_nodes_in_group("game_hud")
				if not huds.is_empty():
					huds[0].cancel_selection()
				return

			var mouse_dir = (get_global_mouse_position() - global_position).normalized()

			if multiplayer.is_server():
				print("[Player] Llamando Router.request_ability (servidor) | slot: ", slot)
				AbilityRouter.request_ability(slot, mouse_dir)
			else:
				print("[Player] Enviando RPC request_ability al servidor | slot: ", slot)
				AbilityRouter.rpc_id(1, "request_ability", slot, mouse_dir)
			ability_used.emit(slot)
			break

	if event.is_action_pressed("interact"):
		_try_revive()

	if event.is_action_released("interact"):
		if multiplayer.is_server():
			var revive_svc = GameServiceLocator.get_service("ReviveService")
			if revive_svc: revive_svc.cancel_revive(get_multiplayer_authority())
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
	var huds := get_tree().get_nodes_in_group("game_hud")
	if huds.is_empty():
		return
	var filter_peer_id: int = -1
	if selection_type == 0: # ALLY
		filter_peer_id = get_multiplayer_authority()
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
		filter_peer_id
	)


func _play_ability_prepare(slot: int) -> void:
	if not character_data or slot < 0 or slot >= character_data.ability_slots.size():
		return
	var ability_data: AbilityData = character_data.ability_slots[slot]
	if not ability_data:
		return

	if ability_data.prepare_animation != "" and ability_data.prepare_animation != null:
		var combat = GameServiceLocator.get_service("CombatMediator")
		if combat:
			combat.apply_root(self, 30.0)
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
		var combat = GameServiceLocator.get_service("CombatMediator")
		if combat:
			combat.remove_root(self)
		rpc("_sync_cancel_ability")

	print("[Ability] Selección cancelada: slot ", slot, " | peer: ", get_multiplayer_authority())


# ── Configuración de personaje ────────────────────────────────────────

func set_character(char_id: int) -> void:
	var data: CharacterData = CharacterRegistry.get_character(char_id)
	if not data: return

	character_data = data
	health         = data.max_health
	health_state   = "alive"
	speed          = data.speed

	add_to_group(data.team)
	if data.team == "killer":
		add_to_group("killer")
	add_to_group("players")

	call_deferred("_apply_character_visuals_and_collision", data)


func _apply_character_visuals_and_collision(data: CharacterData) -> void:
	if $AnimatedSprite2D:
		$AnimatedSprite2D.sprite_frames = data.animation_frames
	_setup_collision_layers(data)

	if multiplayer.is_server():
		var tp = GameServiceLocator.get_service("TPService")
		if tp: tp.register_player(get_multiplayer_authority(), data)


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


# ── Física y movimiento ──────────────────────────────────────────────

func _physics_process(_delta: float) -> void:
	if not multiplayer.multiplayer_peer: return
	if not is_multiplayer_authority(): return
	if health_state == "dead": return

	if state == AnimState.IDLE or active_effects.has("free_look"):
		var mouse_dir = (get_global_mouse_position() - global_position).normalized()
		update_facing_and_flip(mouse_dir)

	if state == AnimState.IDLE:
		var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")

		var want_sprint = Input.is_key_pressed(KEY_SHIFT) and input_dir.length() > 0.1
		var can_sprint = false
		var stam_svc = GameServiceLocator.get_service("StaminaService")
		if stam_svc:
			can_sprint = want_sprint and stam_svc.has_stamina(get_multiplayer_authority())
		else:
			can_sprint = want_sprint

		if stam_svc and can_sprint != _is_sprinting:
			_is_sprinting = can_sprint
			if multiplayer.is_server():
				stam_svc.set_sprinting(get_multiplayer_authority(), can_sprint)
			else:
				stam_svc.rpc_id(1, "set_sprinting", get_multiplayer_authority(), can_sprint)

		var sprint_mult = 1.5 if can_sprint else 1.0
		velocity = input_dir * speed * sprint_mult
		move_and_slide()

		if health_state == "alive":
			var is_moving = velocity.length() > 0.1
			var anim_name = "walk_horizontal" if is_moving else "idle_horizontal"
			if last_animation != anim_name:
				animated_sprite.play(anim_name)
				last_animation = anim_name
			animated_sprite.speed_scale = 1.5 if _is_sprinting and is_moving else 1.0
	else:
		velocity = Vector2.ZERO


func update_facing_and_flip(dir: Vector2) -> void:
	if abs(dir.x) > 0.1:
		facing_right = dir.x > 0
		animated_sprite.flip_h = not facing_right
		facing = Vector2.RIGHT if facing_right else Vector2.LEFT


# ── Animación de habilidades ──────────────────────────────────────────

func _on_anim_finished() -> void:
	if state == AnimState.ABILITY or state == AnimState.PREPARE:
		state = AnimState.IDLE
		active_ability_slot = -1
		_restore_idle()


func _restore_idle() -> void:
	if health_state != "alive":
		return
	animated_sprite.flip_h = not facing_right
	animated_sprite.play("idle_horizontal")
	last_animation = "idle_horizontal"


# ── Muerte definitiva ────────────────────────────────────────────────

func _disable_corpse() -> void:
	set_physics_process(false)
	set_process_input(false)
	print("[Player] _disable_corpse: lógica no-física ejecutada.")

	if not _disable_collisions():
		push_error("[Player] _disable_corpse: fallo al desactivar colisiones.")


func _disable_collisions() -> bool:
	var success := true
	if not is_inside_tree():
		push_error("[Player] _disable_collisions: nodo no en el árbol.")
		return false

	if has_node("CollisionShape2D"):
		var world_shape = $CollisionShape2D
		if world_shape.has_method("set_deferred"):
			world_shape.set_deferred("disabled", true)
			print("[Player] _disable_collisions: CollisionShape2D desactivado (deferred).")
		else:
			push_error("[Player] _disable_collisions: CollisionShape2D no soporta set_deferred.")
			success = false
	else:
		push_error("[Player] _disable_collisions: CollisionShape2D no encontrado.")
		success = false

	if has_node("Hurtbox/CollisionShape2D"):
		var hurtbox_shape = $Hurtbox/CollisionShape2D
		if hurtbox_shape.has_method("set_deferred"):
			hurtbox_shape.set_deferred("disabled", true)
			print("[Player] _disable_collisions: Hurtbox/CollisionShape2D desactivado (deferred).")
		else:
			push_error("[Player] _disable_collisions: Hurtbox/CollisionShape2D no soporta set_deferred.")
			success = false
	else:
		push_error("[Player] _disable_collisions: Hurtbox/CollisionShape2D no encontrado.")
		success = false

	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	print("[Player] _disable_collisions: collision_layer/mask puestos en 0 (deferred).")

	return success


func _prepare_spectator_mode() -> void:
	is_spectator = true
	if is_multiplayer_authority():
		pass
		# TODO: liberar cámara para modo espectador,
		#       seguir a otro jugador, UI de espectador, etc.


func _get_corpse_container() -> Node:
	var parent = get_parent()
	if not parent:
		parent = get_tree().current_scene
	if not parent:
		return get_tree().root
	var container := parent.find_child("CorpseContainer", true, false)
	if not container:
		container = Node2D.new()
		container.name = "CorpseContainer"
		parent.add_child(container)
	return container


func play_ability_animation(anim_name: String, slot_index: int, facing_right_override: bool = true) -> void:
	if not multiplayer.is_server():
		return
	if anim_name == "":
		return

	facing_right = facing_right_override
	facing = Vector2.RIGHT if facing_right else Vector2.LEFT
	animated_sprite.flip_h = not facing_right
	animated_sprite.play(anim_name)
	state = AnimState.ABILITY
	active_ability_slot = slot_index

	for peer_id in multiplayer.get_peers():
		rpc_id(peer_id, "_sync_ability_anim", anim_name, facing_right_override, slot_index)


@rpc("any_peer", "reliable")
func _sync_ability_anim(anim_name: String, facing_right_override: bool, slot_index: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 1:
		return
	if anim_name == "":
		return

	facing_right = facing_right_override
	facing = Vector2.RIGHT if facing_right else Vector2.LEFT
	animated_sprite.flip_h = not facing_right
	animated_sprite.play(anim_name)
	state = AnimState.ABILITY
	active_ability_slot = slot_index


func play_prepare_animation(anim_name: String, slot_index: int, facing_right_override: bool = true) -> void:
	if not multiplayer.is_server():
		return
	if anim_name == "":
		return

	facing_right = facing_right_override
	facing = Vector2.RIGHT if facing_right else Vector2.LEFT
	animated_sprite.flip_h = not facing_right
	animated_sprite.play(anim_name)
	state = AnimState.PREPARE
	active_ability_slot = slot_index

	for peer_id in multiplayer.get_peers():
		rpc_id(peer_id, "_sync_prepare_anim", anim_name, facing_right_override, slot_index)


@rpc("any_peer", "reliable")
func _sync_prepare_anim(anim_name: String, facing_right_override: bool, slot_index: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 1:
		return
	if anim_name == "":
		return

	facing_right = facing_right_override
	facing = Vector2.RIGHT if facing_right else Vector2.LEFT
	animated_sprite.flip_h = not facing_right
	animated_sprite.play(anim_name)
	state = AnimState.PREPARE
	active_ability_slot = slot_index


func reset_ability_state() -> void:
	state = AnimState.IDLE
	active_ability_slot = -1
	_restore_idle()


@rpc("any_peer", "call_local", "reliable")
func _sync_cancel_ability() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	reset_ability_state()


# ── Sincronización desde el servidor ──────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func _sync_health(new_health: int, new_invincible_until: int) -> void:
	var old_health = health
	var _old_state = health_state

	health = new_health
	invincible_until = new_invincible_until

	var should_be_state = ""
	if health <= 0:
		should_be_state = "downed"
	else:
		should_be_state = "alive"

	if health_state != should_be_state and should_be_state != "":
		health_state = should_be_state
		var hs = GameServiceLocator.get_service("HealthService")
		if hs and hs.has_method("get_player_state"):
			hs.player_state_changed.emit(get_multiplayer_authority(), health_state)
	else:
		print("[Client] Sync health: %d -> %d (state: %s, peer: %s)" % [old_health, health, health_state, name])

	if health_state == "downed":
		speed = 0
		if animated_sprite and last_animation != "life_down":
			var anim := "life_down"
			if animated_sprite.sprite_frames and not animated_sprite.sprite_frames.has_animation(anim):
				anim = "idle_horizontal" if animated_sprite.sprite_frames.has_animation("idle_horizontal") else "default"
			animated_sprite.play(anim)
			last_animation = anim
	elif health_state == "dead":
		speed = 0
		if animated_sprite and is_instance_valid(animated_sprite):
			var anim := "player_dead"
			if animated_sprite.sprite_frames and not animated_sprite.sprite_frames.has_animation(anim):
				anim = "idle_horizontal" if animated_sprite.sprite_frames.has_animation("idle_horizontal") else "default"
			animated_sprite.play(anim)
			last_animation = anim
		_disable_corpse()
		_prepare_spectator_mode()
	elif character_data and health_state == "alive":
		speed = character_data.speed
		if animated_sprite and last_animation in ["player_dead", "life_down"]:
			_restore_idle()


@rpc("any_peer", "call_local", "reliable")
func _sync_speed(new_speed: float) -> void:
	speed = new_speed


@rpc("authority", "call_local", "reliable")
func _sync_aiming_mode(slot: int, active: bool) -> void:
	aiming_slot = slot if active else -1


@rpc("any_peer", "call_local", "reliable")
func _sync_effect(effect_name: String, active: bool) -> void:
	if active:
		active_effects[effect_name] = true
	else:
		active_effects.erase(effect_name)


@rpc("any_peer", "call_local", "reliable")
func _sync_state(new_state: String, new_health: int) -> void:
	health_state = new_state
	health = new_health

	match new_state:
		"alive":
			if character_data:
				speed = character_data.speed
			_restore_idle()
		"downed":
			speed = 0
			if animated_sprite:
				var anim := "life_down"
				if animated_sprite.sprite_frames and not animated_sprite.sprite_frames.has_animation(anim):
					anim = "idle_horizontal" if animated_sprite.sprite_frames.has_animation("idle_horizontal") else "default"
				animated_sprite.play(anim)
				last_animation = anim
		"dead":
			speed = 0
			if animated_sprite and is_instance_valid(animated_sprite):
				var anim := "player_dead"
				if animated_sprite.sprite_frames and not animated_sprite.sprite_frames.has_animation(anim):
					anim = "idle_horizontal" if animated_sprite.sprite_frames.has_animation("idle_horizontal") else "default"
				animated_sprite.play(anim)
				last_animation = anim
				animated_sprite.reparent(_get_corpse_container(), true)
			animated_sprite.z_index = 1
			_disable_corpse()
			_prepare_spectator_mode()

	var hs = GameServiceLocator.get_service("HealthService")
	if hs:
		hs.player_state_changed.emit(get_multiplayer_authority(), new_state)


@rpc("any_peer", "call_local", "reliable")
func _sync_escape() -> void:
	var caller = multiplayer.get_remote_sender_id()
	if caller != 0 and caller != 1:
		return
	visible = false
	_disable_corpse()
	_prepare_spectator_mode()
	var coord = GameServiceLocator.get_service("MapEventCoordinator")
	if coord and not coord.has_player_escaped(get_multiplayer_authority()):
		if coord.has_method("_register_escaped"):
			coord._register_escaped(get_multiplayer_authority())
	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud and hud.has_method("_remove_name_label"):
		hud._remove_name_label(get_multiplayer_authority())
	var hs = GameServiceLocator.get_service("HealthService")
	if hs:
		hs.player_state_changed.emit(get_multiplayer_authority(), "escaped")


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
