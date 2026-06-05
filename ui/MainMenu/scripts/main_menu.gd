extends Control

@onready var create_room_btn = $MarginContainer/VBoxContainer/CreateRoomButton
@onready var join_room_btn = $MarginContainer/VBoxContainer/JoinRoomButton
@onready var quit_btn = $MarginContainer/VBoxContainer/QuitButton
var _focus_items: Array[Control] = []
var _focus_idx := 0

func _ready():
	await get_tree().process_frame
	_setup_focus()

func _setup_focus() -> void:
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color(0.114, 0.114, 0.114, 1)
	focus_style.border_color = Color.WHITE
	focus_style.border_width_left = 3
	focus_style.border_width_top = 3
	focus_style.border_width_right = 3
	focus_style.border_width_bottom = 3
	focus_style.set_corner_radius_all(3)
	focus_style.set_expand_margin_all(5)
	_focus_items = [create_room_btn, join_room_btn, quit_btn]
	for i in _focus_items.size():
		_focus_items[i].add_theme_stylebox_override("focus", focus_style)
		_focus_items[i].focus_entered.connect(_update_focus.bind(i))
	create_room_btn.grab_focus()
	_focus_idx = 0

func _update_focus(i: int) -> void:
	_focus_idx = i

func _input(event):
	if event is InputEventKey and event.pressed and not event.is_echo():
		var kc = event.keycode
		var pkc = event.physical_keycode
		if kc != KEY_W and kc != KEY_S and pkc != KEY_W and pkc != KEY_S:
			return

		if (kc == KEY_W or pkc == KEY_W) and _focus_idx > 0:
			_focus_idx -= 1
			_focus_items[_focus_idx].grab_focus()
			AudioManager.play_sfx_ui(2)
			get_viewport().set_input_as_handled()
		elif (kc == KEY_S or pkc == KEY_S) and _focus_idx < _focus_items.size() - 1:
			_focus_idx += 1
			_focus_items[_focus_idx].grab_focus()
			AudioManager.play_sfx_ui(2)
			get_viewport().set_input_as_handled()

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
	NetworkManager.players.clear()
	NetworkManager.local_player_name = ""
	NetworkManager.selected_map = ""
	NetworkManager.is_host = false
	# Esperar múltiples frames para purgar caché
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
func _on_create_room_pressed():
	AudioManager.play_sfx_ui(1)
	await _full_network_reset()
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/CreateRoom.tscn")

func _on_join_room_pressed():
	AudioManager.play_sfx_ui(1)
	await _full_network_reset()
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/JoinRoom.tscn")


func _on_quit_pressed():
	AudioManager.play_sfx_ui(1)
	get_tree().quit()
