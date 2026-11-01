# res://tests/flow/LateSpectatorHost.gd
# Host del test de late-join / espectador tardío.
# Levanta un servidor, arranca una partida con 1 cliente temprano y la MANTIENE
# en curso mientras un tercer peer se conecta a mitad de partida.
# Uso:
#   godot --headless --path . res://tests/flow/LateSpectatorHost.tscn
extends Node


func _ready() -> void:
	await get_tree().process_frame
	NetworkManager.set_lan_mode()
	if not NetworkManager.create_server("LateHost", "1", "LateHost", "Escape", 4):
		push_error("[LateHost] create_server falló")
		get_tree().quit(1)
		return

	var watchdog := preload("res://tests/flow/LateSpectatorHostWatchdog.gd").new()
	watchdog.name = "LateHostWatchdog"
	get_tree().root.add_child(watchdog)
	get_tree().change_scene_to_file("res://Maps/Session.tscn")
