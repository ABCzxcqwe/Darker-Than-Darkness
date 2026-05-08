# create_room.gd
# Pantalla de creación de sala.
# Los mapas disponibles se cargan dinámicamente desde MapRegistry.
extends Control

@onready var player_name_input: LineEdit   = $MarginContainer/VBoxContainer/PlayerNameInput
@onready var map_option:        OptionButton = $MarginContainer/VBoxContainer/MapOption
@onready var map_icon:          TextureRect  = $MarginContainer/VBoxContainer/MapIcon
@onready var create_btn:        Button       = $MarginContainer/VBoxContainer/CreateButton
@onready var back_btn:          Button       = $MarginContainer/VBoxContainer/BackButton
@onready var status_label:      Label        = $MarginContainer/VBoxContainer/StatusLabel

# Lista de MapData cargada desde MapRegistry — mismo orden que el OptionButton
var _available_maps: Array = []

func _ready() -> void:
	_populate_map_list()
	NetworkManager.connection_succeeded.connect(_on_server_created)
	status_label.text = ""

func _populate_map_list() -> void:
	map_option.clear()
	_available_maps = MapRegistry.get_all()

	if _available_maps.is_empty():
		push_warning("[CreateRoom] No hay mapas registrados en MapRegistry.")
		create_btn.disabled = true
		status_label.text   = "No hay mapas disponibles."
		return

	for map_data in _available_maps:
		map_option.add_item(map_data.display_name)

	# Mostrar ícono del primer mapa
	_update_map_icon(0)
	map_option.item_selected.connect(_update_map_icon)

func _update_map_icon(index: int) -> void:
	if not map_icon:
		return
	if index < 0 or index >= _available_maps.size():
		return
	var data: MapData = _available_maps[index]
	map_icon.texture = data.icon if data.icon else null

func _on_create_pressed() -> void:
	var player_name: String = player_name_input.text.strip_edges()
	if player_name.is_empty():
		status_label.text = "Ingresá tu nombre."
		return

	var selected_index: int = map_option.selected
	if selected_index < 0 or selected_index >= _available_maps.size():
		status_label.text = "Seleccioná un mapa."
		return

	var map_data: MapData = _available_maps[selected_index]
	var success: bool = NetworkManager.create_server(player_name, map_data.id)
	if not success:
		status_label.text = "Error al crear el servidor."

func _on_server_created() -> void:
	print("[CreateRoom] Servidor creado, cambiando a lobby...")
	get_tree().change_scene_to_file("res://ui/Lobby.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")

func _exit_tree() -> void:
	if NetworkManager.connection_succeeded.is_connected(_on_server_created):
		NetworkManager.connection_succeeded.disconnect(_on_server_created)
