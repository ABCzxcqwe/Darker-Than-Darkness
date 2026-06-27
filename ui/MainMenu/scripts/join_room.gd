extends Control

@onready var player_name_input = $MarginContainer/VBoxContainer/PlayerNameInput
@onready var ip_input = $MarginContainer/VBoxContainer/IPInput
@onready var lobby_list = $MarginContainer/VBoxContainer/LobbyList
@onready var refresh_btn = $MarginContainer/VBoxContainer/RefreshLobbies
@onready var join_btn = $MarginContainer/VBoxContainer/JoinButton
@onready var back_btn = $MarginContainer/VBoxContainer/BackButton
@onready var status_label = $MarginContainer/VBoxContainer/StatusLabel

var _focus_items: Array[Control] = []
var _focus_idx := 0
var _steam_lobbies: Array = []

func _ready():
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.steam_lobby_list_updated.connect(_on_lobby_list_updated)
	
	ip_input.text = "127.0.0.1"
	status_label.text = ""
	_update_ui_for_mode()
	_setup_focus()

func _update_ui_for_mode():
	var is_steam = NetworkManager.network_mode == NetworkManager.NetworkMode.STEAM
	ip_input.visible = not is_steam
	lobby_list.visible = is_steam
	refresh_btn.visible = is_steam
	if is_steam:
		join_btn.text = "Unirse a Sala"
		NetworkManager.request_lobby_list()
	else:
		join_btn.text = "Conectar"

func _setup_focus() -> void:
	if _focus_items.is_empty():
		var focus_style := StyleBoxFlat.new()
		focus_style.bg_color = Color(0.114, 0.114, 0.114, 1)
		focus_style.border_color = Color.WHITE
		focus_style.border_width_left = 3
		focus_style.border_width_top = 3
		focus_style.border_width_right = 3
		focus_style.border_width_bottom = 3
		focus_style.set_corner_radius_all(3)
		focus_style.set_expand_margin_all(5)
		var is_steam = NetworkManager.network_mode == NetworkManager.NetworkMode.STEAM
		if is_steam:
			_focus_items = [player_name_input, lobby_list, refresh_btn, join_btn, back_btn]
		else:
			_focus_items = [player_name_input, ip_input, join_btn, back_btn]
		for i in _focus_items.size():
			_focus_items[i].add_theme_stylebox_override("focus", focus_style)
			_focus_items[i].focus_entered.connect(_update_focus.bind(i))
	player_name_input.grab_focus()
	_focus_idx = 0

func _update_focus(i: int) -> void:
	_focus_idx = i

func _input(event):
	if event is InputEventKey and event.pressed and not event.is_echo():
		var kc = event.keycode
		var pkc = event.physical_keycode

		if (kc == KEY_ENTER or kc == KEY_KP_ENTER):
			if _focus_idx < _focus_items.size() and (_focus_items[_focus_idx] is LineEdit or _focus_items[_focus_idx] is TextEdit):
				_focus_items[_focus_idx].editable = not _focus_items[_focus_idx].editable
				get_viewport().set_input_as_handled()
				return

		if kc != KEY_W and kc != KEY_S and pkc != KEY_W and pkc != KEY_S:
			return

		var cur := _focus_items[_focus_idx]
		if (cur is LineEdit or cur is TextEdit) and cur.editable:
			return

		if (kc == KEY_W or pkc == KEY_W) and _focus_idx > 0:
			_focus_idx -= 1
			_focus_items[_focus_idx].grab_focus()
			AudioManager.play_sfx_ui(SfxId.MENU_MOVE)
			get_viewport().set_input_as_handled()
		elif (kc == KEY_S or pkc == KEY_S) and _focus_idx < _focus_items.size() - 1:
			_focus_idx += 1
			_focus_items[_focus_idx].grab_focus()
			AudioManager.play_sfx_ui(SfxId.MENU_MOVE)
			get_viewport().set_input_as_handled()

func _on_lobby_selected(index: int):
	if index < 0 or index >= _steam_lobbies.size():
		return
	var lobby_id = _steam_lobbies[index]
	var name_text = player_name_input.text.strip_edges()
	if name_text.is_empty():
		status_label.text = "Ingresá tu nombre."
		return
	AudioManager.play_sfx_ui(SfxId.SELECT)
	if NetworkManager.join_server(name_text, lobby_id):
		status_label.text = "Conectando..."
		join_btn.disabled = true

func _on_refresh_pressed():
	AudioManager.play_sfx_ui(SfxId.SELECT)
	_steam_lobbies.clear()
	lobby_list.clear()
	status_label.text = "Buscando salas..."
	NetworkManager.request_lobby_list()

func _on_lobby_list_updated(lobbies: Array):
	_steam_lobbies = lobbies
	lobby_list.clear()
	var _steam = Engine.get_singleton("Steam")
	for lobby_id in lobbies:
		var name_text = _steam.getLobbyData(lobby_id, "name")
		var map_text = _steam.getLobbyData(lobby_id, "map")
		var members = _steam.getNumLobbyMembers(lobby_id)
		var label = "%s | Mapa: %s | %d/%d" % [name_text, map_text, members, NetworkManager.MAX_PLAYERS]
		lobby_list.add_item(label)
	status_label.text = "Salas encontradas: %d" % lobbies.size()

func _on_join_pressed():
	AudioManager.play_sfx_ui(SfxId.SELECT)
	var _name = player_name_input.text.strip_edges()
	if _name.is_empty():
		status_label.text = "Ingresá tu nombre."
		return
	if NetworkManager.network_mode == NetworkManager.NetworkMode.STEAM:
		if lobby_list.get_selected_items().size() > 0:
			var idx = lobby_list.get_selected_items()[0]
			_on_lobby_selected(idx)
		else:
			status_label.text = "Seleccioná una sala de la lista"
		return
	var ip = ip_input.text.strip_edges()
	if NetworkManager.join_server(_name, ip):
		status_label.text = "Conectando..."
		join_btn.disabled = true
	else:
		status_label.text = "Error de conexión"

func _on_connection_succeeded():
	print("Conexión exitosa, cambiando a lobby...")
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/Lobby.tscn")

func _on_connection_failed():
	status_label.text = "Error: No se pudo conectar al servidor"
	join_btn.disabled = false
	back_btn.disabled = false

func _on_server_disconnected():
	status_label.text = "El servidor se desconectó"
	join_btn.disabled = false
	back_btn.disabled = false

func _on_back_pressed():
	AudioManager.play_sfx_ui(SfxId.SELECT)
	NetworkManager.disconnect_from_server()
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")

func _exit_tree():
	if NetworkManager.connection_succeeded.is_connected(_on_connection_succeeded):
		NetworkManager.connection_succeeded.disconnect(_on_connection_succeeded)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	if NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.server_disconnected.disconnect(_on_server_disconnected)
	if NetworkManager.steam_lobby_list_updated.is_connected(_on_lobby_list_updated):
		NetworkManager.steam_lobby_list_updated.disconnect(_on_lobby_list_updated)
