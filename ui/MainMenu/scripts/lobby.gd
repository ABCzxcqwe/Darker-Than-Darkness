extends Control

@onready var player_list = $MarginContainer/VBoxContainer/PlayerList
@onready var map_label = $MarginContainer/VBoxContainer/MapLabel
@onready var start_btn = $MarginContainer/VBoxContainer/StartButton
@onready var leave_btn = $MarginContainer/VBoxContainer/LeaveButton
@onready var status_label = $MarginContainer/VBoxContainer/StatusLabel
@onready var character_option = $MarginContainer/VBoxContainer/CharacterOption  # Crea este OptionButton

func _ready():
	add_to_group("lobby")
	start_btn.visible = NetworkManager.is_host
	map_label.text = "Mapa: " + NetworkManager.selected_map

	NetworkManager.lobby_updated.connect(_update_player_list)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	_update_player_list()

	# Configurar selector de personaje
	character_option.add_item("Kris", 0)
	character_option.add_item("Susie", 1)
	character_option.add_item("Ralsei", 2)
	character_option.add_item("Jevil", 3)
	character_option.item_selected.connect(_on_character_selected)
	# Cargar la selección actual del jugador (si ya tenía una)
	var my_char = NetworkManager.get_local_character()
	character_option.selected = character_option.get_item_index(my_char)

func _update_player_list():
	player_list.clear()
	for p in NetworkManager.get_player_list():
		var text = p.name
		if p.is_host:
			text += " (HOST)"
		text += " - Personaje: " + _char_name(p.character_id)
		player_list.add_item(text)
	
	# NUEVO: Buscar el mapa en el registro para mostrar su nombre real/bonito
	var map_id: String = NetworkManager.selected_map as String
	if MapRegistry.has_map(map_id):
		var map_data: MapData = MapRegistry.get_map(map_id) as MapData
		map_label.text = "Mapa: " + map_data.display_name
	else:
		map_label.text = "Mapa: " + (map_id if not map_id.is_empty() else "Cargando...")
	status_label.text = "Jugadores: %d/%d" % [NetworkManager.players.size(), NetworkManager.MAX_PLAYERS]

func _char_name(id: int) -> String:
	match id:
		0: return "Kris"
		1: return "Suie"
		2: return "Ralsei"
		3: return "Jevil"
		_: return "?"

func _on_character_selected(index: int):
	var char_id = character_option.get_item_id(index)
	NetworkManager.set_my_character(char_id)

func _on_player_joined(_peer_id: int, _info: Dictionary):
	_update_player_list()

func _on_player_left(_peer_id: int):
	_update_player_list()

func _on_server_disconnected():
	if not is_inside_tree():
		return
	status_label.text = "Host desconectado. Volviendo al menú..."
	# No hacer nada más; NetworkManager se encarga

# En Lobby.gd, dentro de _on_start_pressed()
func _on_start_pressed():
	if not NetworkManager.is_host:
		return
	if NetworkManager.players.size() < 2:
		status_label.text = "Se necesitan al menos 2 jugadores"
		return
	status_label.text = "Iniciando partida..."
	start_btn.disabled = true
	NetworkManager.start_game()
	hide() 

func _on_leave_pressed():
	if not is_inside_tree():
		return
	await NetworkManager.reset_to_menu()

func _return_to_menu():
	if is_inside_tree():
		# Limpiar NetworkManager antes de cambiar de escena
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")
