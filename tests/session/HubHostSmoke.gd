# res://tests/session/HubHostSmoke.gd
# Host de humo: crea una sala LAN y carga el hub. Queda vivo para que un
# cliente se conecte. Uso:
#   godot --headless --path . res://tests/session/HubHostSmoke.tscn
#   godot --headless --path . res://tests/session/HubClientSmoke.tscn -- --hub-server=127.0.0.1:4242
extends Node


func _ready() -> void:
	await get_tree().process_frame
	NetworkManager.set_lan_mode()
	if not NetworkManager.create_server("HubHost", "3", "HubHost", "Escape", 4):
		push_error("[HubHostSmoke] create_server falló")
		get_tree().quit(1)
		return
	get_tree().change_scene_to_file("res://Maps/Session.tscn")
