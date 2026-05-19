# res://scripts/AudioManager.gd
extends Node

@onready var map_player: AudioStreamPlayer = $MapMusicPlayer
@onready var terror_player: AudioStreamPlayer = $TerrorMusicPlayer
@onready var chase_player: AudioStreamPlayer = $ChaseMusicPlayer
@onready var lms_player: AudioStreamPlayer = $LMSMusicPlayer

const FADE_DURATION: float = 1.0

var current_terror_stream: AudioStream = null
var current_chase_stream: AudioStream = null
var current_lms_stream: AudioStream = null

var current_global_state: String = "menu"

var killer_terror_radius: float = 400.0
var killer_chase_radius: float = 200.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[AudioManager] Inicializado.")

func setup_map_audio(map_id: String) -> void:
	stop_all()
	current_global_state = "map"
	
	var map_data: MapData = MapRegistry.maps.get(map_id)
	# PROTECCIÓN: Verificamos si existe el recurso del mapa y si tiene un BGM asignado
	if map_data and "map_bgm" in map_data and map_data.map_bgm != null:
		map_player.stream = map_data.map_bgm
		map_player.volume_db = -80.0
		map_player.play()
		create_tween().tween_property(map_player, "volume_db", 0.0, FADE_DURATION)
	else:
		print("[AudioManager] ADVERTENCIA: El mapa '", map_id, "' no tiene un map_bgm asignado (Nil).")

func register_match_character_music(killer_data: CharacterData, local_survivor_data: CharacterData = null) -> void:
	# PROTECCIÓN: Solo asignamos si killer_data es válido y sus músicas no son Nil
	if killer_data and is_instance_valid(killer_data):
		current_terror_stream = killer_data.terror_music
		current_chase_stream = killer_data.chase_music
		killer_terror_radius = killer_data.terror_radius
		killer_chase_radius = killer_data.chase_radius
		
		# Asignamos de forma segura comprobando que no sea nulo
		if current_terror_stream != null: terror_player.stream = current_terror_stream
		if current_chase_stream != null: chase_player.stream = current_chase_stream
		
	if local_survivor_data and is_instance_valid(local_survivor_data):
		current_lms_stream = local_survivor_data.lms_music
		if current_lms_stream != null: lms_player.stream = current_lms_stream

@rpc("any_peer", "call_local", "reliable")
func set_global_music_state(new_state: String) -> void:
	if current_global_state == new_state: return
	current_global_state = new_state
	
	match current_global_state:
		"lms":
			_fade_between(lms_player, [map_player, terror_player, chase_player])
		"menu":
			stop_all()

func update_proximities(distance: float) -> void:
	if current_global_state != "map": return
	
	if distance <= killer_chase_radius:
		_execute_proximity_mix(chase_player, [map_player, terror_player], distance, killer_chase_radius)
	elif distance <= killer_terror_radius:
		var range_total = killer_terror_radius - killer_chase_radius
		var distance_shifted = distance - killer_chase_radius
		_execute_proximity_mix(terror_player, [map_player, chase_player], distance_shifted, range_total)
	else:
		map_player.volume_db = lerp(map_player.volume_db, 0.0, 0.05)
		if terror_player.playing: _fade_out_player(terror_player)
		if chase_player.playing: _fade_out_player(chase_player)

func _execute_proximity_mix(active: AudioStreamPlayer, inactives: Array, dist: float, max_dist: float) -> void:
	# PROTECCIÓN: Si el reproductor no tiene música cargada (porque era Nil), salimos para evitar errores
	if active.stream == null: return
	
	if not active.playing:
		active.volume_db = -80.0
		active.play()
		
	var factor := 1.0 - (dist / max_dist)
	var target_active_vol = lerp(-20.0, 0.0, factor)
	var target_map_vol = lerp(0.0, -15.0, factor)
	
	active.volume_db = lerp(active.volume_db, target_active_vol, 0.1)
	map_player.volume_db = lerp(map_player.volume_db, target_map_vol, 0.1)
	
	for player in inactives:
		if player.playing:
			_fade_out_player(player)

func _fade_out_player(player: AudioStreamPlayer) -> void:
	player.volume_db = lerp(player.volume_db, -80.0, 0.08)
	if player.volume_db <= -65.0:
		player.stop()

func _fade_between(active_player: AudioStreamPlayer, inactive_players: Array) -> void:
	# PROTECCIÓN: Si el reproductor al que vamos a cambiar no tiene música (Nil), no hacemos el fade
	if active_player.stream == null: return
	
	var tween = create_tween().set_parallel(true)
	if not active_player.playing:
		active_player.volume_db = -80.0
		active_player.play()
		tween.tween_property(active_player, "volume_db", 0.0, FADE_DURATION)
		
	for player in inactive_players:
		if player.playing:
			tween.tween_property(player, "volume_db", -80.0, FADE_DURATION)
			tween.chain().tween_callback(player.stop)

func stop_all() -> void:
	if map_player.playing: map_player.stop()
	if terror_player.playing: terror_player.stop()
	if chase_player.playing: chase_player.stop()
	if lms_player.playing: lms_player.stop()
