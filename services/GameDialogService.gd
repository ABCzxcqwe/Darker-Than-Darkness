extends Node

var _client_relay: Node

func set_client_relay(relay: Node) -> void:
	_client_relay = relay

func _ready() -> void:
	var coordinator = GameServiceLocator.map_event_coordinator
	if coordinator and coordinator.has_signal("exit_activated"):
		if not coordinator.exit_activated.is_connected(_on_exit_activated):
			coordinator.exit_activated.connect(_on_exit_activated)

	var lms = GameServiceLocator.lms
	if lms and lms.has_signal("lms_activated"):
		if not lms.lms_activated.is_connected(_on_lms_activated):
			lms.lms_activated.connect(_on_lms_activated)

func _on_exit_activated(_exit_id: String) -> void:
	if not multiplayer.is_server():
		return
	if _client_relay and _client_relay.has_method("_rpc_push_dialog"):
		_client_relay.rpc("_rpc_push_dialog", "¡LAS SALIDAS SE HAN ABIERTO!", 0)

func _on_lms_activated(_survivor_node: Node, _killer_node: Node, _duration: float) -> void:
	if not multiplayer.is_server():
		return
	if _client_relay and _client_relay.has_method("_rpc_push_dialog"):
		_client_relay.rpc("_rpc_push_dialog", "¡MODO ÚLTIMO SUPERVIVIENTE!", 0)
