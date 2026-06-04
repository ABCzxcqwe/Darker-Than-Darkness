extends Control

@onready var player_list = $MarginContainer/VBoxContainer/PlayerList
@onready var map_label = $MarginContainer/VBoxContainer/MapLabel
@onready var start_btn = $MarginContainer/VBoxContainer/StartButton
@onready var leave_btn = $MarginContainer/VBoxContainer/LeaveButton
@onready var status_label = $MarginContainer/VBoxContainer/StatusLabel
func _ready():
	add_to_group("lobby")
	start_btn.visible = NetworkManager.is_host
	map_label.text = "Mapa: " + NetworkManager.selected_map

	NetworkManager.lobby_updated.connect(_update_player_list)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	_update_player_list()

func _update_player_list():
	player_list.clear()
	for p in NetworkManager.get_player_list():
		var text = p.name
		if p.is_host:
			text += " (HOST)"
		var char_name = "?"
		if p.character_id != -1:
			var data := CharacterRegistry.get_character(p.character_id)
			if data:
				char_name = data.display_name
		text += " - Personaje: " + char_name
		player_list.add_item(text)
	
	var map_id: String = NetworkManager.selected_map as String
	if MapRegistry.has_map(map_id):
		var map_data: MapData = MapRegistry.get_map(map_id) as MapData
		map_label.text = "Mapa: " + map_data.display_name
	else:
		map_label.text = "Mapa: " + (map_id if not map_id.is_empty() else "Cargando...")
	status_label.text = "Jugadores: %d/%d" % [NetworkManager.players.size(), NetworkManager.MAX_PLAYERS]

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
		status_label.text = "No hay suficientes jugadores."
		return
	
	# LLAMADA AL NUEVO SISTEMA ASIMÉTRICO
	NetworkManager.host_start_character_selection()

func _on_leave_pressed():
	if not is_inside_tree():
		return
	MatchCoordinator.reset_to_menu()

func _return_to_menu():
	if is_inside_tree():
		# Limpiar NetworkManager antes de cambiar de escena
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")
