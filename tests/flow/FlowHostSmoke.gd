# res://tests/flow/FlowHostSmoke.gd
# Host del test de flujo completo:
#   hub -> CharacterSelect -> partida -> resultados -> hub
# Uso:
#   godot --headless --path . res://tests/flow/FlowHostSmoke.tscn
#   godot --headless --path . res://tests/flow/FlowClientSmoke.tscn
extends Node


func _ready() -> void:
	await get_tree().process_frame
	NetworkManager.set_lan_mode()
	if not NetworkManager.create_server("FlowHost", "3", "FlowHost", "Escape", 4):
		push_error("[FlowHost] create_server falló")
		get_tree().quit(1)
		return

	var watchdog := preload("res://tests/flow/FlowHostWatchdog.gd").new()
	watchdog.name = "FlowHostWatchdog"
	get_tree().root.add_child(watchdog)
	get_tree().change_scene_to_file("res://Maps/Session.tscn")
