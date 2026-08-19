extends Node

signal slot_evolved(peer_id: int, slot_index: int)
signal slot_devolved(peer_id: int, slot_index: int)

var _evolved_slots: Dictionary = {}
var _client_evolved_slots: Dictionary = {}
var _tp_ready_slots: Dictionary = {}
var _client_relay: Node


func set_client_relay(relay: Node) -> void:
	_client_relay = relay


func _ready() -> void:
	if multiplayer.is_server():
		var tp_svc = GameServiceLocator.tp
		if tp_svc and tp_svc.has_signal("tp_changed"):
			tp_svc.tp_changed.connect(_on_tp_changed)


func register_player(peer_id: int, _data: Resource = null) -> void:
	if not multiplayer.is_server():
		return
	_evolved_slots[peer_id] = [0, 0, 0, 0, 0]
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

	var max_stage := _get_max_stage(peer_id, slot_index)
	var current: int = _evolved_slots[peer_id][slot_index]
	if current >= max_stage:
		return

	var new_stage: int = current + 1
	_evolved_slots[peer_id][slot_index] = new_stage
	slot_evolved.emit(peer_id, slot_index)
	if not skip_rpc:
		_sync_visual_to_client(peer_id, slot_index, new_stage)


## Resetea un slot a su versión base (stage 0). Usado por habilidades en ciclo
## (p. ej. Diamond Rain de Jevil) para volver al inicio de la cadena.
func reset_slot(peer_id: int, slot_index: int, skip_rpc: bool = false) -> void:
	if not multiplayer.is_server():
		return
	if not _evolved_slots.has(peer_id):
		return
	if slot_index < 0 or slot_index >= 5:
		return

	if _evolved_slots[peer_id][slot_index] == 0:
		return

	_evolved_slots[peer_id][slot_index] = 0
	slot_devolved.emit(peer_id, slot_index)
	if not skip_rpc:
		_sync_visual_to_client(peer_id, slot_index, 0)


func is_evolved(peer_id: int, slot_index: int) -> bool:
	return get_evolved_stage(peer_id, slot_index) > 0


## Etapa actual de evolución del slot (0 = base, 1 = primera evolución, ...).
## Permite cadenas de evolución multi-hop (p. ej. Diamond Rain de Jevil).
func get_evolved_stage(peer_id: int, slot_index: int) -> int:
	var slots = _evolved_slots if multiplayer.is_server() else _client_evolved_slots
	if not slots.has(peer_id):
		return 0
	if slot_index < 0 or slot_index >= 5:
		return 0
	return slots[peer_id][slot_index]


func consume_evolution(peer_id: int, slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	if not _evolved_slots.has(peer_id):
		return

	# Cada habilidad evolucionada revierte solo cuando ESA habilidad se usa.
	_clear_if_temporary(peer_id, slot_index)


func _clear_if_temporary(peer_id: int, slot_index: int) -> void:
	if _is_permanent_evolution(peer_id, slot_index):
		return
	_clear_and_sync_slot(peer_id, slot_index)


func _is_permanent_evolution(peer_id: int, slot_index: int) -> bool:
	var player = PlayerRegistry.get_player(peer_id)
	if not player or not player.character_data:
		return false
	var slots: Array = player.character_data.ability_slots
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var base = slots[slot_index]
	if not base or not base.evolved_version:
		return false
	return base.evolved_version.evolution_consume == 1


## Cuántas evoluciones encadena el slot desde su versión base (stage máximo).
## P. ej. base → A → B → C tiene max_stage 3.
func _get_max_stage(peer_id: int, slot_index: int) -> int:
	var player = PlayerRegistry.get_player(peer_id)
	if not player or not player.character_data:
		return 0
	var slots: Array = player.character_data.ability_slots
	if slot_index < 0 or slot_index >= slots.size():
		return 0
	var data = slots[slot_index]
	var stage := 0
	while data and data.evolved_version:
		data = data.evolved_version
		stage += 1
		if stage > 9:
			break
	return stage


func clear_all(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not _evolved_slots.has(peer_id):
		return

	for i in 5:
		_clear_and_sync_slot(peer_id, i)


func _clear_and_sync_slot(peer_id: int, slot_index: int) -> void:
	if _evolved_slots[peer_id][slot_index] > 0:
		_evolved_slots[peer_id][slot_index] = 0
		slot_devolved.emit(peer_id, slot_index)
		_sync_visual_to_client(peer_id, slot_index, 0)
		_set_tp_ready(peer_id, slot_index, false)


func _sync_visual_to_client(peer_id: int, slot_index: int, stage: int) -> void:
	if LobbyManager.players.has(peer_id):
		_client_relay.rpc_id(peer_id, "_rpc_evolve_slot", slot_index, stage)


func _sync_evolve_local(slot_index: int, stage: int) -> void:
	var peer_id = multiplayer.get_unique_id()
	if not _client_evolved_slots.has(peer_id):
		_client_evolved_slots[peer_id] = [0, 0, 0, 0, 0]
	if slot_index >= 0 and slot_index < 5:
		_client_evolved_slots[peer_id][slot_index] = stage

	var huds = get_tree().get_nodes_in_group("game_hud")
	for hud in huds:
		if stage > 0:
			if hud.has_method("visual_evolve_slot"):
				hud.visual_evolve_slot(slot_index, stage)
		else:
			if hud.has_method("visual_devolve_slot"):
				hud.visual_devolve_slot(slot_index)


func resync_client_visuals(peer_id: int) -> void:
	if LobbyManager.players.has(peer_id):
		var evolved = _evolved_slots.get(peer_id)
		if evolved == null:
			return
		for i in evolved.size():
			if evolved[i] > 0:
				_client_relay.rpc_id(peer_id, "_rpc_evolve_slot", i, evolved[i])


func _on_tp_changed(peer_id: int, current_tp: float, _max_tp: float) -> void:
	if not multiplayer.is_server():
		return
	if not _tp_ready_slots.has(peer_id):
		return

	var player = PlayerRegistry.get_player(peer_id)
	if not player or not player.character_data:
		return
	var slots: Array = player.character_data.ability_slots

	for i in slots.size():
		var data = slots[i]
		if not data or not data.evolved_version:
			continue

		var is_lms: bool = data.lms_auto_evolve
		var tp_sufficient: bool = current_tp >= data.evolved_version.tp_cost

		if not is_lms:
			continue

		var evolved = _evolved_slots.get(peer_id)
		if evolved == null or evolved[i] <= 0:
			continue

		_set_tp_ready(peer_id, i, tp_sufficient)


func _set_tp_ready(peer_id: int, slot_index: int, is_ready: bool) -> void:
	if not _tp_ready_slots.has(peer_id):
		return
	if slot_index < 0 or slot_index >= 5:
		return
	if _tp_ready_slots[peer_id][slot_index] == is_ready:
		return

	_tp_ready_slots[peer_id][slot_index] = is_ready
	if LobbyManager.players.has(peer_id):
		_client_relay.rpc_id(peer_id, "_rpc_tp_ready", slot_index, is_ready)


func _sync_tp_ready_local(slot_index: int, is_ready: bool) -> void:
	var huds = get_tree().get_nodes_in_group("game_hud")
	if huds.is_empty():
		return
	var hud = huds[0]
	if hud.has_method("visual_tp_ready"):
		hud.visual_tp_ready(slot_index, is_ready)
