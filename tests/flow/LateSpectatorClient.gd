# res://tests/flow/LateSpectatorClient.gd
# Espectador tardío: se conecta cuando la partida ya está en curso, pide
# espectar y verifica que el Synchronizer de posición le entregue el delta
# continuo (net_position del host debe cambiar aunque no haya teleports).
# Uso (con LateSpectatorHost y LateSpectatorEarlyClient corriendo):
#   godot --headless --path . res://tests/flow/LateSpectatorClient.tscn
extends Node

const SERVER := "127.0.0.1:4242"
const CONNECT_TIMEOUT := 10.0
const SAMPLE_SECONDS := 8.0
const SAMPLE_INTERVAL := 0.5


func _ready() -> void:
	await get_tree().process_frame
	NetworkManager.set_lan_mode()

	var connected := [false]
	NetworkManager.connection_succeeded.connect(func() -> void:
		connected[0] = true
	)
	if not NetworkManager.join_server("LateSpectator", SERVER):
		push_error("[LateSpec] join_server falló")
		get_tree().quit(1)
		return

	var elapsed := 0.0
	while not connected[0] and elapsed < CONNECT_TIMEOUT:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if not connected[0]:
		push_error("[LateSpec] timeout de conexión")
		get_tree().quit(1)
		return

	var watchdog := preload("res://tests/flow/LateSpectatorWatchdog.gd").new()
	watchdog.name = "LateSpectatorWatchdog"
	get_tree().root.add_child(watchdog)
