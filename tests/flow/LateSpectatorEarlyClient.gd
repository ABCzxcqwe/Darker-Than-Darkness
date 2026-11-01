# res://tests/flow/LateSpectatorEarlyClient.gd
# Cliente temprano: solo existe para que el host pueda arrancar la partida
# (se necesitan 2 jugadores activos). Elige personaje y se queda quieto.
extends Node

const SERVER := "127.0.0.1:4242"
const CONNECT_TIMEOUT := 10.0


func _ready() -> void:
	await get_tree().process_frame
	NetworkManager.set_lan_mode()

	var connected := [false]
	NetworkManager.connection_succeeded.connect(func() -> void:
		connected[0] = true
	)
	if not NetworkManager.join_server("EarlyClient", SERVER):
		push_error("[EarlyClient] join_server falló")
		get_tree().quit(1)
		return

	var elapsed := 0.0
	while not connected[0] and elapsed < CONNECT_TIMEOUT:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if not connected[0]:
		push_error("[EarlyClient] timeout de conexión")
		get_tree().quit(1)
		return

	var watchdog := preload("res://tests/flow/LateSpectatorEarlyClientWatchdog.gd").new()
	watchdog.name = "EarlyClientWatchdog"
	get_tree().root.add_child(watchdog)

	get_tree().change_scene_to_file("res://Maps/Session.tscn")
