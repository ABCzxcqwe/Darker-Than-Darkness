# res://Network/replication/client_relay.gd
extends Node
## Hijo permanente de GameServiceLocator. Existe en todos los peers.
## Recibe RPCs del servidor y emite señales para la UI.
## El estado de lectura vive en ClientState; este nodo solo transporta y emite.

signal timer_changed(current_time: float)
signal timer_timeout()

signal health_changed(peer_id: int, current_hp: int, max_hp: int)
signal player_state_changed(peer_id: int, state: String)
signal survivor_died_permanently(peer_id: int)

signal stamina_changed(peer_id: int, current_stamina: float, max_stamina: float)

signal tp_changed(peer_id: int, current_tp: float, max_tp: float)
signal dynamic_tp_cost_changed(slot_index: int, cost: float)
signal ability_slot_updated(slot_index: int, tp_cost: float, cooldown: float, stage: int)

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

signal rage_state_changed(charged: bool, progress: int, required: int)
signal rage_time_changed(caster_id: int, remaining: float)

signal dialog_notification(message: String, type: int)

signal camera_shake(intensity: float, duration: float)

signal stats_received(stats: Dictionary)

var _state := ClientState.new()


## Compatibilidad con lecturas existentes de `relay.time_left`.
var time_left: float:
	get:
		return _state.time_left
	set(value):
		_state.time_left = value


func get_state() -> ClientState:
	return _state


# ── Timer ────────────────────────────────────────────────────────────

@rpc("authority", "unreliable", "call_local")
func _sync_time_client(server_time: float) -> void:
	_state.time_left = server_time
	timer_changed.emit(server_time)


@rpc("authority", "reliable")
func _sync_timeout() -> void:
	timer_timeout.emit()


# ── Health ───────────────────────────────────────────────────────────

@rpc("authority", "reliable", "call_local")
func _sync_global_health(peer_id: int, current_hp: int, max_hp: int, state: String, down_count: int = 0) -> void:
	_state.set_down_count(peer_id, down_count)
	health_changed.emit(peer_id, current_hp, max_hp)
	player_state_changed.emit(peer_id, state)


func get_down_count(peer_id: int) -> int:
	return _state.get_down_count(peer_id)


func is_on_last_life(peer_id: int) -> bool:
	return _state.is_on_last_life(peer_id)


@rpc("authority", "reliable", "call_local")
func _sync_survivor_died(peer_id: int) -> void:
	survivor_died_permanently.emit(peer_id)


# ── Cooldown / evolución ─────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _rpc_cooldown_state(slot_index: int, duration: float) -> void:
	var huds = get_tree().get_nodes_in_group(GroupNames.GAME_HUD)
	if huds.is_empty():
		for i in range(3):
			await get_tree().process_frame
			huds = get_tree().get_nodes_in_group(GroupNames.GAME_HUD)
			if not huds.is_empty():
				break
	if huds.is_empty():
		return
	var hud = huds[0]
	if hud.has_method("on_cooldown_state_changed"):
		hud.on_cooldown_state_changed(slot_index, duration)


@rpc("authority", "call_local", "reliable")
func _rpc_evolve_slot(slot_index: int, stage: int) -> void:
	var peer_id = multiplayer.get_unique_id()
	_state.set_evolved_stage(peer_id, slot_index, stage)
	if stage > 0:
		slot_evolved.emit(slot_index, stage)
	else:
		slot_devolved.emit(slot_index)


@rpc("authority", "call_local", "reliable")
func _rpc_tp_ready(slot_index: int, is_ready: bool) -> void:
	var huds = get_tree().get_nodes_in_group(GroupNames.GAME_HUD)
	if huds.is_empty():
		return
	var hud = huds[0]
	if hud.has_method("visual_tp_ready"):
		hud.visual_tp_ready(slot_index, is_ready)


# ── Radar ────────────────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _rpc_add_arrow(arrow_id: int, type: int, target_x: float, target_y: float, track_peer: int, filter_peer: int, duration: float) -> void:
	arrow_spawned.emit(arrow_id, type, Vector2(target_x, target_y), track_peer, filter_peer, duration)


@rpc("authority", "call_local", "reliable")
func _rpc_remove_arrow(arrow_id: int) -> void:
	arrow_despawned.emit(arrow_id)


# ── Damage numbers ───────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _rpc_add_damage_number(peer_id: int, amount: int, pos_x: float, pos_y: float, rng_seed: int, dir_sign: float, color: Color) -> void:
	damage_number_spawned.emit(peer_id, amount, pos_x, pos_y, rng_seed, dir_sign, color)


# ── Revive ───────────────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _notify_revive_started(rescuer_id: int, target_id: int, duration: float) -> void:
	revive_started.emit(rescuer_id, target_id, duration)


@rpc("authority", "call_local", "reliable")
func _notify_revive_cancelled(rescuer_id: int, target_id: int) -> void:
	revive_cancelled.emit(rescuer_id, target_id)


@rpc("authority", "call_local", "reliable")
func _notify_revive_completed(rescuer_id: int, target_id: int) -> void:
	revive_completed.emit(rescuer_id, target_id)


# ── Map events / fase ────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _sync_lms_state(threshold: float) -> void:
	lms_state_changed.emit(threshold)


@rpc("authority", "call_local", "reliable")
func _sync_lms_ended() -> void:
	lms_ended_state.emit()


@rpc("authority", "call_local", "reliable")
func _sync_game_state(new_state: int, old_state: int) -> void:
	_state.set_game_state(new_state)
	game_state_changed.emit(new_state, old_state)


func get_game_state() -> int:
	return _state.get_game_state()


@rpc("authority", "call_local", "reliable")
func _sync_escaped_players(escaped: Array[int]) -> void:
	_state.set_escaped_players(escaped)
	escaped_players_changed.emit(_state.get_escaped_players())


# ── Status effects / rage ────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _rpc_effect_applied(peer_id: int, effect_name: String, duration: float) -> void:
	effect_applied.emit(peer_id, effect_name, duration)


@rpc("authority", "call_local", "reliable")
func _rpc_effect_removed(peer_id: int, effect_name: String) -> void:
	effect_removed.emit(peer_id, effect_name)


@rpc("authority", "call_local", "reliable")
func _rpc_rage_state(charged: bool, progress: int, required: int) -> void:
	rage_state_changed.emit(charged, progress, required)


@rpc("authority", "call_local", "reliable")
func _rpc_rage_time(caster_id: int, remaining: float) -> void:
	rage_time_changed.emit(caster_id, remaining)


# ── Audio ────────────────────────────────────────────────────────────

@rpc("authority", "reliable", "call_local")
func _rpc_setup_map_audio(map_id: String) -> void:
	AudioManager.setup_match_audio(map_id)


@rpc("authority", "reliable")
func _rpc_sync_spectator_audio(map_id: String, priority: int, position: float, lms_peer: int) -> void:
	AudioManager.setup_match_audio(map_id)
	AudioManager.apply_synced_priority(priority, position, lms_peer)


# ── Stamina / TP ─────────────────────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func sync_stamina_to_client(peer_id: int, current_stamina: float, max_stamina: float) -> void:
	_state.set_stamina(peer_id, current_stamina, max_stamina)
	stamina_changed.emit(peer_id, current_stamina, max_stamina)


@rpc("authority", "call_local", "reliable")
func sync_tp_to_client(peer_id: int, current_tp: float, max_tp: float) -> void:
	_state.set_tp(peer_id, current_tp, max_tp)
	tp_changed.emit(peer_id, current_tp, max_tp)


func get_tp(peer_id: int) -> Dictionary:
	return _state.get_tp(peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_dynamic_tp_cost(slot_index: int, cost: float) -> void:
	dynamic_tp_cost_changed.emit(slot_index, cost)


@rpc("authority", "call_local", "reliable")
func _rpc_ability_slot_updated(slot_index: int, tp_cost: float, cooldown: float, stage: int) -> void:
	ability_slot_updated.emit(slot_index, tp_cost, cooldown, stage)


# ── Diálogos / cámara / stats ───────────────────────────────────────

@rpc("authority", "call_local", "reliable")
func _rpc_push_dialog(message: String, type: int = 0) -> void:
	dialog_notification.emit(message, type)


@rpc("authority", "call_local", "reliable")
func _rpc_camera_shake(intensity: float, duration: float) -> void:
	camera_shake.emit(intensity, duration)


@rpc("authority", "reliable")
func _rpc_my_stats(stats: Dictionary) -> void:
	_state.set_stats(stats)
	stats_received.emit(stats)


# ── Helpers de nodos ─────────────────────────────────────────────────

func _find_killer_node() -> Node2D:
	var killers = get_tree().get_nodes_in_group(GroupNames.KILLER)
	if killers.is_empty():
		return null
	return killers[0] as Node2D


func _find_any_survivor_node() -> Node2D:
	var survivors = get_tree().get_nodes_in_group(GroupNames.SURVIVOR)
	if survivors.is_empty():
		return null
	return survivors[0] as Node2D


# ── API pública ──────────────────────────────────────────────────────

func has_player_escaped(peer_id: int) -> bool:
	return _state.has_player_escaped(peer_id)


func is_evolved(peer_id: int, slot_index: int) -> bool:
	return _state.is_evolved(peer_id, slot_index)


func get_evolved_stage(peer_id: int, slot_index: int) -> int:
	return _state.get_evolved_stage(peer_id, slot_index)


func get_stamina(peer_id: int) -> Dictionary:
	return _state.get_stamina(peer_id)


func get_my_stats() -> Dictionary:
	return _state.get_my_stats()


func reset_state() -> void:
	_state.reset()
