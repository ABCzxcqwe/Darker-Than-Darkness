# core/ClientRelay.gd
# Hijo permanente de GameServiceLocator. Existe en todos los peers.
# Recibe RPCs del servidor y emite señales para la UI.
# NO contiene lógica de juego — solo relay de estado.
extends Node

# ── Señales ──────────────────────────────────────────────────────────
signal timer_changed(current_time: float)
signal timer_timeout()

signal health_changed(peer_id: int, current_hp: int, max_hp: int)
signal player_state_changed(peer_id: int, state: String)
signal survivor_died_permanently(peer_id: int)

signal stamina_changed(peer_id: int, current_stamina: float, max_stamina: float)

signal tp_changed(peer_id: int, current_tp: float, max_tp: float)
signal dynamic_tp_cost_changed(slot_index: int, cost: float)

signal slot_evolved(slot_index: int, stage: int)
signal slot_devolved(slot_index: int)

signal arrow_spawned(arrow_id: int, type: int, target_pos: Vector2, track_peer: int, filter_peer: int, duration: float)
signal arrow_despawned(arrow_id: int)

signal damage_number_spawned(peer_id: int, amount: int, pos_x: float, pos_y: float, rng_seed: int, dir_sign: float, color: Color)

signal revive_started(rescuer_id: int, target_id: int, duration: float)
signal revive_cancelled(rescuer_id: int, target_id: int)
signal revive_completed(rescuer_id: int, target_id: int)

signal lms_state_changed(threshold: float)
signal lms_ended_state()
signal escaped_players_changed(escaped: Array[int])
signal game_state_changed(new_state: int, old_state: int)

signal effect_applied(peer_id: int, effect_name: String, duration: float)
signal effect_removed(peer_id: int, effect_name: String)

signal dialog_notification(message: String, type: int)

signal camera_shake(intensity: float, duration: float)


# ── Estado (lectura síncrona para UI) ────────────────────────────────
var time_left: float = 0.0
var _evolved_slots: Dictionary = {}  # peer_id -> [bool, bool, bool, bool, bool]
var _escaped_players: Array[int] = []
var _stamina_cache: Dictionary = {}  # { peer_id: { "current": float, "max": float } }


# ── RPCs ─────────────────────────────────────────────────────────────

## Timer
@rpc("authority", "unreliable", "call_local")
func _sync_time_client(server_time: float) -> void:
	time_left = server_time
	timer_changed.emit(server_time)


@rpc("authority", "reliable")
func _sync_timeout() -> void:
	timer_timeout.emit()


## Health
@rpc("authority", "reliable", "call_local")
func _sync_global_health(peer_id: int, current_hp: int, max_hp: int, state: String) -> void:
	health_changed.emit(peer_id, current_hp, max_hp)
	player_state_changed.emit(peer_id, state)


@rpc("authority", "reliable", "call_local")
func _sync_survivor_died(peer_id: int) -> void:
	survivor_died_permanently.emit(peer_id)


## Cooldown
@rpc("authority", "call_local", "reliable")
func _rpc_cooldown_state(slot_index: int, duration: float) -> void:
	var huds = get_tree().get_nodes_in_group("game_hud")
	if huds.is_empty():
		for i in range(3):
			await get_tree().process_frame
			huds = get_tree().get_nodes_in_group("game_hud")
			if not huds.is_empty():
				break
	if huds.is_empty():
		return
	var hud = huds[0]
	if not hud.has_method("on_cooldown_state_changed"):
		return
	hud.on_cooldown_state_changed(slot_index, duration)


## Evolution
@rpc("authority", "call_local", "reliable")
func _rpc_evolve_slot(slot_index: int, stage: int) -> void:
	var peer_id = multiplayer.get_unique_id()
	if not _evolved_slots.has(peer_id):
		_evolved_slots[peer_id] = [0, 0, 0, 0, 0]
	if slot_index >= 0 and slot_index < 5:
		_evolved_slots[peer_id][slot_index] = stage

	if stage > 0:
		slot_evolved.emit(slot_index, stage)
	else:
		slot_devolved.emit(slot_index)


@rpc("authority", "call_local", "reliable")
func _rpc_tp_ready(slot_index: int, is_ready: bool) -> void:
	var huds = get_tree().get_nodes_in_group("game_hud")
	if huds.is_empty():
		return
	var hud = huds[0]
	if hud.has_method("visual_tp_ready"):
		hud.visual_tp_ready(slot_index, is_ready)


## Radar
@rpc("authority", "call_local", "reliable")
func _rpc_add_arrow(arrow_id: int, type: int, target_x: float, target_y: float, track_peer: int, filter_peer: int, duration: float) -> void:
	arrow_spawned.emit(arrow_id, type, Vector2(target_x, target_y), track_peer, filter_peer, duration)


@rpc("authority", "call_local", "reliable")
func _rpc_remove_arrow(arrow_id: int) -> void:
	arrow_despawned.emit(arrow_id)


## Damage Numbers
@rpc("authority", "call_local", "reliable")
func _rpc_add_damage_number(peer_id: int, amount: int, pos_x: float, pos_y: float, rng_seed: int, dir_sign: float, color: Color) -> void:
	damage_number_spawned.emit(peer_id, amount, pos_x, pos_y, rng_seed, dir_sign, color)


## Revive
@rpc("authority", "call_local", "reliable")
func _notify_revive_started(rescuer_id: int, target_id: int, duration: float) -> void:
	revive_started.emit(rescuer_id, target_id, duration)


@rpc("authority", "call_local", "reliable")
func _notify_revive_cancelled(rescuer_id: int, target_id: int) -> void:
	revive_cancelled.emit(rescuer_id, target_id)


@rpc("authority", "call_local", "reliable")
func _notify_revive_completed(rescuer_id: int, target_id: int) -> void:
	revive_completed.emit(rescuer_id, target_id)


## Map Event
@rpc("authority", "call_local", "reliable")
func _sync_lms_state(threshold: float) -> void:
	lms_state_changed.emit(threshold)


@rpc("authority", "call_local", "reliable")
func _sync_lms_ended() -> void:
	lms_ended_state.emit()


## Audio
@rpc("authority", "call_local", "reliable")
func _sync_game_state(new_state: int, old_state: int) -> void:
	game_state_changed.emit(new_state, old_state)


@rpc("authority", "call_local", "reliable")
func _sync_escaped_players(escaped: Array[int]) -> void:
	_escaped_players = escaped
	escaped_players_changed.emit(_escaped_players)


## Status Effect Notifications
@rpc("authority", "call_local", "reliable")
func _rpc_effect_applied(peer_id: int, effect_name: String, duration: float) -> void:
	effect_applied.emit(peer_id, effect_name, duration)


@rpc("authority", "call_local", "reliable")
func _rpc_effect_removed(peer_id: int, effect_name: String) -> void:
	effect_removed.emit(peer_id, effect_name)


@rpc("authority", "reliable", "call_local")
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


## Stamina
@rpc("authority", "call_local", "reliable")
func sync_stamina_to_client(peer_id: int, current_stamina: float, max_stamina: float) -> void:
	_stamina_cache[peer_id] = { "current": current_stamina, "max": max_stamina }
	stamina_changed.emit(peer_id, current_stamina, max_stamina)


## TP
@rpc("authority", "call_local", "reliable")
func sync_tp_to_client(peer_id: int, current_tp: float, max_tp: float) -> void:
	tp_changed.emit(peer_id, current_tp, max_tp)


## Dynamic TP cost (for scalable abilities like Ultimate Heal)
@rpc("authority", "call_local", "reliable")
func _rpc_dynamic_tp_cost(slot_index: int, cost: float) -> void:
	dynamic_tp_cost_changed.emit(slot_index, cost)


## Dialog Notifications
@rpc("authority", "call_local", "reliable")
func _rpc_push_dialog(message: String, type: int = 0) -> void:
	dialog_notification.emit(message, type)


@rpc("authority", "call_local", "reliable")
func _rpc_camera_shake(intensity: float, duration: float) -> void:
	camera_shake.emit(intensity, duration)


# ── Internos ──────────────────────────────────────────────────────────
func _find_killer_node() -> Node2D:
	var killers = get_tree().get_nodes_in_group("killer")
	if killers.is_empty():
		return null
	return killers[0] as Node2D


func _find_any_survivor_node() -> Node2D:
	var survivors = get_tree().get_nodes_in_group("survivor")
	if survivors.is_empty():
		return null
	return survivors[0] as Node2D


# ── API Pública ──────────────────────────────────────────────────────

func has_player_escaped(peer_id: int) -> bool:
	return peer_id in _escaped_players


func is_evolved(peer_id: int, slot_index: int) -> bool:
	return get_evolved_stage(peer_id, slot_index) > 0


## Etapa actual de evolución del slot (0 = base, 1 = primera evolución, ...).
func get_evolved_stage(peer_id: int, slot_index: int) -> int:
	var slots = _evolved_slots.get(peer_id)
	if slots == null:
		return 0
	if slot_index < 0 or slot_index >= slots.size():
		return 0
	return slots[slot_index]


func get_stamina(peer_id: int) -> Dictionary:
	return _stamina_cache.get(peer_id, { "current": 0.0, "max": 0.0 })


func reset_state() -> void:
	time_left = 0.0
	_evolved_slots.clear()
	_escaped_players.clear()
	_stamina_cache.clear()
