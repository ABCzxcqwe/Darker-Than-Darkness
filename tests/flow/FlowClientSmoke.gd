# res://tests/flow/FlowClientSmoke.gd
# Cliente del test de flujo completo. Se conecta al host de FlowHostSmoke.
extends Node

const SERVER := "127.0.0.1:4242"
const CONNECT_TIMEOUT := 8.0


func _ready() -> void:
	await get_tree().process_frame
	NetworkManager.set_lan_mode()

	var connected := [false]
	NetworkManager.connection_succeeded.connect(func() -> void:
		connected[0] = true
	)
	if not NetworkManager.join_server("FlowClient", SERVER):
		push_error("[FlowClient] join_server falló")
		get_tree().quit(1)
		return

	var elapsed := 0.0
	while not connected[0] and elapsed < CONNECT_TIMEOUT:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if not connected[0]:
		push_error("[FlowClient] timeout de conexión")
		get_tree().quit(1)
		return

	var watchdog := preload("res://tests/flow/FlowClientWatchdog.gd").new()
	watchdog.name = "FlowClientWatchdog"
	get_tree().root.add_child(watchdog)
	get_tree().change_scene_to_file("res://Maps/Session.tscn")
