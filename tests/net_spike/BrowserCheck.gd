extends Node

var _sb: Control


func _ready() -> void:
	SettingsManager.network_mode = 0  # LAN
	var ps := load("res://ui/MainMenu/scenes/ServerBrowser.tscn") as PackedScene
	_sb = ps.instantiate()
	add_child(_sb)
	await get_tree().process_frame
	_sb._mode = "LAN"
	_sb._ip_edit.text = "127.0.0.1"

	# Evitamos que el browser cambie de escena al conectar: lo detectamos nosotros.
	if NetworkManager.connection_succeeded.is_connected(_sb._on_connection_succeeded):
		NetworkManager.connection_succeeded.disconnect(_sb._on_connection_succeeded)
	NetworkManager.connection_succeeded.connect(_on_ok)

	print("[BROWSER] _try_join_lan -> 127.0.0.1")
	_sb._try_join_lan()

	await get_tree().create_timer(22.0).timeout
	print("[BROWSER] TIMEOUT sin éxito (joining=%s fallback=%s hint='%s')" % [
		str(_sb._joining), str(_sb._fallback_attempted), _sb._hint.text])
	get_tree().quit(1)


func _on_ok() -> void:
	print("[BROWSER] SUCCESS: conectado por IP directa")
	get_tree().quit(0)
