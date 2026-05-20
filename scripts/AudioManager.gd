# res://scripts/AudioManager.gd
# Autoload Global de Audio — Adaptado para recibir música dinámica de mapas y personajes.
extends Node

var current_global_state: String = "menu"

# Nodos reales de tu escena (.tscn)
@onready var map_music_player: AudioStreamPlayer = $MapMusicPlayer
@onready var terror_music_player: AudioStreamPlayer = $TerrorMusicPlayer
@onready var chase_music_player: AudioStreamPlayer = $ChaseMusicPlayer
@onready var lms_music_player: AudioStreamPlayer = $LMSMusicPlayer

# Variables de rastreo local
var cached_local_player_id: int = -1
var cached_local_player: Node = null
var lms_bloqueo_activo: bool = false # Interruptor maestro para silenciar el mapa de raíz

# Configuración de transición (Lerp)
const FADE_SPEED := 4.5 # Un poco más rápido para transiciones más agresivas en LMS
const MIN_DB := -80.0
const MAX_DB := 0.0

# Radios de acción (Ajustables)
const TERROR_RADIUS := 500.0
const CHASE_RADIUS := 200.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return


func _process(delta: float) -> void:
	# ── 1. COMPUERTA DEFENSIVA DE RED ──
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_silence_all_match_audio(delta)
		return
		
	if current_global_state == "menu" or current_global_state == "lobby":
		_silence_all_match_audio(delta)
		return
	# ───────────────────────────────────

	# ── 2. ASIGNACIÓN SEGURA DEL JUGADOR LOCAL ──
	if cached_local_player_id == -1:
		cached_local_player_id = multiplayer.get_unique_id()
		
	if not is_instance_valid(cached_local_player):
		cached_local_player = _find_player_node_by_peer_id(cached_local_player_id)
		return 
	# ────────────────────────────────────────────

	# ── 3. CÁLCULO DINÁMICO DE DISTANCIAS ──
	_update_proximities_from_local(cached_local_player, delta)


# =======================================================================
# API PÚBLICA: INYECCIÓN DE AUDIO DESDE MAPAS Y PERSONAJES
# =======================================================================

func set_character_threat_audio(terror_stream: AudioStream, chase_stream: AudioStream) -> void:
	if terror_music_player: terror_music_player.stream = terror_stream
	if chase_music_player: chase_music_player.stream = chase_stream
	print("[AudioManager] Audio de peligro inyectado correctamente por el personaje.")


# =======================================================================
# LÓGICA DE PROXIMIDAD Y MEZCLA DE AUDIO (CLIENTE)
# =======================================================================

func _update_proximities_from_local(local_player: Node, delta: float) -> void:
	var killers = get_tree().get_nodes_in_group("killer")
	var survivors = get_tree().get_nodes_in_group("survivor")
	
	var usando_lms: bool = (survivors.size() <= 1 and lms_music_player.stream != null)
	
	# ── PRIORIDAD ABSOLUTA PARA LMS ──
	# Nota: cuando lms_bloqueo_activo es true, los streams de mapa/terror/chase
	# ya fueron descargados (null) por activate_lms_audio, así que _smooth_fade
	# no puede reactivarlos. Solo nos ocupamos del player LMS aquí.
	if usando_lms or lms_bloqueo_activo:
		if lms_music_player.stream and not lms_music_player.playing:
			lms_music_player.volume_db = MAX_DB
			lms_music_player.play()
			print("[AUDIO DEBUG] LMS iniciado con éxito en proceso continuo.")
		return
	# ─────────────────────────────────

	# LÓGICA NORMAL DE LA PARTIDA
	if lms_music_player.playing:
		lms_music_player.stop()

	if killers.size() == 0:
		_smooth_fade(terror_music_player, MIN_DB, delta)
		_smooth_fade(chase_music_player, MIN_DB, delta)
		_smooth_fade(map_music_player, MAX_DB, delta)
		return
		
	var killer_node = killers[0]
	if not is_instance_valid(killer_node): return
		
	var distance: float = local_player.global_position.distance_to(killer_node.global_position)
	
	if distance <= CHASE_RADIUS:
		_smooth_fade(chase_music_player, MAX_DB, delta)
		_smooth_fade(terror_music_player, -6.0, delta)
		_smooth_fade(map_music_player, -15.0, delta) 
	elif distance <= TERROR_RADIUS:
		var factor: float = 1.0 - ((distance - CHASE_RADIUS) / (TERROR_RADIUS - CHASE_RADIUS))
		var target_db := lerpf(MIN_DB + 20.0, MAX_DB, factor) 
		
		_smooth_fade(terror_music_player, target_db, delta)
		_smooth_fade(chase_music_player, MIN_DB, delta) 
		_smooth_fade(map_music_player, lerpf(MAX_DB, -10.0, factor), delta)
	else:
		_smooth_fade(terror_music_player, MIN_DB, delta)
		_smooth_fade(chase_music_player, MIN_DB, delta)
		_smooth_fade(map_music_player, MAX_DB, delta)


func _smooth_fade(player: AudioStreamPlayer, target_db: float, delta: float) -> void:
	if player.stream == null: return
		
	if not player.playing and target_db > MIN_DB:
		player.play()
		player.volume_db = MIN_DB 
		
	player.volume_db = lerpf(player.volume_db, target_db, FADE_SPEED * delta)
	
	if player.playing and player.volume_db <= MIN_DB + 1.0:
		player.stop()


# =======================================================================
# CONTROL DE ESTADOS GLOBALES Y FLUJO
# =======================================================================

func activate_lms_audio() -> void:
	lms_bloqueo_activo = true

	# Detenemos y descargamos los streams para que _smooth_fade no pueda reactivarlos
	if map_music_player:
		map_music_player.stop()
		map_music_player.stream = null
	if terror_music_player:
		terror_music_player.stop()
		terror_music_player.stream = null
	if chase_music_player:
		chase_music_player.stop()
		chase_music_player.stream = null

	if lms_music_player and lms_music_player.stream and not lms_music_player.playing:
		lms_music_player.volume_db = MAX_DB
		lms_music_player.play()


@rpc("authority", "call_local", "reliable")
func _rpc_activate_lms_audio() -> void:
	activate_lms_audio()


@rpc("authority", "call_local", "reliable")
func _rpc_deactivate_lms_audio() -> void:
	lms_bloqueo_activo = false

	if lms_music_player.playing:
		lms_music_player.stop()

	# Restauramos el stream del mapa desde el registro para que pueda sonar de nuevo
	var map_id: String = GameData.selected_map if "selected_map" in GameData else ""
	if map_id != "":
		var map_data = MapRegistry.get_map(map_id) as MapData
		if map_data and map_music_player:
			map_music_player.stream = map_data.map_bgm
			map_music_player.volume_db = MAX_DB
			map_music_player.play()


func change_audio_state(new_state: String) -> void:
	current_global_state = new_state
	print("[AudioManager] Estado cambiado a: ", new_state)
	
	if new_state == "ingame" and not lms_bloqueo_activo:
		if map_music_player.stream and not map_music_player.playing: 
			map_music_player.play()


func _silence_all_match_audio(delta: float) -> void:
	lms_bloqueo_activo = false
	_smooth_fade(map_music_player, MIN_DB, delta)
	_smooth_fade(terror_music_player, MIN_DB, delta)
	_smooth_fade(chase_music_player, MIN_DB, delta)
	_smooth_fade(lms_music_player, MIN_DB, delta)


func _find_player_node_by_peer_id(peer_id: int) -> Node:
	var root_scene = get_tree().current_scene
	if root_scene:
		return root_scene.find_child(str(peer_id), true, false)
	return null

func update_proximities(_optional_dist = null) -> void:
	if is_instance_valid(cached_local_player):
		_update_proximities_from_local(cached_local_player, 0.016)

func register_match_character_music(killer_terror: AudioStream, killer_chase: AudioStream, survivor_lms: AudioStream) -> void:
	set_character_threat_audio(killer_terror, killer_chase)

	if lms_music_player and survivor_lms:
		lms_music_player.stream = survivor_lms

	if current_global_state == "ingame":
		_verificar_y_reproducir_base()


func setup_map_audio(map_id: String) -> void:
	if map_id == "": return
	var map_data = MapRegistry.get_map(map_id) as MapData
	if not map_data: return

	if map_music_player:
		map_music_player.stream = map_data.map_bgm

	setup_map_audio_finish()


func setup_map_audio_finish() -> void:
	change_audio_state("ingame")
	_verificar_y_reproducir_base()


func _verificar_y_reproducir_base() -> void:
	var survivors = get_tree().get_nodes_in_group("survivor")
	
	if survivors.size() <= 1 and lms_music_player and lms_music_player.stream:
		activate_lms_audio()
	else:
		lms_bloqueo_activo = false
		if lms_music_player.playing:
			lms_music_player.stop()
		
		if map_music_player and map_music_player.stream and not map_music_player.playing:
			map_music_player.play()
			map_music_player.volume_db = MAX_DB


func activar_fase_final_del_mapa() -> void:
	var map_id: String = GameData.selected_map if "selected_map" in GameData else "1"
	var map_data = MapRegistry.get_map(map_id) as MapData
	
	if map_data and map_data.final_phase_music and map_music_player:
		map_music_player.stream = map_data.final_phase_music
		
		if not lms_bloqueo_activo:
			map_music_player.play()
			map_music_player.volume_db = MAX_DB
			print("[AudioManager] Transición: Sonando música de escape del mapa.")
