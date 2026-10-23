# res://tests/session/HubClientSmoke.gd
# Cliente de humo: se conecta a un servidor dedicado, carga el hub y comprueba
# que LobbyManager y los avatares se sincronizan. Uso:
#   1. godot --headless --path . -- --server --port=43998 --max=4 --map=3
#   2. godot --headless --path . res://tests/session/HubClientSmoke.tscn
extends Node

const DEFAULT_SERVER := "127.0.0.1:43998"
const CONNECT_TIMEOUT := 6.0


func _ready() -> void:
	await get_tree().process_frame
	NetworkManager.set_lan_mode()

	var server := DEFAULT_SERVER
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hub-server="):
			server = arg.substr("--hub-server=".length())

	var connected := [false]
	NetworkManager.connection_succeeded.connect(func() -> void:
		connected[0] = true
	)
	if not NetworkManager.join_server("TestClient", server):
		push_error("[HubClientSmoke] join_server falló")
		get_tree().quit(1)
		return

	var elapsed := 0.0
	while not connected[0] and elapsed < CONNECT_TIMEOUT:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if not connected[0]:
		push_error("[HubClientSmoke] Timeout de conexión")
		get_tree().quit(1)
		return

	# El watchdog vive en root para sobrevivir al cambio de escena.
	var watchdog := preload("res://tests/session/HubClientWatchdog.gd").new()
	watchdog.name = "HubClientWatchdog"
	get_tree().root.add_child(watchdog)
	get_tree().change_scene_to_file("res://Maps/Session.tscn")
