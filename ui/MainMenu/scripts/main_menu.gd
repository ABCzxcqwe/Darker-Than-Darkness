extends "res://ui/MainMenu/scripts/menu_base.gd"

@onready var create_room_btn = $MarginContainer/VBoxContainer/CreateRoomButton
@onready var join_room_btn = $MarginContainer/VBoxContainer/JoinRoomButton
@onready var options_btn = $MarginContainer/VBoxContainer/OptionsButton
@onready var quit_btn = $MarginContainer/VBoxContainer/QuitButton

func _ready():
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_setup_focus([create_room_btn, join_room_btn, options_btn, quit_btn])

func _full_network_reset():
	print("Reiniciando sistema multiplayer por completo")
	# Limpiar game manager actual
	if MatchCoordinator.current_game_manager:
		if MatchCoordinator.current_game_manager.has_method("cleanup"):
			MatchCoordinator.current_game_manager.cleanup()
		MatchCoordinator.current_game_manager.queue_free()
		MatchCoordinator.current_game_manager = null
	# Cerrar peer y limpiar datos
	if NetworkManager.multiplayer.multiplayer_peer:
		NetworkManager.multiplayer.multiplayer_peer.close()
	NetworkManager.multiplayer.multiplayer_peer = null
	LobbyManager.reset_lobby_state()
	LobbyManager.local_player_name = ""
	LobbyManager.selected_map = ""
	LobbyManager.is_host = false
	# Esperar múltiples frames para purgar caché
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await get_tree().process_frame
	
func _on_create_room_pressed():
	AudioManager.play_sfx_ui(SfxId.SELECT)
	await _full_network_reset()
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/CreateRoom.tscn")

func _on_join_room_pressed():
	AudioManager.play_sfx_ui(SfxId.SELECT)
	await _full_network_reset()
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/JoinRoom.tscn")


func _on_options_pressed():
	AudioManager.play_sfx_ui(SfxId.SELECT)
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/Settings.tscn")

func _on_quit_pressed():
	AudioManager.play_sfx_ui(SfxId.SELECT)
	get_tree().quit()
