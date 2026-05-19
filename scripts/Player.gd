# res://scripts/Player.gd
extends CharacterBody2D

## Emitida cuando el jugador local usa una habilidad (para actualizar UI)
signal ability_used(ability_index: int)

@export var speed = 200
@onready var synchronizer      := $Synchronizer
@onready var animated_sprite   := $AnimatedSprite2D
@onready var hurtbox: Area2D = $Hurtbox

var character_data:   CharacterData
var health:           int    = 0
var health_state:     String = "alive"   # "alive", "downed", "dead"
var last_animation:   String = "idle_down"
var facing_right:     bool   = true
var invincible_until: int    = 0

# Dirección de orientación actual — usada por HitboxService para aim_mode "facing"
var facing: Vector2 = Vector2.RIGHT


func _ready() -> void:
	print("[Player] _ready() | nombre: ", name, " | autoridad: ", is_multiplayer_authority())

	if not synchronizer:
		push_error("[Player] No se encontró 'Synchronizer'. Revisa player.tscn")

	if not is_multiplayer_authority():
		if $Camera2D:
			$Camera2D.enabled = false
	else:
		# ── AQUÍ SE INYECTA EL OÍDO LOCAL ──
		var listener := AudioListener2D.new()
		add_child(listener)
		listener.make_current()
		
		# Esperamos un frame para garantizar que character_data ya fue inyectado por el Spawner
		await get_tree().process_frame
		_initialize_local_audio_streams()

	# Registrar en servicios al entrar a la partida
	if multiplayer.is_server():
		var hs := GameServiceLocator.get_service("HealthService")
		if hs:
			hs.register(self)
		var ss := GameServiceLocator.get_service("StatusEffectService")
		if ss:
			ss.register(self)
		var es := GameServiceLocator.get_service("EvolutionService")
		if es:
			es.register_player(get_multiplayer_authority())


# ── Rescate ───────────────────────────────────────────────────────────

func _try_revive() -> void:
	# Buscar survivor caído en rango
	var my_data := character_data
	var _range: float = my_data.revive_range if my_data else 80.0

	var closest_target: Node = null
	var closest_dist:   float = _range + 1.0

	for player in get_tree().get_nodes_in_group("players"):
		if player == self:
			continue
		if not player.is_in_group("survivor"):
			continue
		if player.health_state != "downed":
			continue
		var dist := global_position.distance_to(player.global_position)
		if dist < closest_dist:
			closest_dist   = dist
			closest_target = player

	if not closest_target:
		return

	if multiplayer.is_server():
		var revive_svc := GameServiceLocator.get_service("ReviveService")
		if revive_svc:
			revive_svc.request_revive(self, closest_target)
	else:
		rpc_id(1, "_request_revive", closest_target.get_multiplayer_authority())


@rpc("any_peer", "reliable")
func _request_revive(target_peer_id: int) -> void:
	# Validar que el que llama es este mismo jugador
	var caller_id := multiplayer.get_remote_sender_id()
	if caller_id != get_multiplayer_authority():
		return

	var rescuer_node := _get_self_on_server()
	var target_node  := get_tree().root.find_child(str(target_peer_id), true, false)
	if not rescuer_node or not target_node:
		return

	var revive_svc := GameServiceLocator.get_service("ReviveService")
	if revive_svc:
		revive_svc.request_revive(rescuer_node, target_node)


@rpc("any_peer", "reliable")
func _request_cancel_revive() -> void:
	var caller_id := multiplayer.get_remote_sender_id()
	if caller_id != get_multiplayer_authority():
		return
	var revive_svc := GameServiceLocator.get_service("ReviveService")
	if revive_svc:
		revive_svc.cancel_revive(get_multiplayer_authority())


func _get_self_on_server() -> Node:
	return get_tree().root.find_child(str(get_multiplayer_authority()), true, false)


func _exit_tree() -> void:
	if multiplayer.is_server():
		var peer_id := get_multiplayer_authority()
		var hs := GameServiceLocator.get_service("HealthService")
		if hs:
			hs.unregister(peer_id)
		var ss := GameServiceLocator.get_service("StatusEffectService")
		if ss:
			ss.unregister(self)
		var tp := GameServiceLocator.get_service("TPService")
		if tp:
			tp.unregister_player(peer_id)
		var es := GameServiceLocator.get_service("EvolutionService")
		if es:
			es.unregister_player(peer_id)


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Bloquear habilidades si está caído o muerto
	if health_state != "alive":
		return

	# ── Habilidades (slots 0-4) ───────────────────────────────────────
	var action_map := {
		"ability_1": 1,
		"ability_2": 2,
		"ability_3": 3,
		"ability_4": 4,
		"ability_0": 0,
	}
	for action in action_map:
		if event.is_action_pressed(action):
			var slot: int = action_map[action]
			var mouse_dir := (get_global_mouse_position() - global_position).normalized()
			if multiplayer.is_server():
				AbilityRouter.request_ability(slot, mouse_dir)
			else:
				AbilityRouter.rpc_id(1, "request_ability", slot, mouse_dir)
			ability_used.emit(slot)
			break


	# ── Rescate ───────────────────────────────────────────────────────
	if event.is_action_pressed("interact"):
		_try_revive()

	if event.is_action_released("interact"):
		# Cancelar rescate si se suelta la tecla
		if multiplayer.is_server():
			var revive_svc := GameServiceLocator.get_service("ReviveService")
			if revive_svc:
				revive_svc.cancel_revive(get_multiplayer_authority())
		else:
			rpc_id(1, "_request_cancel_revive")


func set_character(char_id: int) -> void:
	var data: CharacterData = CharacterRegistry.get_character(char_id)
	if not data:
		push_error("[Player] No se encontró CharacterData para ID ", char_id)
		return

	if $AnimatedSprite2D:
		$AnimatedSprite2D.sprite_frames = data.animation_frames
	else:
		push_error("[Player] No hay nodo AnimatedSprite2D")

	speed          = data.speed
	character_data = data
	health         = data.max_health
	health_state   = "alive"
	add_to_group(data.team)
	add_to_group("players")
	
	# ── ADICIÓN TÁCTICA PARA EL AUDIO ──
	# Añadir al Killer al grupo para que sea rastreable, y refrescar streams en el AudioManager
	if data.team == "killer":
		add_to_group("killers")
	
	_setup_collision_layers(data)

	# Registrar TP ahora que tenemos el CharacterData
	if multiplayer.is_server():
		var tp := GameServiceLocator.get_service("TPService")
		if tp:
			tp.register_player(get_multiplayer_authority(), data)


func _setup_collision_layers(data: CharacterData) -> void:
	# Usar la variable @onready en lugar de get_node_or_null
	print("[Player] ", name, " hurtbox layer ANTES: ", hurtbox.collision_layer)
	
	if data.team == "killer":
		collision_layer = 4
		collision_mask  = 1
		hurtbox.collision_layer = 16   # killer_hurtbox
		hurtbox.collision_mask  = 0
		print("[Player] ", name, " killer hurtbox layer ASIGNADO: ", hurtbox.collision_layer)
	else:
		collision_layer = 2
		collision_mask  = 1 
		hurtbox.collision_layer = 8    # survivor_hurtbox
		hurtbox.collision_mask  = 0
		print("[Player] ", name, " survivor hurtbox layer ASIGNADO: ", hurtbox.collision_layer)


func _physics_process(_delta: float) -> void:
	if not multiplayer.multiplayer_peer:
		return
	if not is_multiplayer_authority():
		return
	if health_state == "dead":
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_dir * speed
	move_and_slide()

	var dir_to_mouse := (get_global_mouse_position() - global_position).normalized()
	update_animation_and_flip(dir_to_mouse, velocity.length() > 0.1)
	
	# ── TRACKER DE AUDIO DE PROXIMIDAD ──
	# Solo el superviviente local calcula qué tan cerca está el peligro
	if character_data and character_data.team == "survivor":
		var killers = get_tree().get_nodes_in_group("killers")
		if killers.size() > 0 and is_instance_valid(killers[0]):
			var dist = global_position.distance_to(killers[0].global_position)
			AudioManager.update_proximities(dist)

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


# ── Sincronización desde el servidor ──────────────────────────────────

@rpc("any_peer", "call_local", "reliable")
func _sync_health(new_health: int, new_invincible_until: int) -> void:
	health           = new_health
	invincible_until = new_invincible_until
	print("[Player] ", name, " | vida: ", health)


@rpc("any_peer", "call_local", "reliable")
func _sync_speed(new_speed: float) -> void:
	speed = new_speed
	print("[Player] ", name, " | velocidad: ", speed)


@rpc("any_peer", "call_local", "reliable")
func _sync_effect(effect_name: String, active: bool) -> void:
	# TODO: efectos visuales (flash, color, icono de estado)
	print("[Player] ", name, " | efecto: ", effect_name, " activo: ", active)


@rpc("any_peer", "call_local", "reliable")
func _sync_state(new_state: String, new_health: int) -> void:
	health_state = new_state
	health       = new_health
	print("[Player] ", name, " | estado: ", health_state)

	match new_state:
		"downed":
			# El StatusEffectService aplicará el slow cuando esté listo.
			# Por ahora solo bloqueamos habilidades (ya lo hace _input).
			pass
		"dead":
			# TODO: activar modo espectador
			pass
		"alive":
			# Fue rescatado — restaurar velocidad normal
			if character_data:
				speed = character_data.speed
				
func _initialize_local_audio_streams() -> void:
	if not character_data: return
	
	# Si mi personaje local es un Survivor, le mando mi data para registrar mi LMS music
	if character_data.team == "survivor":
		# Buscamos al Killer que ya esté spawneado en el mapa para extraer sus canciones
		var killers = get_tree().get_nodes_in_group("killers")
		if killers.size() > 0 and is_instance_valid(killers[0]):
			AudioManager.register_match_character_music(killers[0].character_data, character_data)
		else:
			# Si el killer no cargó antes, registramos solo nuestro survivor por ahora
			AudioManager.register_match_character_music(null, character_data)
			
	# Si mi personaje local es el Killer, le mando mis datos de audio al manager
	elif character_data.team == "killer":
		add_to_group("killers") # Nos aseguramos de estar en el grupo para que los survivors nos encuentren
		AudioManager.register_match_character_music(character_data, null)
