extends Control

@onready var create_room_btn = $MarginContainer/VBoxContainer/CreateRoomButton
@onready var join_room_btn = $MarginContainer/VBoxContainer/JoinRoomButton
@onready var quit_btn = $MarginContainer/VBoxContainer/QuitButton

func _ready():
	# Opcional: si llegas aquí sin haber limpiado bien, puedes forzar una limpieza
	# Pero evita hacerlo si ya se hizo.
	await get_tree().process_frame

func _full_network_reset():
	print("Reiniciando sistema multiplayer por completo")
	# Limpiar game manager actual
	if NetworkManager.current_game_manager:
		if NetworkManager.current_game_manager.has_method("cleanup"):
			NetworkManager.current_game_manager.cleanup()
		NetworkManager.current_game_manager.queue_free()
		NetworkManager.current_game_manager = null
	# Cerrar peer y limpiar datos
	if NetworkManager.multiplayer.multiplayer_peer:
		NetworkManager.multiplayer.multiplayer_peer.close()
	NetworkManager.multiplayer.multiplayer_peer = null
	NetworkManager.players.clear()
	NetworkManager.local_player_name = ""
	NetworkManager.selected_map = ""
	NetworkManager.is_host = false
	# Esperar múltiples frames para purgar caché
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
func _on_create_room_pressed():
	await _full_network_reset()
	get_tree().change_scene_to_file("res://ui/CreateRoom.tscn")

func _on_join_room_pressed():
	await _full_network_reset()
	get_tree().change_scene_to_file("res://ui/JoinRoom.tscn")


func _on_quit_pressed():
	get_tree().quit()
