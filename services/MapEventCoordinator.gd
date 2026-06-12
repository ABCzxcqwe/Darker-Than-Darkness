extends Node

signal exit_activated(exit_id: String)
signal exit_deactivated(exit_id: String)
signal player_escaped(peer_id: int, exit_id: String)
signal phase_event_triggered(event_id: String)

@export var lms_exits_to_open: int = 1

var _map_node: BaseMap = null
var _exits: Dictionary = {}
var _triggers: Dictionary = {}
var _spawn_points: Dictionary = {}
var _phase_events: Array[MapPhaseEvent] = []
var _escaped_players: Array[int] = []
var _timer_service: Node = null
var _health_service: Node = null
var _game_state: Node = null
var _lms_active: bool = false
var _lms_exit_threshold: float = 0.0
var _lms_exits_opened: bool = false
var _exit_arrows: Dictionary = {}


# ── Lifecycle ─────────────────────────────────────────────

func _ready() -> void:
	_connect_services()


func _connect_services() -> void:
	_timer_service = GameServiceLocator.get_service("TimerService")
	_health_service = GameServiceLocator.get_service("HealthService")
	_game_state = GameServiceLocator.get_service("GameStateService")
	if _timer_service and _timer_service.has_signal("timer_changed"):
		_timer_service.timer_changed.connect(_on_timer_changed)

	var lms = GameServiceLocator.get_service("LMSService")
	if lms:
		if lms.has_signal("lms_activated"):
			lms.lms_activated.connect(_on_lms_activated)
		if lms.has_signal("lms_ended"):
			lms.lms_ended.connect(_on_lms_ended)


# ── LMS ────────────────────────────────────────────────────

func _on_lms_activated(survivor_node: Node, _killer_node: Node, _duration: float) -> void:
	if not multiplayer.is_server():
		return
	var threshold = _get_lms_exit_threshold(survivor_node)
	rpc("_sync_lms_state", threshold)


@rpc("authority", "call_local", "reliable")
func _sync_lms_state(threshold: float) -> void:
	_lms_active = true
	_lms_exits_opened = false
	_lms_exit_threshold = threshold
	_close_non_lms_exits()
	_check_lms_exit_condition()


func _on_lms_ended() -> void:
	if not multiplayer.is_server():
		return
	rpc("_sync_lms_ended")


@rpc("authority", "call_local", "reliable")
func _sync_lms_ended() -> void:
	_lms_active = false
	_lms_exits_opened = false


func _get_lms_exit_threshold(survivor_node: Node) -> float:
	if not survivor_node:
		return 0.0
	var data = survivor_node.get("character_data") if "character_data" in survivor_node else null
	if not data:
		return 0.0
	return data.lms_exit_timer_threshold


func _check_lms_exit_condition() -> void:
	if _lms_exit_threshold <= 0.0:
		return
	if _timer_service and _timer_service.time_left <= _lms_exit_threshold:
		_open_random_lms_exits()
		_lms_exits_opened = true


func _close_non_lms_exits() -> void:
	for exit_id in _exits:
		var exit = _exits[exit_id]
		if exit.is_active and not exit.open_during_lms:
			deactivate_exit(exit_id)


func _open_random_lms_exits() -> void:
	var pool: Array[String] = []
	for exit_id in _exits:
		var exit = _exits[exit_id]
		if not exit.is_active and exit.open_during_lms:
			pool.append(exit_id)

	if pool.is_empty():
		pool = _get_inactive_exits()

	pool.shuffle()
	var to_open = mini(lms_exits_to_open, pool.size())
	for i in to_open:
		activate_exit(pool[i])


func _get_inactive_exits() -> Array[String]:
	var result: Array[String] = []
	for exit_id in _exits:
		if not _exits[exit_id].is_active:
			result.append(exit_id)
	return result


# ── Setup (llamado por World tras cargar el mapa) ────────

func setup(map_node: BaseMap) -> void:
	_map_node = map_node
	_scan_map_events()


func _scan_map_events() -> void:
	if not _map_node:
		return
	_exits.clear()
	_triggers.clear()
	_spawn_points.clear()
	_phase_events.clear()

	_scan_children(_map_node)

	print("[MapEventCoordinator] Exits: ", _exits.keys(),
		" | Triggers: ", _triggers.keys(),
		" | SpawnPoints: ", _spawn_points.keys(),
		" | PhaseEvents: ", _phase_events.size())


func _scan_children(node: Node) -> void:
	for child in node.get_children():
		if child is MapExit:
			_exits[child.exit_id] = child
			child.deactivate()
			child.body_entered.connect(_on_player_entered_exit.bind(child.exit_id))
		elif child is MapTrigger:
			_triggers[child.trigger_id] = child
		elif child is MapSpawnPoint:
			_spawn_points[child.spawn_id] = child
		elif child is MapPhaseEvent:
			_phase_events.append(child)
			if child.activate_on_start:
				_execute_action(child)
				child.has_fired = true

		_scan_children(child)


# ── Phase Events ──────────────────────────────────────────

func _on_timer_changed(current_time: float) -> void:
	_evaluate_phase_events()
	if _lms_active and not _lms_exits_opened:
		_check_lms_exit_condition()


func _evaluate_phase_events() -> void:
	for event in _phase_events:
		if event.has_fired and event.one_shot:
			continue
		if not _check_condition(event):
			continue
		_execute_action(event)
		event.has_fired = true
		phase_event_triggered.emit(event.event_id)


func _check_condition(event: MapPhaseEvent) -> bool:
	match event.condition:
		MapPhaseEvent.ConditionType.TIME_REMAINING:
			return _timer_service != null \
				and _timer_service.time_left <= event.condition_value
		MapPhaseEvent.ConditionType.SURVIVORS_ALIVE:
			var alive = _count_alive_survivors()
			return alive <= event.condition_value
		MapPhaseEvent.ConditionType.LMS_ACTIVE:
			var lms = GameServiceLocator.get_service("LMSService")
			return lms != null and lms.is_lms_active()
		MapPhaseEvent.ConditionType.ALWAYS:
			return true
	return false


func _execute_action(event: MapPhaseEvent) -> void:
	match event.action:
		MapPhaseEvent.ActionType.ACTIVATE_EXIT:
			activate_exit(event.action_target)
		MapPhaseEvent.ActionType.DEACTIVATE_EXIT:
			deactivate_exit(event.action_target)
		MapPhaseEvent.ActionType.ACTIVATE_TRIGGER:
			_activate_trigger(event.action_target)
		MapPhaseEvent.ActionType.DEACTIVATE_TRIGGER:
			_deactivate_trigger(event.action_target)
		MapPhaseEvent.ActionType.PLAY_EFFECT:
			_play_effect(event.action_target)
		MapPhaseEvent.ActionType.SET_AMBIENT:
			_set_ambient(event.action_target)
		MapPhaseEvent.ActionType.CALL_CUSTOM:
			_call_custom_event(event)


# ── Exit Management ───────────────────────────────────────

func activate_exit(exit_id: String) -> void:
	if not _exits.has(exit_id):
		push_warning("[MapEventCoordinator] Exit '", exit_id, "' no encontrado.")
		return
	var exit = _exits[exit_id]
	if _lms_active and not exit.open_during_lms:
		return
	exit.activate()
	exit_activated.emit(exit_id)
	if multiplayer.is_server():
		var radar = GameServiceLocator.get_service("RadarService")
		if radar and not _exit_arrows.has(exit_id):
			var arrow_id = radar.show_map_indicator(exit.global_position)
			if arrow_id >= 0:
				_exit_arrows[exit_id] = arrow_id
	print("[MapEventCoordinator] Exit '", exit_id, "' activado.")


func deactivate_exit(exit_id: String) -> void:
	if not _exits.has(exit_id):
		return
	_exits[exit_id].deactivate()
	exit_deactivated.emit(exit_id)
	if multiplayer.is_server() and _exit_arrows.has(exit_id):
		var radar = GameServiceLocator.get_service("RadarService")
		if radar:
			radar.remove_map_indicator(_exit_arrows[exit_id])
		_exit_arrows.erase(exit_id)


func is_near_active_exit(player_pos: Vector2) -> bool:
	for exit_id in _exits:
		var exit = _exits[exit_id]
		if exit.is_active and exit.is_nearby(player_pos):
			return true
	return false


func get_nearby_exit_id(player_pos: Vector2) -> String:
	for exit_id in _exits:
		var exit = _exits[exit_id]
		if exit.is_active and exit.is_nearby(player_pos):
			return exit_id
	return ""


func get_active_exits() -> Array[String]:
	var active: Array[String] = []
	for exit_id in _exits:
		if _exits[exit_id].is_active:
			active.append(exit_id)
	return active


# ── Escape (automático al colisionar) ─────────────────────

func _on_player_entered_exit(body: Node, exit_id: String) -> void:
	if not multiplayer.is_server():
		return
	if not body.is_in_group("players"):
		return
	var exit = _exits.get(exit_id)
	if not exit or not exit.is_active:
		return
	var peer_id = body.get_multiplayer_authority()
	if peer_id < 0:
		return
	if NetworkManager.players.get(peer_id, {}).get("assigned_role") != "survivor":
		return
	_process_escape(peer_id, exit_id)


func _process_escape(peer_id: int, exit_id: String) -> void:
	if _game_state and _game_state.current_state != _game_state.State.PLAYING:
		return
	if peer_id in _escaped_players:
		return
	if _health_service and _health_service.is_dead(peer_id):
		return

	var player = _find_player(peer_id)
	if not player:
		return

	_escaped_players.append(peer_id)
	player_escaped.emit(peer_id, exit_id)
	print("[MapEventCoordinator] Jugador ", peer_id, " escapó por '", exit_id, "'.")

	if player.has_method("_sync_escape"):
		player.rpc("_sync_escape")

	if _game_state:
		_check_match_end()


func _check_match_end() -> void:
	var total_survivors := 0
	var escaped_count := 0
	for pid in NetworkManager.players:
		if NetworkManager.players[pid]["assigned_role"] != "survivor":
			continue
		total_survivors += 1
		if pid in _escaped_players:
			escaped_count += 1
			continue
		var dead = _health_service and _health_service.is_dead(pid)
		print("[MapEventCoordinator] _check_match_end: pid=", pid, " dead=", dead, " escaped=false")
		if not dead:
			return

	print("[MapEventCoordinator] _check_match_end: COMPLETO -> escaped=", escaped_count, "/", total_survivors)
	if _game_state:
		_game_state.transition_to_ended("survivors_escaped", {
			"escaped_count": escaped_count,
			"total_survivors": total_survivors
		})


# ── Trigger Management ────────────────────────────────────

func _activate_trigger(trigger_id: String) -> void:
	if not _triggers.has(trigger_id):
		return
	_triggers[trigger_id].monitoring = true


func _deactivate_trigger(trigger_id: String) -> void:
	if not _triggers.has(trigger_id):
		return
	_triggers[trigger_id].monitoring = false


# ── Spawn Points ──────────────────────────────────────────

func spawn_at_point(spawn_id: String, parent: Node = null) -> Node:
	if not _spawn_points.has(spawn_id):
		return null
	var instance = _spawn_points[spawn_id].spawn_random()
	if instance and parent:
		parent.add_child(instance)
	elif instance and _map_node:
		_map_node.add_child(instance)
	return instance


func get_spawn_point_position(spawn_id: String) -> Vector2:
	if _spawn_points.has(spawn_id):
		return _spawn_points[spawn_id].global_position
	return Vector2.ZERO


# ── Effects / Ambiente (placeholders para futuro) ─────────

func _play_effect(effect_name: String) -> void:
	print("[MapEventCoordinator] Efecto '", effect_name, "' solicitado (sin implementar).")


func _set_ambient(ambient_name: String) -> void:
	print("[MapEventCoordinator] Ambiente '", ambient_name, "' solicitado (sin implementar).")


func _call_custom_event(event: MapPhaseEvent) -> void:
	print("[MapEventCoordinator] Evento custom '", event.event_id, "' (sin implementar).")


# ── Helpers ───────────────────────────────────────────────

func _find_player(peer_id: int) -> Node:
	for player in get_tree().get_nodes_in_group("players"):
		if player.get_multiplayer_authority() == peer_id:
			return player
	return null


func _count_alive_survivors() -> int:
	var count := 0
	for pid in NetworkManager.players:
		if NetworkManager.players[pid]["assigned_role"] == "survivor":
			if _health_service and not _health_service.is_dead(pid):
				count += 1
	return count


func has_player_escaped(peer_id: int) -> bool:
	return peer_id in _escaped_players


func get_escaped_count() -> int:
	return _escaped_players.size()


func _register_escaped(peer_id: int) -> void:
	if not peer_id in _escaped_players:
		_escaped_players.append(peer_id)


func clear() -> void:
	_exits.clear()
	_triggers.clear()
	_spawn_points.clear()
	_phase_events.clear()
	_escaped_players.clear()
	_exit_arrows.clear()
	_lms_active = false
	_lms_exits_opened = false
	_lms_exit_threshold = 0.0
	_map_node = null
