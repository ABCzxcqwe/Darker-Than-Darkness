extends "res://ui/Old/scripts/menu_base.gd"

@onready var player_list = $MarginContainer/VBoxContainer/PlayerList
@onready var map_label = $MarginContainer/VBoxContainer/MapLabel
@onready var start_btn = $MarginContainer/VBoxContainer/StartButton
@onready var leave_btn = $MarginContainer/VBoxContainer/LeaveButton
@onready var status_label = $MarginContainer/VBoxContainer/StatusLabel

func _ready():
	add_to_group("lobby")
	start_btn.visible = LobbyManager.is_host
	map_label.text = "Mapa: " + LobbyManager.selected_map

	LobbyManager.lobby_updated.connect(_update_player_list)
	LobbyManager.player_joined.connect(_on_player_joined)
	LobbyManager.player_left.connect(_on_player_left)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)

	_update_player_list()
	var focus_items: Array[Control] = []
	if start_btn.visible:
		focus_items.append(start_btn)
	focus_items.append(leave_btn)
	_setup_focus(focus_items)

func _update_player_list():
	player_list.clear()
	for p in LobbyManager.get_player_list():
		var text = p.name
		if p.is_host:
			text += " (HOST)"
		var char_name = "?"
		if p.character_id != -1:
			var data: CharacterData = CharacterRegistry.get_character(p.character_id)
			if data:
				char_name = data.display_name
		text += " - Personaje: " + char_name
		player_list.add_item(text)
	
	var map_id: String = LobbyManager.selected_map as String
	if MapRegistry.has_map(map_id):
		var map_data: MapData = MapRegistry.get_map(map_id) as MapData
		map_label.text = "Mapa: " + map_data.display_name
	else:
		map_label.text = "Mapa: " + (map_id if not map_id.is_empty() else "Cargando...")
	status_label.text = "Jugadores: %d/%d" % [LobbyManager.players.size(), LobbyManager.MAX_PLAYERS]

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
	AudioManager.play_sfx_ui(SfxId.SELECT)
	if not LobbyManager.is_host:
		return
	if LobbyManager.players.size() < 2:
		status_label.text = "No hay suficientes jugadores."
		return
	
	# LLAMADA AL NUEVO SISTEMA ASIMÉTRICO
	LobbyManager.host_start_character_selection()

func _on_leave_pressed():
	AudioManager.play_sfx_ui(SfxId.SELECT)
	if not is_inside_tree():
		return
	MatchCoordinator.reset_to_menu()

func _exit_tree():
	if LobbyManager.lobby_updated.is_connected(_update_player_list):
		LobbyManager.lobby_updated.disconnect(_update_player_list)
	if LobbyManager.player_joined.is_connected(_on_player_joined):
		LobbyManager.player_joined.disconnect(_on_player_joined)
	if LobbyManager.player_left.is_connected(_on_player_left):
		LobbyManager.player_left.disconnect(_on_player_left)
	if NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.server_disconnected.disconnect(_on_server_disconnected)


