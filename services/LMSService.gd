extends Node

signal lms_activated(survivor_node: Node, killer_node: Node, duration: float)
signal lms_ended()

var is_active: bool = false
var active_survivor: Node = null
var active_killer: Node = null

var _health_service: Node = null
var _status_service: Node = null
var _timer_service: Node = null
var _audio_manager = null
var _evolution_service: Node = null
var _lms_survivor_peer: int = -1
var _evolved_lms_slots: Array = []


func _ready() -> void:
	_connect_services()


func _connect_services() -> void:
	_health_service = GameServiceLocator.get_service("HealthService")
	_status_service = GameServiceLocator.get_service("StatusEffectService")
	_timer_service = GameServiceLocator.get_service("TimerService")
	_evolution_service = GameServiceLocator.get_service("EvolutionService")
	_audio_manager = AudioManager

	if _evolution_service and _evolution_service.has_signal("slot_devolved"):
		_evolution_service.slot_devolved.connect(_on_slot_devolved)


func start_lms(survivor_node: Node, killer_node: Node) -> void:
	if is_active or not multiplayer.is_server():
		return

	is_active = true
	active_survivor = survivor_node
	active_killer = killer_node
	_lms_survivor_peer = survivor_node.get_multiplayer_authority()
	_evolved_lms_slots.clear()

	var char_data = survivor_node.character_data
	var lms_duration = char_data.lms_duration if char_data and "lms_duration" in char_data else 140.0
	var heal_amount = char_data.lms_heal_amount if char_data and "lms_heal_amount" in char_data else 60

	if _health_service:
		_health_service.heal(survivor_node, heal_amount)

	# Auto-evolucionar slots con lms_auto_evolve
	_apply_lms_evolutions()

	if _audio_manager:
		var lms_music = char_data.lms_music if char_data and "lms_music" in char_data else null
		if lms_music:
			_audio_manager.lms_music_player.stream = lms_music
		_audio_manager.rpc("_rpc_activate_lms_audio", _lms_survivor_peer)

	if _timer_service:
		_timer_service.start_timer(lms_duration)

	lms_activated.emit(survivor_node, killer_node, lms_duration)


func stop_lms() -> void:
	if not is_active:
		return

	is_active = false

	if _evolution_service and _lms_survivor_peer > 0:
		_evolution_service.clear_all(_lms_survivor_peer)

	if _audio_manager:
		_audio_manager.rpc("_rpc_deactivate_lms_audio")

	active_survivor = null
	active_killer = null
	_lms_survivor_peer = -1
	_evolved_lms_slots.clear()
	lms_ended.emit()


func is_lms_active() -> bool:
	return is_active


func get_active_survivor() -> Node:
	return active_survivor


func _apply_lms_evolutions() -> void:
	if not _evolution_service or not active_survivor:
		return

	var char_data = active_survivor.character_data
	if not char_data or not char_data.ability_slots:
		return

	for i in char_data.ability_slots.size():
		var data = char_data.ability_slots[i]
		if data and data.lms_auto_evolve and data.evolved_version:
			_evolution_service.evolve_slot(_lms_survivor_peer, i, true)
			_evolved_lms_slots.append(i)
			print("[LMSService] Slot ", i, " (", data.display_name, ") auto-evolucionado para LMS")


func _on_slot_devolved(peer_id: int, slot_index: int) -> void:
	if not is_active or peer_id != _lms_survivor_peer:
		return
	if slot_index in _evolved_lms_slots:
		var char_data = active_survivor.character_data if active_survivor else null
		if char_data and slot_index < char_data.ability_slots.size():
			var data = char_data.ability_slots[slot_index]
			if data and data.lms_auto_evolve and data.evolved_version:
				_evolution_service.evolve_slot(peer_id, slot_index, true)
				print("[LMSService] Slot ", slot_index, " re-evolucionado tras consumo en LMS")
