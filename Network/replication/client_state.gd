class_name ClientState
extends RefCounted
## Estado de cliente que replica ClientRelay.
##
## Separado del nodo RPC para que el relay no mezcle señales/transport con
## almacenamiento y consultas síncronas de la UI.

var time_left: float = 0.0
var game_state: int = 0  # 0 INTRO / 1 PLAYING / 2 ENDED
var evolved_slots: Dictionary = {}  # peer_id -> [stage x5]
var escaped_players: Array[int] = []
var stamina_cache: Dictionary = {}   # peer_id -> { current, max }
var tp_cache: Dictionary = {}        # peer_id -> { current, max }
var down_counts: Dictionary = {}     # peer_id -> caídas
var stats_cache: Dictionary = {}     # stats del peer local


func set_down_count(peer_id: int, count: int) -> void:
	down_counts[peer_id] = count


func get_down_count(peer_id: int) -> int:
	return int(down_counts.get(peer_id, 0))


func is_on_last_life(peer_id: int) -> bool:
	return get_down_count(peer_id) >= 1


func set_game_state(value: int) -> void:
	game_state = value


func get_game_state() -> int:
	return game_state


func set_evolved_stage(peer_id: int, slot_index: int, stage: int) -> void:
	if not evolved_slots.has(peer_id):
		evolved_slots[peer_id] = [0, 0, 0, 0, 0]
	if slot_index >= 0 and slot_index < 5:
		evolved_slots[peer_id][slot_index] = stage


func get_evolved_stage(peer_id: int, slot_index: int) -> int:
	var slots = evolved_slots.get(peer_id)
	if slots == null:
		return 0
	if slot_index < 0 or slot_index >= slots.size():
		return 0
	return int(slots[slot_index])


func is_evolved(peer_id: int, slot_index: int) -> bool:
	return get_evolved_stage(peer_id, slot_index) > 0


func set_escaped_players(escaped: Array) -> void:
	escaped_players.clear()
	for pid in escaped:
		escaped_players.append(int(pid))


func get_escaped_players() -> Array[int]:
	return escaped_players


func has_player_escaped(peer_id: int) -> bool:
	return peer_id in escaped_players


func set_stamina(peer_id: int, current: float, max_value: float) -> void:
	stamina_cache[peer_id] = {"current": current, "max": max_value}


func get_stamina(peer_id: int) -> Dictionary:
	return stamina_cache.get(peer_id, {"current": 0.0, "max": 0.0})


func set_tp(peer_id: int, current: float, max_value: float) -> void:
	tp_cache[peer_id] = {"current": current, "max": max_value}


func get_tp(peer_id: int) -> Dictionary:
	return tp_cache.get(peer_id, {})


func set_stats(stats: Dictionary) -> void:
	stats_cache = stats.duplicate(true)


func get_my_stats() -> Dictionary:
	return stats_cache


func reset() -> void:
	time_left = 0.0
	game_state = 0
	evolved_slots.clear()
	escaped_players.clear()
	stamina_cache.clear()
	tp_cache.clear()
	down_counts.clear()
	stats_cache.clear()
