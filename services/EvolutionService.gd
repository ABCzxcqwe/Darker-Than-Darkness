extends Node

signal slot_evolved(peer_id: int, slot_index: int)
signal slot_devolved(peer_id: int, slot_index: int)

var _evolved_slots: Dictionary = {}
var _tp_ready_slots: Dictionary = {}


func _ready() -> void:
	if multiplayer.is_server():
		var tp_svc = GameServiceLocator.get_service("TPService")
		if tp_svc and tp_svc.has_signal("tp_changed"):
			tp_svc.tp_changed.connect(_on_tp_changed)


func register_player(peer_id: int, _data: Resource = null) -> void:
	if not multiplayer.is_server():
		return
	_evolved_slots[peer_id] = [false, false, false, false, false]
	_tp_ready_slots[peer_id] = [false, false, false, false, false]
	print("[EvolutionService] Jugador ", peer_id, " registrado.")


func unregister_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_evolved_slots.erase(peer_id)
	_tp_ready_slots.erase(peer_id)


func evolve_slot(peer_id: int, slot_index: int, skip_rpc: bool = false) -> void:
	if not multiplayer.is_server():
		return
	if not _evolved_slots.has(peer_id):
		return
	if slot_index < 0 or slot_index >= 5:
		return

	if _evolved_slots[peer_id][slot_index]:
		return

	_evolved_slots[peer_id][slot_index] = true
	slot_evolved.emit(peer_id, slot_index)
	if not skip_rpc:
		_sync_visual_to_client(peer_id, slot_index, true)


func is_evolved(peer_id: int, slot_index: int) -> bool:
	if not _evolved_slots.has(peer_id):
		return false
	if slot_index < 0 or slot_index >= 5:
		return false
	return _evolved_slots[peer_id][slot_index]


func consume_evolution(peer_id: int, slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	if not _evolved_slots.has(peer_id):
		return

	if slot_index == 1 or slot_index == 3:
		_clear_if_temporary(peer_id, 1)
		_clear_if_temporary(peer_id, 3)
	else:
		_clear_if_temporary(peer_id, slot_index)


func _clear_if_temporary(peer_id: int, slot_index: int) -> void:
	if _is_permanent_evolution(peer_id, slot_index):
		return
	_clear_and_sync_slot(peer_id, slot_index)


func _is_permanent_evolution(peer_id: int, slot_index: int) -> bool:
	var player = get_tree().root.find_child(str(peer_id), true, false)
	if not player or not player.character_data:
		return false
	var slots: Array = player.character_data.ability_slots
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var base = slots[slot_index]
	if not base or not base.evolved_version:
		return false
	return base.evolved_version.evolution_consume == 1


func clear_all(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not _evolved_slots.has(peer_id):
		return

	for i in 5:
		_clear_and_sync_slot(peer_id, i)


func _clear_and_sync_slot(peer_id: int, slot_index: int) -> void:
	if _evolved_slots[peer_id][slot_index]:
		_evolved_slots[peer_id][slot_index] = false
		slot_devolved.emit(peer_id, slot_index)

		if _evolved_slots[peer_id][slot_index]:
			return

		_sync_visual_to_client(peer_id, slot_index, false)
		_set_tp_ready(peer_id, slot_index, false)


func _sync_visual_to_client(peer_id: int, slot_index: int, evolved: bool) -> void:
	if NetworkManager.players.has(peer_id):
		rpc_id(peer_id, "_rpc_evolve_slot", slot_index, evolved)


@rpc("authority", "call_local", "reliable")
func _rpc_evolve_slot(slot_index: int, evolved: bool) -> void:
	var huds = get_tree().get_nodes_in_group("game_hud")
	if huds.is_empty():
		return
	var hud = huds[0]
	if evolved:
		if hud.has_method("visual_evolve_slot"):
			hud.visual_evolve_slot(slot_index)
	else:
		if hud.has_method("visual_devolve_slot"):
			hud.visual_devolve_slot(slot_index)


func _on_tp_changed(peer_id: int, current_tp: float, _max_tp: float) -> void:
	if not multiplayer.is_server():
		return
	if not _tp_ready_slots.has(peer_id):
		return

	var player = get_tree().root.find_child(str(peer_id), true, false)
	if not player or not player.character_data:
		return
	var slots: Array = player.character_data.ability_slots

	for i in slots.size():
		var data = slots[i]
		if not data or not data.evolved_version:
			continue

		var is_lms: bool = data.lms_auto_evolve
		var tp_sufficient: bool = current_tp >= data.evolved_version.tp_cost
		var is_permanent: bool = data.evolved_version.evolution_consume == 1

		if not is_lms:
			continue

		var evolved = _evolved_slots.get(peer_id)
		if evolved == null or not evolved[i]:
			continue

		_set_tp_ready(peer_id, i, tp_sufficient)

		if tp_sufficient or is_permanent:
			_sync_visual_to_client(peer_id, i, true)
		else:
			_sync_visual_to_client(peer_id, i, false)


func _set_tp_ready(peer_id: int, slot_index: int, is_ready: bool) -> void:
	if not _tp_ready_slots.has(peer_id):
		return
	if slot_index < 0 or slot_index >= 5:
		return
	if _tp_ready_slots[peer_id][slot_index] == is_ready:
		return

	_tp_ready_slots[peer_id][slot_index] = is_ready
	if NetworkManager.players.has(peer_id):
		rpc_id(peer_id, "_rpc_tp_ready", slot_index, is_ready)


@rpc("authority", "call_local", "reliable")
func _rpc_tp_ready(slot_index: int, is_ready: bool) -> void:
	var huds = get_tree().get_nodes_in_group("game_hud")
	if huds.is_empty():
		return
	var hud = huds[0]
	if hud.has_method("visual_tp_ready"):
		hud.visual_tp_ready(slot_index, is_ready)
