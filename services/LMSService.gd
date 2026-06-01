# res://services/LMSService.gd
# Activa el modo LMS (Last Man Standing) cuando GameStateService lo ordena.
# GameStateService decide cuándo, LMSService solo ejecuta.
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


func _ready() -> void:
	_connect_services()


func _connect_services() -> void:
	_health_service = GameServiceLocator.get_service("HealthService")
	_status_service = GameServiceLocator.get_service("StatusEffectService")
	_timer_service = GameServiceLocator.get_service("TimerService")
	_audio_manager = AudioManager


func start_lms(survivor_node: Node, killer_node: Node) -> void:
	if is_active or not multiplayer.is_server():
		return

	is_active = true
	active_survivor = survivor_node
	active_killer = killer_node

	var char_data = survivor_node.character_data
	var lms_duration = char_data.lms_duration if char_data and "lms_duration" in char_data else 140.0
	var heal_amount = char_data.lms_heal_amount if char_data and "lms_heal_amount" in char_data else 60

	if _health_service:
		_health_service.heal(survivor_node, heal_amount)

	# Audio LMS
	if _audio_manager:
		var lms_music = char_data.lms_music if char_data and "lms_music" in char_data else null
		if lms_music:
			_audio_manager.lms_music_player.stream = lms_music
		_audio_manager.rpc("_rpc_activate_lms_audio", survivor_node.get_multiplayer_authority())

	# GameStateService maneja el timer — solo reiniciamos la duración
	if _timer_service:
		_timer_service.start_timer(lms_duration)

	lms_activated.emit(survivor_node, killer_node, lms_duration)


func stop_lms() -> void:
	if not is_active:
		return

	if _audio_manager:
		_audio_manager.rpc("_rpc_deactivate_lms_audio")

	is_active = false
	active_survivor = null
	active_killer = null
	lms_ended.emit()


func is_lms_active() -> bool:
	return is_active


func get_active_survivor() -> Node:
	return active_survivor
