# res://scripts/AudioManager.gd
extends Node

# Si los nodos ya existen (porque la escena los tiene), se usan; si no, se crean.
var map_player: AudioStreamPlayer
var terror_player: AudioStreamPlayer
var chase_player: AudioStreamPlayer
var lms_player: AudioStreamPlayer

const FADE_DURATION: float = 1.0
const CROSSFADE_ZONE: float = 50.0

var current_terror_stream: AudioStream = null
var current_chase_stream: AudioStream = null
var current_lms_stream: AudioStream = null

var _previous_state: String = ""
var current_global_state: String = "menu"

var killer_terror_radius: float = 400.0
var killer_chase_radius: float = 200.0

# Cache del jugador local
var cached_local_player: Node2D = null
var cached_local_player_id: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Buscar o crear los AudioStreamPlayer
	map_player = _get_or_create_player("MapMusicPlayer")
	terror_player = _get_or_create_player("TerrorMusicPlayer")
	chase_player = _get_or_create_player("ChaseMusicPlayer")
	lms_player = _get_or_create_player("LMSMusicPlayer")
	print("[AudioManager] Inicializado.")

# Helper: obtiene el nodo hijo si existe, o lo crea
func _get_or_create_player(name: String) -> AudioStreamPlayer:
	var player = get_node_or_null(name)
	if not player:
		player = AudioStreamPlayer.new()
		player.name = name
		add_child(player)
	return player

func setup_map_audio(map_id: String) -> void:
	stop_all()
	current_global_state = "map"
	
	var map_data: MapData = MapRegistry.get_map(map_id)
	if map_data and map_data.map_bgm != null:
		print("[AUDIO TEST] Reproduciendo música de mapa: ", map_data.map_bgm.resource_path)
		map_player.stream = map_data.map_bgm
		map_player.volume_db = -80.0
		map_player.play()
		create_tween().tween_property(map_player, "volume_db", 0.0, FADE_DURATION)
	else:
		print("[AudioManager] ADVERTENCIA: El mapa '", map_id, "' no tiene map_bgm asignado.")

func register_match_character_music(killer_data: CharacterData, local_survivor_data: CharacterData = null) -> void:
	if killer_data and is_instance_valid(killer_data):
		current_terror_stream = killer_data.terror_music
		current_chase_stream = killer_data.chase_music
		killer_terror_radius = killer_data.terror_radius
		killer_chase_radius = killer_data.chase_radius
		
		if current_terror_stream != null:
			terror_player.stream = current_terror_stream
		else:
			terror_player.stream = null
			_stop_player(terror_player)
		
		if current_chase_stream != null:
			chase_player.stream = current_chase_stream
		else:
			chase_player.stream = null
			_stop_player(chase_player)
		
	if local_survivor_data and is_instance_valid(local_survivor_data):
		current_lms_stream = local_survivor_data.lms_music
		if current_lms_stream != null:
			lms_player.stream = current_lms_stream
			print("[AudioManager] LMS music cargado: ", current_lms_stream.resource_path)
		else:
			lms_player.stream = null
			push_error("[AudioManager] LMS music es null para survivor ", local_survivor_data.display_name)

# IMPORTANTE: El servidor replica el estado a todos los clientes
@rpc("authority", "reliable")
func set_global_music_state(new_state: String) -> void:
	print("[AudioManager] set_global_music_state llamado en peer ", multiplayer.get_unique_id(), " con estado: ", new_state)
	if current_global_state == new_state:
		return
	
	_previous_state = current_global_state
	current_global_state = new_state
	
	match current_global_state:
		"lms":
			# Asegurar que el LMS tenga stream
			if lms_player.stream == null:
				push_error("[AudioManager] No se puede activar LMS: lms_player sin stream")
				return
			_fade_between(lms_player, [map_player, terror_player, chase_player])
		"menu":
			stop_all()
		"map":
			_restore_normal_music()

# Permite salir del modo LMS (llamado desde el servidor cuando termina)
func exit_lms() -> void:
	if current_global_state == "lms":
		set_global_music_state(_previous_state if _previous_state != "" else "map")

func _restore_normal_music() -> void:
	# Reanudar música de mapa si no está sonando
	if not map_player.playing and map_player.stream:
		map_player.volume_db = -80.0
		map_player.play()
		create_tween().tween_property(map_player, "volume_db", 0.0, FADE_DURATION)

func update_proximities(distance: float) -> void:
	if current_global_state != "map":
		return
	
	if distance <= killer_chase_radius:
		var t = 1.0 - (distance / killer_chase_radius)
		_mix_two_players(chase_player, terror_player, t, map_player)
	elif distance <= killer_terror_radius:
		var d = distance - killer_chase_radius
		var range_total = killer_terror_radius - killer_chase_radius
		var t = 1.0 - (d / range_total)
		_mix_two_players(terror_player, chase_player, t, map_player)
	else:
		_fade_out_player_smooth(map_player, 0.0)
		_fade_out_player_smooth(terror_player, -80.0, true)
		_fade_out_player_smooth(chase_player, -80.0, true)

func _mix_two_players(active: AudioStreamPlayer, secondary: AudioStreamPlayer, t: float, map_p: AudioStreamPlayer) -> void:
	if active.stream == null:
		_fade_out_player_smooth(active, -80.0, true)
		return
	
	if not active.playing:
		active.volume_db = -80.0
		active.play()
	
	var target_active_vol = lerp(-20.0, 0.0, t)
	active.volume_db = lerp(active.volume_db, target_active_vol, 0.2)
	
	if secondary.stream != null and secondary.playing:
		var target_secondary_vol = lerp(0.0, -80.0, t)
		secondary.volume_db = lerp(secondary.volume_db, target_secondary_vol, 0.2)
		if secondary.volume_db <= -70.0:
			secondary.stop()
	
	var target_map_vol = lerp(0.0, -25.0, t)
	map_p.volume_db = lerp(map_p.volume_db, target_map_vol, 0.1)

func _fade_out_player_smooth(player: AudioStreamPlayer, target_db: float = -80.0, stop_when_done: bool = true) -> void:
	if not player.playing:
		return
	var tween = create_tween()
	tween.tween_property(player, "volume_db", target_db, FADE_DURATION)
	if stop_when_done:
		tween.tween_callback(_stop_player.bind(player))

func _stop_player(player: AudioStreamPlayer) -> void:
	if player.playing:
		player.stop()

func _fade_between(active_player: AudioStreamPlayer, inactive_players: Array) -> void:
	if active_player.stream == null:
		push_error("[AudioManager] _fade_between: active_player sin stream")
		return
	# Verificar que el stream tenga archivo (evita error de MP3 vacío)
	if active_player.stream is AudioStreamMP3 and active_player.stream.resource_path.is_empty():
		push_error("[AudioManager] El stream de LMS no tiene archivo asignado.")
		return
	
	var tween = create_tween()
	tween.set_parallel(true)  # IMPORTANTE: todos los fades al mismo tiempo
	
	# Activo: asegurar que suene y subir volumen a 0 dB
	if not active_player.playing:
		active_player.volume_db = -80.0
		active_player.play()
	tween.tween_property(active_player, "volume_db", 0.0, FADE_DURATION)
	
	# Inactivos: bajar volumen a -80 dB
	for player in inactive_players:
		if player.playing:  # solo si está sonando (evita errores)
			tween.tween_property(player, "volume_db", -80.0, FADE_DURATION)
	
	# Al terminar todos los fades, detener los que estén en silencio
	tween.finished.connect(func():
		for player in inactive_players:
			if player.playing and player.volume_db <= -70.0:
				player.stop()
	)


func stop_all() -> void:
	for player in [map_player, terror_player, chase_player, lms_player]:
		if player.playing:
			player.stop()

func _process(_delta: float) -> void:
	if current_global_state != "map":
		return
	
	var multiplayer_instance = multiplayer
	if not multiplayer_instance:
		var local = get_tree().root.find_child("LocalPlayer", true, false)
		if local and is_instance_valid(local):
			_update_proximities_from_local(local)
		return
	
	var local_peer_id: int = multiplayer_instance.get_unique_id()
	
	if cached_local_player_id != local_peer_id or not is_instance_valid(cached_local_player):
		cached_local_player_id = local_peer_id
		cached_local_player = _find_player_node_by_peer_id(local_peer_id)
	
	if not is_instance_valid(cached_local_player):
		return
	
	if cached_local_player.has_method("get_character_data") or "character_data" in cached_local_player:
		var char_data = cached_local_player.character_data if "character_data" in cached_local_player else null
		if char_data and char_data.team == "killer":
			return
	
	var killer_node: Node2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node2D and "character_data" in p and p.character_data and p.character_data.team == "killer":
			killer_node = p
			break
	
	if killer_node and is_instance_valid(killer_node):
		var distance: float = cached_local_player.global_position.distance_to(killer_node.global_position)
		update_proximities(distance)
	else:
		_fade_out_player_smooth(terror_player, -80.0, true)
		_fade_out_player_smooth(chase_player, -80.0, true)

func _find_player_node_by_peer_id(peer_id: int) -> Node2D:
	for node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node
		if node.has_meta("peer_id") and node.get_meta("peer_id") == peer_id:
			return node
	return null

func _update_proximities_from_local(local_player: Node2D) -> void:
	if not local_player or not is_instance_valid(local_player):
		return
	if local_player.has_method("get_character_data") or "character_data" in local_player:
		var char_data = local_player.character_data if "character_data" in local_player else null
		if char_data and char_data.team == "killer":
			return
	var killer_node: Node2D = null
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node2D and "character_data" in p and p.character_data and p.character_data.team == "killer":
			killer_node = p
			break
	if killer_node:
		var distance = local_player.global_position.distance_to(killer_node.global_position)
		update_proximities(distance)
	else:
		_fade_out_player_smooth(terror_player, -80.0, true)
		_fade_out_player_smooth(chase_player, -80.0, true)
