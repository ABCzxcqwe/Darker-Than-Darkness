# res://services/GameStateService.gd
# State machine del match: INTRO → PLAYING → ENDED
extends Node

enum State { INTRO, PLAYING, ENDED }

signal state_changed(new_state: State, old_state: State)

var current_state: State = State.INTRO : set = _set_state

const BASE_TIME := 90.0
const TIME_PER_SURVIVOR := 30.0

var _health_service: Node = null
var _timer_service: Node = null
var _lms_service: Node = null
var _ending_sequence_started := false


func _ready() -> void:
	if not multiplayer.is_server():
		return
	NetworkManager.player_left.connect(_on_network_player_left)


func _connect_services() -> void:
	_health_service = GameServiceLocator.get_service("HealthService")
	_timer_service = GameServiceLocator.get_service("TimerService")
	_lms_service = GameServiceLocator.get_service("LMSService")

	if _health_service:
		_health_service.survivor_died_permanently.connect(_on_survivor_death)
	if _timer_service:
		_timer_service.timeout.connect(_on_timer_timeout)


func _set_state(new: State) -> void:
	var old = current_state
	current_state = new
	state_changed.emit(new, old)


func is_in_game() -> bool:
	return current_state == State.PLAYING


func transition_to_playing() -> void:
	_connect_services()
	_set_state(State.PLAYING)
	_setup_map_audio()
	_start_timer()
	_evaluate_match()


func transition_to_ended(reason: String) -> void:
	_set_state(State.ENDED)
	_cleanup_match_audio()
	_calculate_killer_points(reason)
	_go_to_stats(reason)


# ─── AUDIO ────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _rpc_setup_map_audio(map_id: String) -> void:
	AudioManager.setup_map_audio(map_id)
	var killer_node: Node2D = _find_killer_node()
	var survivor_node: Node2D = _find_any_survivor_node()
	var terror_r: float = killer_node.character_data.terror_radius if killer_node and killer_node.character_data else 400.0
	var chase_r: float  = killer_node.character_data.chase_radius  if killer_node and killer_node.character_data else 200.0
	AudioManager.set_killer_config(terror_r, chase_r)
	var terror_stream: AudioStream = killer_node.character_data.terror_music if killer_node else null
	var chase_stream: AudioStream  = killer_node.character_data.chase_music  if killer_node else null
	var lms_stream: AudioStream    = survivor_node.character_data.lms_music if survivor_node else null
	AudioManager.register_match_character_music(terror_stream, chase_stream, lms_stream)


func _setup_map_audio() -> void:
	if not multiplayer.is_server():
		return
	rpc("_rpc_setup_map_audio", GameData.selected_map)


func _cleanup_match_audio() -> void:
	AudioManager.reset_match_audio()


# ─── TIMER ───────────────────────────────────────────────

func _start_timer() -> void:
	if not multiplayer.is_server():
		return
	var survivor_count := 0
	for pid in NetworkManager.players:
		if NetworkManager.players[pid]["assigned_role"] == "survivor":
			survivor_count += 1
	var initial_time = BASE_TIME + (survivor_count * TIME_PER_SURVIVOR)
	_timer_service.start_timer(initial_time)


func _on_timer_timeout() -> void:
	if current_state != State.PLAYING:
		return
	if _lms_service and _lms_service.is_lms_active():
		_lms_service.stop_lms()
	transition_to_ended("survivors_escaped")


# ─── DEATH ───────────────────────────────────────────────

func _on_survivor_death(peer_id: int) -> void:
	if current_state != State.PLAYING:
		return
	_timer_service.modify_time(15.0)
	_evaluate_match()


# ─── DISCONNECT ──────────────────────────────────────────

# Llamado por señal NetworkManager.player_left (el jugador ya fue borrado del diccionario)
# Solo usamos esto para cleanup de servicios, no para lógica de partida.
func _on_network_player_left(peer_id: int) -> void:
	_unregister_player_services(peer_id)


# Llamado directamente por NetworkManager con el rol capturado ANTES de borrar al jugador
func handle_player_disconnect(peer_id: int, abandoned_role: String) -> void:
	if current_state != State.PLAYING:
		return

	if abandoned_role == "killer":
		_timer_service.stop_timer()
		transition_to_ended("killer_disconnected")
	elif abandoned_role == "survivor":
		_timer_service.modify_time(10.0)
		if _lms_service and _lms_service.is_lms_active() and _lms_service.get_active_survivor() \
				and _lms_service.get_active_survivor().get_multiplayer_authority() == peer_id:
			_lms_service.stop_lms()
		_evaluate_match()


func _unregister_player_services(peer_id: int) -> void:
	var tp = GameServiceLocator.get_service("TPService")
	if tp and tp.has_method("unregister_player"):
		tp.unregister_player(peer_id)
	var evo = GameServiceLocator.get_service("EvolutionService")
	if evo and evo.has_method("unregister_player"):
		evo.unregister_player(peer_id)
	var cd = GameServiceLocator.get_service("CooldownService")
	if cd and cd.has_method("clear_player"):
		cd.clear_player(peer_id)


# ─── EVALUATE ────────────────────────────────────────────

func _evaluate_match() -> void:
	var alive = _count_alive_survivors()
	if alive == 0:
		_timer_service.stop_timer()
		transition_to_ended("killer_elimination")
	elif alive == 1:
		var survivor = _find_last_survivor()
		var killer = _find_killer_node()
		if survivor and _lms_service:
			_lms_service.start_lms(survivor, killer)


func _count_alive_survivors() -> int:
	var count := 0
	for pid in NetworkManager.players:
		if NetworkManager.players[pid]["assigned_role"] == "survivor":
			if _health_service and not _health_service.is_dead(pid):
				count += 1
	return count


func _find_last_survivor() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if "character_data" in p and p.character_data and p.character_data.team == "survivor":
			if not _health_service.is_dead(p.get_multiplayer_authority()):
				return p
	return null


func _find_killer_node() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if "character_data" in p and p.character_data and p.character_data.team == "killer":
			return p
	return null


func _find_any_survivor_node() -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if "character_data" in p and p.character_data and p.character_data.team == "survivor":
			return p
	return null


# ─── SUDDEN DEATH ────────────────────────────────────────

func evaluate_sudden_death_condition() -> void:
	if current_state != State.PLAYING or _ending_sequence_started:
		return
	if _health_service and _health_service.check_all_survivors_incapacitated():
		_ending_sequence_started = true
		await get_tree().create_timer(3.0).timeout
		if _health_service.check_all_survivors_incapacitated():
			_timer_service.stop_timer()
			transition_to_ended("killer_elimination")
		else:
			_ending_sequence_started = false


# ─── END MATCH ───────────────────────────────────────────

func _calculate_killer_points(reason: String) -> void:
	for pid in NetworkManager.players:
		if not NetworkManager.players.has(pid):
			continue
		var role = NetworkManager.players[pid]["assigned_role"]
		if reason == "survivors_escaped":
			NetworkManager.players[pid]["killer_points"] += 10 if role == "survivor" else 40
		elif reason == "killer_elimination":
			NetworkManager.players[pid]["killer_points"] += 5 if role == "killer" else 25


func _go_to_stats(reason: String) -> void:
	var final_time := 0.0
	if _timer_service:
		final_time = _timer_service.time_left
	var stats_data := {
		"end_reason": reason,
		"time_left": final_time,
		"players_snapshot": NetworkManager.players.duplicate(true)
	}
	MatchCoordinator.rpc("_go_to_stats_screen", stats_data)
