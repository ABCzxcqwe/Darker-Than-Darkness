extends Control
## CreateRoom — funcional, crea lobby real, soul rojo, datos sala + modo juego

const GAME_MODES := ["Escape"] # Juggernaut bloqueado

var _map_idx := 0
var _game_mode_idx := 0
var _max_players: int = 4
var _focus_idx := 0 # 0=Nombre, 1=Mapa, 2=Modo juego (bloqueado), 3=Jugadores, 4=Crear, 5=Volver
var _field_nodes: Array[Control] = []
var _busy := false
var _available_maps: Array = []

@onready var _soul: TextureRect = $SoulCursor
@onready var _title: Label = $CenterContainer/DeltaruneBox/Margin/VBox/Title
@onready var _name_edit: LineEdit = $CenterContainer/DeltaruneBox/Margin/VBox/NameRow/NameInput
@onready var _map_label: Label = $CenterContainer/DeltaruneBox/Margin/VBox/MapRow/MapLabel
@onready var _hint: Label = $CenterContainer/DeltaruneBox/Margin/VBox/HintLabel
@onready var _mode_label: Label = $CenterContainer/DeltaruneBox/Margin/VBox/ModeRow/ModeValue
@onready var _game_mode_label: Label = $CenterContainer/DeltaruneBox/Margin/VBox/GameModeRow/GameModeLabel
@onready var _players_label: Label = $CenterContainer/DeltaruneBox/Margin/VBox/PlayersRow/PlayersLabel

func _ready() -> void:
	var am0 := get_node_or_null("/root/AudioManager")
	if am0 and am0.has_method("play_menu_drone") and am0.current_global_state != "menu_drone":
		am0.play_menu_drone()
	var sm := get_node_or_null("/root/SettingsManager")
	var nm := get_node_or_null("/root/NetworkManager")
	# Mostrar modo red actual desde SettingsManager (no mock cfg)
	var net_mode_str := "LAN"
	if sm and sm.network_mode == 1:
		net_mode_str = "ONLINE"
	elif nm and nm.network_mode == 1:
		net_mode_str = "ONLINE"
	if _mode_label:
		_mode_label.text = net_mode_str
	var mr := get_node_or_null("/root/MapRegistry")
	if mr:
		_available_maps = mr.get_all()
	if _available_maps.is_empty():
		_map_label.text = "Sin mapas"
	else:
		_map_idx = 0
		_map_label.text = _available_maps[0].display_name
	_game_mode_label.text = GAME_MODES[_game_mode_idx]
	if _players_label:
		_players_label.text = str(_max_players)
	_name_edit.text = ""
	_name_edit.placeholder_text = "Mi sala"
	_field_nodes = [_name_edit, _map_label, _game_mode_label, _players_label, $CenterContainer/DeltaruneBox/Margin/VBox/Actions/CreateBtn, $CenterContainer/DeltaruneBox/Margin/VBox/Actions/BackBtn]
	if has_node("/root/NetworkManager"):
		var nmm := get_node_or_null("/root/NetworkManager")
		if nmm and not nmm.connection_succeeded.is_connected(_on_server_created):
			nmm.connection_succeeded.connect(_on_server_created)
		if nmm and not nmm.connection_failed.is_connected(_on_create_failed):
			nmm.connection_failed.connect(_on_create_failed)
	grab_focus()
	_highlight(_focus_idx)
	_position_soul(_focus_idx, true)

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var editing := _field_nodes[_focus_idx] == _name_edit and _name_edit.has_focus()
	if editing and event is InputEventKey and event.pressed and event.keycode != KEY_ENTER and event.keycode != KEY_KP_ENTER and event.keycode != KEY_ESCAPE and event.unicode == 0:
		if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down"):
			pass
		else:
			return
	if event.is_action_pressed("menu_up"):
		_move_vert(-1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		_move_vert(1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_left"):
		if _focus_idx == 1:
			_change_map(-1)
			vp.set_input_as_handled()
		elif _focus_idx == 2:
			_change_game_mode(-1)
			vp.set_input_as_handled()
		elif _focus_idx == 3:
			_change_max_players(-1)
			vp.set_input_as_handled()
	elif event.is_action_pressed("menu_right"):
		if _focus_idx == 1:
			_change_map(1)
			vp.set_input_as_handled()
		elif _focus_idx == 2:
			_change_game_mode(1)
			vp.set_input_as_handled()
		elif _focus_idx == 3:
			_change_max_players(1)
			vp.set_input_as_handled()
	elif event.is_action_pressed("menu_accept") or event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_Z):
		if editing and (event is InputEventKey and event.keycode == KEY_Z and event.unicode != 0):
			return
		_confirm()
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		_go_back()
		vp.set_input_as_handled()

func _move_vert(dir: int) -> void:
	var ni := clampi(_focus_idx + dir, 0, _field_nodes.size() - 1)
	if ni == _focus_idx:
		return
	_focus_idx = ni
	_highlight(_focus_idx)
	_position_soul(_focus_idx, false)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)
	if _field_nodes[_focus_idx] == _name_edit:
		_name_edit.grab_focus()
	else:
		if _name_edit.has_focus():
			_name_edit.release_focus()

func _highlight(idx: int) -> void:
	for i in _field_nodes.size():
		var c := _field_nodes[i]
		if c is LineEdit:
			c.modulate = Color(0, 1, 0, 1) if i == idx else Color(0, 0.50196081, 0, 1)
		elif c is Label:
			c.modulate = Color(0, 1, 0, 1) if i == idx else Color(0, 0.50196081, 0, 1)
		elif c is Button:
			c.modulate = Color(0, 1, 0, 1) if i == idx else Color(0, 0.50196081, 0, 1)
	if _hint:
		match idx:
			0: _hint.text = "Escribe nombre de sala"
			1: _hint.text = "< > cambiar mapa"
			2: _hint.text = "Modo fijo: Escape (Supervivencia)"
			3: _hint.text = "< > cambiar jugadores 2..10"
			4: _hint.text = "Crear sala [Z]"
			5: _hint.text = "Volver [X]"

func _position_soul(idx: int, instant: bool) -> void:
	if _soul == null or _field_nodes.is_empty():
		return
	await get_tree().process_frame
	var target: Control = _field_nodes[idx]
	if not is_instance_valid(target):
		return
	var dest := target.global_position + Vector2(-28, (target.size.y - _soul.size.y)/2.0) - global_position
	if instant:
		_soul.position = dest
	else:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_soul, "position", dest, 0.08)

func _change_map(dir: int) -> void:
	if _available_maps.is_empty():
		return
	_map_idx = clampi(_map_idx + dir, 0, _available_maps.size() - 1)
	var m = _available_maps[_map_idx]
	_map_label.text = m.display_name if m else "Sin mapa"
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)

func _change_game_mode(dir: int) -> void:
	if GAME_MODES.size() <= 1:
		var am0 := get_node_or_null("/root/AudioManager")
		if am0 and am0.has_method("play_sfx_ui"):
			am0.play_sfx_ui(SfxId.ERROR)
		if _hint:
			_hint.text = "Modo Juggernaut no disponible"
		return
	_game_mode_idx = clampi(_game_mode_idx + dir, 0, GAME_MODES.size() - 1)
	_game_mode_label.text = GAME_MODES[_game_mode_idx]
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)

func _change_max_players(dir: int) -> void:
	_max_players = clampi(_max_players + dir, 2, 10)
	if _players_label:
		_players_label.text = str(_max_players)
	var am2 := get_node_or_null("/root/AudioManager")
	if am2 and am2.has_method("play_sfx_ui"):
		am2.play_sfx_ui(SfxId.MENU_MOVE)

func _confirm() -> void:
	if _focus_idx == 0:
		_move_vert(1)
		return
	if _focus_idx == 1:
		_move_vert(1)
		return
	if _focus_idx == 2:
		_move_vert(1)
		return
	if _focus_idx == 3:
		_move_vert(1)
		return
	if _focus_idx == 4:
		_try_create()
		return
	if _focus_idx == 5:
		_go_back()

func _try_create() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.SELECT)
	var sala_name: String = _name_edit.text.strip_edges()
	if sala_name.is_empty():
		_hint.text = "Ingresa nombre de sala."
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.ERROR)
		return
	if _available_maps.is_empty():
		_hint.text = "No hay mapas."
		return
	var idx: int = clampi(_map_idx, 0, _available_maps.size() - 1)
	var map_data = _available_maps[idx]
	var sm := get_node_or_null("/root/SettingsManager")
	var player_name: String = sm.player_name if sm and sm.player_name != "" else "Jugador"
	if player_name.strip_edges() == "":
		player_name = "Jugador"
	var game_mode: String = GAME_MODES[_game_mode_idx]
	var nm := get_node_or_null("/root/NetworkManager")
	if nm == null:
		_hint.text = "NetworkManager no encontrado"
		return
	_busy = true
	_hint.text = "Creando sala..."
	var success: bool = nm.create_server(player_name, map_data.id, sala_name, game_mode, _max_players)
	if not success:
		_busy = false
		_hint.text = "Error al crear el servidor."
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.ERROR)

func _on_server_created() -> void:
	_busy = false
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/Lobby.tscn")

func _on_create_failed() -> void:
	_busy = false
	_hint.text = "Error al crear lobby (Steam no disponible?)"
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.ERROR)

func _go_back() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.SELECT)
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/ServerBrowser.tscn")

func _exit_tree() -> void:
	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		if nm.connection_succeeded.is_connected(_on_server_created):
			nm.connection_succeeded.disconnect(_on_server_created)
		if nm.connection_failed.is_connected(_on_create_failed):
			nm.connection_failed.disconnect(_on_create_failed)
