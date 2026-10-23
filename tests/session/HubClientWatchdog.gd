# res://tests/session/HubClientWatchdog.gd
# Nodo que sobrevive al cambio de escena y valida el hub del cliente.
extends Node

const CHECK_DELAY := 3.0


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = CHECK_DELAY
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(_check)
	timer.start()


func _check() -> void:
	var session := get_tree().root.get_node_or_null("Session")
	var avatar_count := 0
	if session:
		var actors := session.get_node_or_null("Actors")
		if actors:
			avatar_count = actors.get_child_count()
	print("[HubClientWatchdog] players=%d avatars=%d scene=%s" % [
		LobbyManager.players.size(), avatar_count, str(get_tree().current_scene.name) if get_tree().current_scene else "null"
	])
	var ok := LobbyManager.players.size() >= 1 and avatar_count >= 1
	get_tree().quit(0 if ok else 1)
