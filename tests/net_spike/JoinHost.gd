extends Node


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer)
	multiplayer.peer_disconnected.connect(_on_peer_off)
	var ok: bool = NetworkManager.start_dedicated_server("test-browser", "1", "Escape", 4, 4242)
	print("[HOST] start_dedicated_server=", ok)
	await get_tree().create_timer(14.0).timeout
	print("[HOST] fin peers=", multiplayer.get_peers())
	get_tree().quit()


func _on_peer(id: int) -> void:
	print("[HOST] peer_connected ", id, " peers=", multiplayer.get_peers())


func _on_peer_off(id: int) -> void:
	print("[HOST] peer_disconnected ", id)
