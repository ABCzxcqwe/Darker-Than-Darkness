# res://audio/AudioManager.gd
# Autoload Global de Audio — Godot nativo con prioridades, chase variant y oclusión
extends Node

# =======================================================================
# ENUMS
# =======================================================================
enum PriorityLevel { NONE = 0, ESCAPE = 1, SPECIAL = 2, LMS = 3 }
enum ChaseVariantType { NORMAL = 0, LAST_LIFE = 1 }

# =======================================================================
# ESTADOS
# =======================================================================
var current_global_state: String = "menu"
var lms_bloqueo_activo: bool = false
var _is_chasing: bool = false
var _current_priority: int = PriorityLevel.NONE
var _chase_variant: int = ChaseVariantType.NORMAL

# Nodos de audio (.tscn)
@onready var map_music_player: AudioStreamPlayer = $MapMusicPlayer
@onready var terror_music_player: AudioStreamPlayer = $TerrorMusicPlayer
@onready var chase_music_player: AudioStreamPlayer = $ChaseMusicPlayer
@onready var lms_music_player: AudioStreamPlayer = $LMSMusicPlayer
@onready var menu_music_player: AudioStreamPlayer = $MenuMusicPlayer

# Streams de chase (se intercambian según variante)
var _chase_stream_normal: AudioStream = null
var _chase_stream_last_life: AudioStream = null

# Loop configurable (segundos). -1 = sin recorte.
var _map_loop_start: float = 0.0
var _map_loop_end: float = -1.0
var _final_loop_start: float = 0.0
var _final_loop_end: float = -1.0
var _priority_before_special: int = PriorityLevel.NONE
var _escape_was_active: bool = false

# =======================================================================
# RADIOS (se sobreescriben desde CharacterData del asesino)
# =======================================================================
var terror_radius: float = 500.0
var chase_radius_base: float = 200.0
var chase_radius_expanded: float = 400.0

# Oclusión
var occlusion_mask: int = 1

# =======================================================================
# RASTREO LOCAL
# =======================================================================
var cached_local_player_id: int = -1
var cached_local_player: Node = null

# =======================================================================
# CONFIGURACIÓN DE FADE
# =======================================================================
const FADE_SPEED := 4.5
const MIN_DB := -80.0
const MAX_DB := 0.0

# =======================================================================
# SFX POOL
# =======================================================================
const SFX_POOL_SIZE := 16

var _sfx_library: Dictionary = {}  # int id -> AudioStream
var _pool_2d: Array[AudioStreamPlayer2D] = []
var _pool: Array[AudioStreamPlayer] = []

func _init_sfx_pool() -> void:
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.bus = &"SFX"
		p.finished.connect(_release_2d.bind(p))
		add_child(p)
		_pool_2d.append(p)

		var pu := AudioStreamPlayer.new()
		pu.bus = &"SFX"
		pu.finished.connect(_release.bind(pu))
		add_child(pu)
		_pool.append(pu)

func _acquire_2d() -> AudioStreamPlayer2D:
	for p in _pool_2d:
		if not p.playing:
			return p
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.finished.connect(_release_2d.bind(p))
	add_child(p)
	_pool_2d.append(p)
	return p

func _acquire() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.finished.connect(_release.bind(p))
	add_child(p)
	_pool.append(p)
	return p

func _release_2d(p: AudioStreamPlayer2D) -> void:
	p.stream = null

func _release(p: AudioStreamPlayer) -> void:
	p.stream = null

func _load_sfx_files() -> void:
	_sfx_library.clear()
	var library := load("res://audio/SfxLibrary.tres") as SfxLibrary
	if not library:
		push_error("[AudioManager] No se pudo cargar SfxLibrary.tres")
		return
	for entry in library.sounds:
		if entry and entry.stream:
			_sfx_library[entry.id] = entry.stream

func play_sfx(sfx_id: int, position: Vector2) -> void:
	var stream = _sfx_library.get(sfx_id)
	if not stream:
		push_warning("[AudioManager] SFX no encontrado: ", sfx_id)
		return
	var player := _acquire_2d()
	player.stream = stream
	player.global_position = position
	player.play()

func play_sfx_ui(sfx_id: int) -> void:
	var stream = _sfx_library.get(sfx_id)
	if not stream:
		push_warning("[AudioManager] SFX no encontrado: ", sfx_id)
		return
	var player := _acquire()
	player.stream = stream
	player.play()

func play_stream(stream: AudioStream) -> void:
	if not stream:
		return
	var player := _acquire()
	player.stream = stream
	player.play()

func play_stream_2d(stream: AudioStream, position: Vector2) -> void:
	if not stream:
		return
	var player := _acquire_2d()
	player.stream = stream
	player.global_position = position
	player.play()

@rpc("any_peer", "reliable", "call_local")
func play_sfx_networked(sfx_id: int, x: float, y: float) -> void:
	play_sfx(sfx_id, Vector2(x, y))

func play_sfx_global(sfx_id: int) -> void:
	var stream = _sfx_library.get(sfx_id)
	if not stream:
		push_warning("[AudioManager] SFX no encontrado: ", sfx_id)
		return
	var player := _acquire()
	player.stream = stream
	player.play()

@rpc("any_peer", "reliable", "call_local")
func play_sfx_global_networked(sfx_id: int) -> void:
	play_sfx_global(sfx_id)

@rpc("authority", "reliable", "call_local")
func play_stream_2d_rpc(path: String, x: float, y: float) -> void:
	var stream := load(path) as AudioStream
	if stream:
		play_stream_2d(stream, Vector2(x, y))

# =======================================================================
# CICLO DE VIDA
# =======================================================================
func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_init_sfx_pool()
	_load_sfx_files()

func _process(delta: float) -> void:
	# Menu drone: canal dedicado Menu Music -> Master, aislado de Map Music.
	# Auto-repair si estamos en menu sin musica (tras reset_match_audio o arranque).
	if current_global_state == "menu" and multiplayer.multiplayer_peer == null:
		if menu_music_player and (menu_music_player.stream == null or not menu_music_player.playing):
			if get_tree().current_scene and get_tree().current_scene.name != "CharacterSelect":
				play_menu_drone()
				return
	if current_global_state == "menu_drone":
		# Asegurar que el drone siga sonando, no silenciar.
		if menu_music_player and menu_music_player.stream and not menu_music_player.playing:
			menu_music_player.volume_db = MAX_DB
			menu_music_player.play()
		return
	if _is_disconnected_or_menu():
		_silence_all_match_audio(delta)
		return

	_handle_loop_ends()

	if cached_local_player_id == -1:
		cached_local_player_id = multiplayer.get_unique_id()
	if not is_instance_valid(cached_local_player):
		cached_local_player = _find_player_node_by_peer_id(cached_local_player_id)
		return

	_update_proximities(cached_local_player, delta)


func _handle_loop_ends() -> void:
	# Para MP3/Ogg nativo no tiene loop_end, recortamos silencio con seek manual.
	# WAV ya loopea nativo via loop_begin/end, no necesita polling.
	if _map_loop_end > 0.0 and map_music_player and map_music_player.playing and map_music_player.stream:
		# Solo para streams que no son WAV (WAV ya corta nativo)
		if not (map_music_player.stream is AudioStreamWAV):
			var pos := map_music_player.get_playback_position()
			if pos >= _map_loop_end:
				map_music_player.seek(_map_loop_start)
	if _final_loop_end > 0.0 and lms_music_player and lms_music_player.playing and lms_music_player.stream:
		# final_phase_music comparte lms_music_player cuando prioridad ESCAPE
		if _current_priority == PriorityLevel.ESCAPE and not (lms_music_player.stream is AudioStreamWAV):
			var pos2 := lms_music_player.get_playback_position()
			if pos2 >= _final_loop_end:
				lms_music_player.seek(_final_loop_start)

func _is_disconnected_or_menu() -> bool:
	if current_global_state == "menu_drone":
		return false
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return true
	if current_global_state == "menu" or current_global_state == "lobby":
		return true
	# Fallback por LobbyManager (cubre ENDED sin que AudioManager haya recibido reset aún)
	if LobbyManager and LobbyManager.current_phase == LobbyManager.GamePhase.ENDED:
		return true
	return false

# =======================================================================
# LÓGICA DE PROXIMIDAD
# =======================================================================
func _update_proximities(player: Node, delta: float) -> void:
	if not is_instance_valid(player):
		return
	if "interaction" in player and player.interaction and player.interaction.is_spectator:
		var ctrl := get_tree().get_first_node_in_group(GroupNames.SPECTATOR)
		var target = ctrl.get_follow_target() if ctrl and ctrl.has_method("get_follow_target") else null
		if is_instance_valid(target):
			player = target
		else:
			return

	var killers = get_tree().get_nodes_in_group("killer")
	var survivors = get_tree().get_nodes_in_group("survivor")

	var priority_active = _current_priority >= PriorityLevel.ESCAPE or lms_bloqueo_activo

	if priority_active:
		_smooth_fade(map_music_player, MIN_DB, delta)
		_smooth_fade(terror_music_player, MIN_DB, delta)
		_smooth_fade(chase_music_player, MIN_DB, delta)
		_smooth_fade(lms_music_player, MAX_DB, delta)
		return

	if lms_music_player.playing:
		lms_music_player.stop()

	if killers.size() == 0:
		_is_chasing = false
		_smooth_fade(terror_music_player, MIN_DB, delta)
		_smooth_fade(chase_music_player, MIN_DB, delta)
		_smooth_fade(map_music_player, MAX_DB, delta)
		return

	var killer_node = killers[0]
	if not is_instance_valid(killer_node):
		return

	var is_killer: bool = player.is_in_group("killer")
	var distance: float = player.global_position.distance_to(killer_node.global_position)

	var occluded: bool = _check_occlusion(player.global_position, killer_node.global_position)

	var chase_range = chase_radius_expanded if _is_chasing else chase_radius_base

	var relay = GameServiceLocator.get_client_relay()

	if is_killer:
		for s in survivors:
			if not is_instance_valid(s): continue
			if "health_state" in s and s.health_state != "alive": continue
			if relay and relay.has_player_escaped(s.get_multiplayer_authority()): continue
			var d: float = player.global_position.distance_to(s.global_position)
			if d <= chase_range:
				if not _is_chasing:
					_is_chasing = true
				_smooth_fade(chase_music_player, MAX_DB, delta)
				_smooth_fade(map_music_player, MIN_DB, delta)
				_smooth_fade(terror_music_player, MIN_DB, delta)
				return
		_is_chasing = false
		_smooth_fade(chase_music_player, MIN_DB, delta)
		_smooth_fade(map_music_player, MAX_DB, delta)
		_smooth_fade(terror_music_player, MIN_DB, delta)
		return

	if distance <= chase_range:
		if not _is_chasing:
			_is_chasing = true
		_smooth_fade(chase_music_player, MAX_DB, delta)
		_smooth_fade(terror_music_player, MIN_DB, delta)
		_smooth_fade(map_music_player, MIN_DB, delta)
	elif distance <= terror_radius:
		if _is_chasing:
			_is_chasing = false
		var factor: float = 1.0 - ((distance - chase_radius_base) / (terror_radius - chase_radius_base))
		var target_db := lerpf(-30.0, 0.0, factor)
		if occluded:
			target_db = lerpf(target_db, MIN_DB, 0.6)
		_smooth_fade(terror_music_player, target_db, delta)
		_smooth_fade(chase_music_player, MIN_DB, delta)
		_smooth_fade(map_music_player, MAX_DB, delta)
	else:
		if _is_chasing:
			_is_chasing = false
		_smooth_fade(terror_music_player, MIN_DB, delta)
		_smooth_fade(chase_music_player, MIN_DB, delta)
		_smooth_fade(map_music_player, MAX_DB, delta)

func _smooth_fade(player: AudioStreamPlayer, target_db: float, delta: float) -> void:
	if player.stream == null:
		return
	if not player.playing and target_db > MIN_DB:
		player.play()
		player.volume_db = MIN_DB
	player.volume_db = lerpf(player.volume_db, target_db, FADE_SPEED * delta)

func _check_occlusion(from: Vector2, to: Vector2) -> bool:
	var space = get_tree().root.get_world_2d().direct_space_state
	if not space:
		return false
	var query = PhysicsRayQueryParameters2D.create(from, to, occlusion_mask)
	var result = space.intersect_ray(query)
	return not result.is_empty()

# =======================================================================
# API PÚBLICA — INYECCIÓN
# =======================================================================
func _set_stream_loop(stream: AudioStream, loop: bool) -> void:
	# Legacy wrapper — ahora usa _configure_stream_loop con duplicate.
	# Mantenido para compatibilidad con llamadas externas.
	if stream == null:
		return
	var s := _configure_stream_loop(stream, 0.0, -1.0, loop)
	# Nota: caller debe reasignar stream = s si quiere usar el duplicate.
	# Para compat, si es WAV o tiene loop, mutamos original como fallback.
	if s != stream and "loop" in stream:
		stream.loop = loop


func _duplicate_stream(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	# duplicate() crea instancia separada para no mutar el Resource de MapData
	if stream.has_method("duplicate"):
		return stream.duplicate() as AudioStream
	return stream


func _configure_stream_loop(stream: AudioStream, loop_start: float, loop_end: float, loop: bool = true) -> AudioStream:
	if stream == null:
		return null
	var s := _duplicate_stream(stream)
	if loop and s is AudioStreamWAV:
		var wav := s as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		if loop_start >= 0.0:
			wav.loop_begin = int(loop_start * wav.mix_rate)
		if loop_end >= 0.0:
			wav.loop_end = int(loop_end * wav.mix_rate)
		elif loop_end < 0:
			wav.loop_end = -1
		return wav
	if "loop" in s:
		s.loop = loop
		if loop and "loop_offset" in s:
			s.loop_offset = maxf(loop_start, 0.0)
	return s


func set_character_threat_audio(terror_stream: AudioStream, chase_stream: AudioStream) -> void:
	if terror_music_player:
		var s1 := _configure_stream_loop(terror_stream, 0.0, -1.0, true) if terror_stream else null
		terror_music_player.stream = s1
	if chase_music_player:
		var s2 := _configure_stream_loop(chase_stream, 0.0, -1.0, true) if chase_stream else null
		_chase_stream_normal = s2
		chase_music_player.stream = s2

func set_killer_config(terror_r: float, chase_r: float) -> void:
	terror_radius = terror_r
	chase_radius_base = chase_r
	chase_radius_expanded = chase_r * 2.0

func reset_match_audio() -> void:
	if map_music_player and map_music_player.playing:
		map_music_player.stop()
	if terror_music_player and terror_music_player.playing:
		terror_music_player.stop()
	if chase_music_player and chase_music_player.playing:
		chase_music_player.stop()
	if lms_music_player and lms_music_player.playing:
		lms_music_player.stop()

	if map_music_player:
		map_music_player.stream = null
	if terror_music_player:
		terror_music_player.stream = null
	if chase_music_player:
		chase_music_player.stream = null
	if lms_music_player:
		lms_music_player.stream = null
	# Menu Music es canal dedicado -> no tocar aquí, preserva drone entre Settings/CreateRoom/Lobby
	# Solo resetear si se pide explícitamente via stop_menu_drone()

	_chase_stream_normal = null
	_chase_stream_last_life = null

	cached_local_player = null
	cached_local_player_id = -1

	_current_priority = PriorityLevel.NONE
	_priority_before_special = PriorityLevel.NONE
	_escape_was_active = false
	lms_bloqueo_activo = false
	_is_chasing = false
	_chase_variant = ChaseVariantType.NORMAL

	_map_loop_start = 0.0
	_map_loop_end = -1.0
	_final_loop_start = 0.0
	_final_loop_end = -1.0

	current_global_state = "menu"


func setup_map_audio(map_id: String) -> void:
	reset_match_audio()
	if map_id == "":
		return
	var map_data = MapRegistry.get_map(map_id) as MapData
	if not map_data:
		return
	if map_music_player and map_data.map_bgm:
		var s := _configure_stream_loop(map_data.map_bgm, map_data.map_bgm_loop_start, map_data.map_bgm_loop_end, true)
		map_music_player.stream = s
		_map_loop_start = maxf(map_data.map_bgm_loop_start, 0.0)
		_map_loop_end = map_data.map_bgm_loop_end
	else:
		_map_loop_start = 0.0
		_map_loop_end = -1.0
	setup_map_audio_finish()

func setup_map_audio_finish() -> void:
	change_audio_state("ingame")

func register_match_character_music(killer_terror: AudioStream, killer_chase: AudioStream, survivor_lms: AudioStream) -> void:
	set_character_threat_audio(killer_terror, killer_chase)
	if lms_music_player and survivor_lms:
		var s := _configure_stream_loop(survivor_lms, 0.0, -1.0, false)
		lms_music_player.stream = s
	if current_global_state == "ingame":
		_restore_base()

func change_audio_state(new_state: String) -> void:
	current_global_state = new_state
	if new_state == "menu_drone":
		if menu_music_player and menu_music_player.stream and not menu_music_player.playing:
			menu_music_player.volume_db = MAX_DB
			menu_music_player.play()
		return
	if new_state == "ingame":
		# Al entrar a partida, apagar menu drone (canal dedicado)
		if menu_music_player and menu_music_player.playing:
			menu_music_player.stop()
		if not lms_bloqueo_activo:
			if map_music_player.stream and not map_music_player.playing:
				map_music_player.volume_db = MAX_DB
				map_music_player.play()

# =======================================================================
# PRIORIDAD: SPECIAL → ESCAPE → LMS
# =======================================================================
func activate_special_music() -> void:
	_start_priority_stream(PriorityLevel.SPECIAL)

@rpc("authority", "reliable", "call_local")
func _rpc_activate_special_music() -> void:
	_current_priority = PriorityLevel.SPECIAL
	if map_music_player: map_music_player.stop()
	if terror_music_player: terror_music_player.stop()
	if chase_music_player: chase_music_player.stop()
	if lms_music_player: lms_music_player.stop()

@rpc("authority", "call_local", "reliable")
func activar_fase_final_del_mapa() -> void:
	_start_priority_stream(PriorityLevel.ESCAPE)

func activate_lms_audio() -> void:
	_current_priority = PriorityLevel.LMS
	lms_bloqueo_activo = true
	if map_music_player:
		map_music_player.stop()
	if terror_music_player:
		terror_music_player.stop()
	if chase_music_player:
		chase_music_player.stop()
	if lms_music_player and lms_music_player.stream and not lms_music_player.playing:
		lms_music_player.volume_db = MAX_DB
		lms_music_player.play()

func stop_priority_music() -> void:
	_current_priority = PriorityLevel.NONE
	lms_bloqueo_activo = false
	if lms_music_player.playing:
		lms_music_player.stop()
	if not lms_bloqueo_activo:
		_restore_base()

@rpc("authority", "reliable", "call_local")
func _rpc_stop_priority_music() -> void:
	stop_priority_music()

func _start_priority_stream(priority: int) -> void:
	if priority <= _current_priority and _current_priority != PriorityLevel.NONE:
		return
	_current_priority = priority
	lms_bloqueo_activo = false
	if map_music_player:
		map_music_player.stop()
	if terror_music_player:
		terror_music_player.stop()
	if chase_music_player:
		chase_music_player.stop()
	if lms_music_player:
		var map_data = MapRegistry.get_map(GameData.selected_map if "selected_map" in GameData else "") as MapData
		var stream: AudioStream = null
		var loop_start: float = 0.0
		var loop_end: float = -1.0
		if priority == PriorityLevel.ESCAPE and map_data and map_data.final_phase_music:
			stream = map_data.final_phase_music
			loop_start = map_data.final_phase_loop_start
			loop_end = map_data.final_phase_loop_end
		if stream:
			var s := _configure_stream_loop(stream, loop_start, loop_end, true)
			lms_music_player.stream = s
			_final_loop_start = maxf(loop_start, 0.0)
			_final_loop_end = loop_end
			lms_music_player.volume_db = MAX_DB
			lms_music_player.play()
		else:
			_final_loop_start = 0.0
			_final_loop_end = -1.0

# =======================================================================
# CHASE VARIANT
# =======================================================================
func set_last_life_chase_stream(stream: AudioStream) -> void:
	var s := _configure_stream_loop(stream, 0.0, -1.0, true) if stream else null
	_chase_stream_last_life = s

func set_chase_variant(variant: int) -> void:
	_chase_variant = variant
	if chase_music_player:
		if variant == ChaseVariantType.LAST_LIFE and _chase_stream_last_life:
			chase_music_player.stream = _chase_stream_last_life
		elif variant == ChaseVariantType.NORMAL and _chase_stream_normal:
			chase_music_player.stream = _chase_stream_normal

# =======================================================================
# RPCs (LMS)
# =======================================================================
@rpc("any_peer", "call_local", "reliable")
func _rpc_activate_lms_audio(survivor_peer_id: int) -> void:
	var survivor_node = _find_player_node_by_peer_id(survivor_peer_id)
	if is_instance_valid(survivor_node) and "character_data" in survivor_node:
		var char_data = survivor_node.character_data
		if char_data and char_data.lms_music:
			# LMS no loopea por diseño (false), configurar sin loop
			var s := _configure_stream_loop(char_data.lms_music, 0.0, -1.0, false)
			lms_music_player.stream = s
	_current_priority = PriorityLevel.LMS
	lms_bloqueo_activo = true
	if terror_music_player and terror_music_player.playing: terror_music_player.stop()
	if chase_music_player and chase_music_player.playing: chase_music_player.stop()
	if map_music_player and map_music_player.playing: map_music_player.stop()
	if lms_music_player and lms_music_player.stream:
		lms_music_player.volume_db = MAX_DB
		lms_music_player.play()

@rpc("any_peer", "call_local", "reliable")
func _rpc_deactivate_lms_audio() -> void:
	_current_priority = PriorityLevel.NONE
	lms_bloqueo_activo = false
	if lms_music_player.playing:
		lms_music_player.stop()
	lms_music_player.stream = null
	
@rpc("authority", "call_local", "reliable")
func play_sfx_on_peer(sfx_id: int, x: float, y: float) -> void:
	play_sfx(sfx_id, Vector2(x, y))

# =======================================================================
# RPCs (RAGE — ultimate de Jevil)
# Reutiliza lms_music_player con prioridad SPECIAL. El guard de
# desactivación evita pisar la música del LMS si éste canceló el Rage.
# =======================================================================
## Tema del ultimate. Si cambias la música, ajusta también
## RAGE_DURATION en abilities/jevil/Rage/Rage.gd.
const RAGE_MUSIC_PATH := "res://Characters/Jevil/assets/Music/THE WORLD REVOLVING.mp3"

@rpc("any_peer", "call_local", "reliable")
func _rpc_activate_rage_music() -> void:
	var stream := load(RAGE_MUSIC_PATH) as AudioStream
	if stream == null:
		push_warning("[AudioManager] Música del Rage no encontrada: ", RAGE_MUSIC_PATH)
		return
	# Guardar si estábamos en ESCAPE para restaurar condicional (Rage no siempre en escape)
	_priority_before_special = _current_priority
	_escape_was_active = (_current_priority == PriorityLevel.ESCAPE)
	var s := _configure_stream_loop(stream, 0.0, -1.0, false)
	if map_music_player and map_music_player.playing:
		map_music_player.stop()
	if terror_music_player and terror_music_player.playing:
		terror_music_player.stop()
	if chase_music_player and chase_music_player.playing:
		chase_music_player.stop()
	if lms_music_player and lms_music_player.playing:
		lms_music_player.stop()
	lms_music_player.stream = s
	lms_music_player.volume_db = MAX_DB
	lms_music_player.play()
	_current_priority = PriorityLevel.SPECIAL


@rpc("any_peer", "call_local", "reliable")
func _rpc_deactivate_rage_music() -> void:
	if _current_priority != PriorityLevel.SPECIAL:
		return
	var was_escape := _escape_was_active
	_escape_was_active = false
	_priority_before_special = PriorityLevel.NONE
	_current_priority = PriorityLevel.NONE
	if lms_music_player.playing:
		lms_music_player.stop()
	lms_music_player.stream = null
	# Restore condicional: si la fase escape sigue activa al terminar Rage, volver a final_phase_music
	# (Rage no siempre está en escape — respetar tu acotación: solo restaurar si final_phase_triggered)
	var mec = GameServiceLocator.map_event_coordinator
	var should_restore_escape: bool = was_escape or (mec != null and mec._final_phase_triggered)
	if should_restore_escape and mec != null and mec._final_phase_triggered:
		# LMS tiene prioridad mayor (3) que ESCAPE (1) — si queda 1 vivo, LMS debe sonar en vez de escape
		var alive_count := 0
		for s in get_tree().get_nodes_in_group("survivor"):
			if "health_state" in s and s.health_state == "alive":
				alive_count += 1
		if alive_count <= 1 and lms_music_player and lms_music_player.stream:
			_restore_base()
			return
		_start_priority_stream(PriorityLevel.ESCAPE)
		if lms_music_player.stream and lms_music_player.playing:
			return
	# Caso normal (Rage en PLAYING o sin fase final): restaurar base (LMS si corresponde sino map_bgm)
	_restore_base()

# =======================================================================
# HELPERS
# =======================================================================
func play_menu_drone(path: String = "") -> void:
	if path == "":
		var tm := get_node_or_null("/root/ThemeManager")
		if tm and tm.has_method("get_music_path"):
			path = tm.get_music_path()
		else:
			path = "res://ui/Boot/scenes/AUDIO_DRONE.wav"
	var s := load(path) as AudioStream
	if s == null:
		push_warning("[AudioManager] AUDIO_DRONE no encontrado: ", path)
		return
	s = _configure_stream_loop(s, 0.0, -1.0, true)
	if menu_music_player:
		if menu_music_player.playing:
			menu_music_player.stop()
		menu_music_player.stream = s
		menu_music_player.volume_db = MAX_DB
		# Aplicar volumen actual de SettingsManager al nuevo bus dedicado
		var sm := get_node_or_null("/root/SettingsManager")
		if sm and "music_volume" in sm:
			var idx := AudioServer.get_bus_index(&"Menu Music")
			if idx != -1:
				# Menu Music -> Master, replicamos volumen de Music para respetar slider
				AudioServer.set_bus_volume_db(idx, linear_to_db(float(sm.music_volume)))
		menu_music_player.play()
		change_audio_state("menu_drone")

func stop_menu_drone() -> void:
	if menu_music_player and menu_music_player.playing:
		menu_music_player.stop()
	if current_global_state == "menu_drone":
		current_global_state = "menu"

func _restore_base() -> void:
	var alive_count := 0
	for s in get_tree().get_nodes_in_group("survivor"):
		if "health_state" in s and s.health_state == "alive":
			alive_count += 1
	if alive_count <= 1 and lms_music_player and lms_music_player.stream:
		activate_lms_audio()
	else:
		lms_bloqueo_activo = false
		_current_priority = PriorityLevel.NONE
		if lms_music_player.playing:
			lms_music_player.stop()
		if map_music_player and map_music_player.stream and not map_music_player.playing:
			map_music_player.play()
			map_music_player.volume_db = MAX_DB

func _silence_all_match_audio(delta: float) -> void:
	if current_global_state == "menu_drone":
		return
	lms_bloqueo_activo = false
	_smooth_fade(map_music_player, MIN_DB, delta)
	_smooth_fade(terror_music_player, MIN_DB, delta)
	_smooth_fade(chase_music_player, MIN_DB, delta)
	_smooth_fade(lms_music_player, MIN_DB, delta)
	# Menu Music es canal dedicado -> nunca fadear aquí

func _find_player_node_by_peer_id(peer_id: int) -> Node:
	for group_name in ["survivor", "killer"]:
		for player in get_tree().get_nodes_in_group(group_name):
			if player.name == str(peer_id):
				return player
	return null

func update_proximities(_d = null) -> void:
	if is_instance_valid(cached_local_player):
		_update_proximities(cached_local_player, 0.016)

func _set_lms_stream(stream: AudioStream) -> void:
	lms_music_player.stream = stream
	if stream and "loop" in stream:
		stream.loop = false
