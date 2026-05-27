# res://characters/Player.gd
extends CharacterBody2D

signal ability_used(ability_index: int)

enum AnimState { IDLE, ABILITY }

@export var speed = 200
@onready var synchronizer      = $Synchronizer
@onready var animated_sprite   = $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox
@onready var world_c           = $CollisionShape2D
@onready var hurtbox_c         = $Hurtbox/CollisionShape2D

var character_data:   CharacterData
var health:           int    = 0
var health_state:     String = "alive"
var last_animation:   String = "idle_down"
var facing_right:     bool   = true
var invincible_until: int    = 0

var facing: Vector2 = Vector2.RIGHT

var active_effects: Dictionary = {}
var state: int = AnimState.IDLE


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
	var abs_svc = GameServiceLocator.get_service("AbilityStateService") # <- NUEVO
	if abs_svc and peer_id != -1: abs_svc.unregister_player(peer_id)   # <- NUEVO



func cancel_current_ability(slot: int) -> void:
	if multiplayer.is_server():
		AbilityRouter.request_cancel_ability(slot)
	else:
		AbilityRouter.rpc_id(1, "request_cancel_ability", slot)


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
	
	for action in action_map:
		if event.is_action_pressed(action):
			var slot: int = action_map[action]
			
			var base_data = character_data.ability_slots[slot] if (character_data and slot < character_data.ability_slots.size()) else null

			if state == AnimState.ABILITY and base_data and base_data.can_cancel:
				cancel_current_ability(slot)
				return

			if not base_data:
				return

			if base_data.requires_selection:
				var hud_nodes = get_tree().get_nodes_in_group("game_hud")
				if not hud_nodes.is_empty():
					var hud = hud_nodes[0]
					var menu_title = "SELECCIONA: " + base_data.display_name.to_upper()
					hud.request_selection(
						menu_title,
						func(target_peer_id: int):
							var part_high = int(target_peer_id / 65536)
							var part_low = int(target_peer_id % 65536)
							var specialized_vector = Vector2(part_high, part_low)
							if multiplayer.is_server():
								AbilityRouter.request_ability(slot, specialized_vector)
							else:
								AbilityRouter.rpc_id(1, "request_ability", slot, specialized_vector)
							ability_used.emit(slot),
						func():
							print("[Player-Client] Selección cancelada.")
					)
				else:
					push_warning("[Player] No se encontró 'game_hud' para selección.")
				return
			
			var mouse_dir = (get_global_mouse_position() - global_position).normalized()
			if multiplayer.is_server():
				AbilityRouter.request_ability(slot, mouse_dir)
			else:
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

	# Separar lo que necesita el árbol listo
	call_deferred("_apply_character_visuals_and_collision", data)


func _apply_character_visuals_and_collision(data: CharacterData) -> void:
	if $AnimatedSprite2D:
		$AnimatedSprite2D.sprite_frames = data.animation_frames
	_setup_collision_layers(data)

	if multiplayer.is_server():
		var tp = GameServiceLocator.get_service("TPService")
		if tp: tp.register_player(get_multiplayer_authority(), data)


func _setup_collision_layers(data: CharacterData) -> void:
	print("[Collision] peer=%s | char=%s | size=(%s,%s)" % [
		get_multiplayer_authority(), 
		data.resource_name, 
		data.size_x, 
		data.size_y
	])
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
	print("[Shape] peer=%s | world_c.shape.get_rid()=%s | size=%s" % [
		get_multiplayer_authority(),
		world_c.shape.get_rid(),
		world_c.shape.size
	]) 

func _physics_process(_delta: float) -> void:
	if not multiplayer.multiplayer_peer: return
	if not is_multiplayer_authority(): return
	if health_state == "dead": return

	if state == AnimState.IDLE:
		var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		velocity = input_dir * speed
		move_and_slide()

		var dir_to_mouse = (get_global_mouse_position() - global_position).normalized()
		update_animation_and_flip(dir_to_mouse, velocity.length() > 0.1)
	else:
		velocity = Vector2.ZERO


func update_animation_and_flip(dir: Vector2, is_moving: bool) -> void:
	var prefix    := "walk" if is_moving else "idle"
	var anim_name := prefix + "_down"
	facing_right  = true

	if abs(dir.y) > abs(dir.x):
		anim_name = prefix + ("_down" if dir.y > 0 else "_up")
		facing    = Vector2.DOWN if dir.y > 0 else Vector2.UP
	else:
		anim_name    = prefix + "_horizontal"
		facing_right = dir.x > 0
		facing       = Vector2.RIGHT if facing_right else Vector2.LEFT
		animated_sprite.flip_h = not facing_right

	if last_animation != anim_name:
		animated_sprite.play(anim_name)
		last_animation = anim_name


# ── FSM de Animaciones ────────────────────────────────────────────────

func _on_anim_finished() -> void:
	if state == AnimState.ABILITY:
		state = AnimState.IDLE
		if animated_sprite:
			_play_idle_for_facing()


func _play_idle_for_facing() -> void:
	var idle_anim: String = "idle_down"
	if facing == Vector2.UP:
		idle_anim = "idle_up"
	elif facing == Vector2.LEFT or facing == Vector2.RIGHT:
		idle_anim = "idle_horizontal"
		animated_sprite.flip_h = facing == Vector2.LEFT
	if last_animation != idle_anim:
		animated_sprite.play(idle_anim)
		last_animation = idle_anim


func play_ability_animation(anim_name: String) -> void:
	if multiplayer.is_server():
		rpc("_sync_ability_anim", anim_name)


@rpc("authority", "call_local", "reliable")
func _sync_ability_anim(anim_name: String) -> void:
	if anim_name != "":
		animated_sprite.play(anim_name)
		state = AnimState.ABILITY


func reset_ability_state() -> void:
	state = AnimState.IDLE


@rpc("authority", "call_local", "reliable")
func _sync_cancel_ability() -> void:
	reset_ability_state()


# ── Sincronización desde el servidor ──────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func _sync_health(new_health: int, new_invincible_until: int) -> void:
	var old_health = health
	var _old_state = health_state
	
	health = new_health
	invincible_until = new_invincible_until
	
	# Auto-corregir estado inconsistente basado en la vida
	var should_be_state = ""
	if health <= 0:
		should_be_state = "downed"
	else:
		should_be_state = "alive"
	
	# Si el estado actual no coincide con la vida, corregirlo
	if health_state != should_be_state and should_be_state != "":
		print("[Client] Auto-corrigiendo estado: %s -> %s (health: %d, peer: %s)" % [health_state, should_be_state, health, name])
		health_state = should_be_state
		
		# Emitir señal local para actualizar UI
		var hs = GameServiceLocator.get_service("HealthService")
		if hs and hs.has_method("get_player_state"):
			hs.player_state_changed.emit(get_multiplayer_authority(), health_state)
	else:
		print("[Client] Sync health: %d -> %d (state: %s, peer: %s)" % [old_health, health, health_state, name])
	
	# Si estamos en downed, deshabilitar velocidad
	if health_state == "downed" or health_state == "dead":
		speed = 0
	elif character_data and health_state == "alive":
		speed = character_data.speed


@rpc("any_peer", "call_local", "reliable")
func _sync_speed(new_speed: float) -> void:
	speed = new_speed


@rpc("any_peer", "call_local", "reliable")
func _sync_effect(effect_name: String, active: bool) -> void:
	if active:
		active_effects[effect_name] = true
	else:
		active_effects.erase(effect_name)


@rpc("any_peer", "call_local", "reliable")
func _sync_state(new_state: String, new_health: int) -> void:
	var old_state = health_state
	var old_health = health
	
	print("[Client] Sync state: %s -> %s (health: %d -> %d, peer: %s)" % [old_state, new_state, old_health, new_health, name])
	
	health_state = new_state
	health = new_health  
	
	match new_state:
		"alive":
			if character_data: 
				speed = character_data.speed
			print("[Client] Player %s revivido con %d HP" % [name, health])
		"downed":
			speed = 0
			print("[Client] Player %s está en estado DOWNED con %d HP" % [name, health])
		"dead":
			speed = 0
			print("[Client] Player %s está MUERTO" % name)
	
	# Notificar al HealthService local sobre el cambio de estado
	var hs = GameServiceLocator.get_service("HealthService")
	if hs:
		hs.player_state_changed.emit(get_multiplayer_authority(), new_state)
