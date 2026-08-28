extends Control
## Mock Lobby — verde #008000/#00FF00 soul rojo, casi fullscreen, teclado-only Z/X

var _focusables: Array[Control] = []
var _index := 0

@onready var _soul: TextureRect = $SoulCursor
@onready var _map_label: Label = $CenterContainer/DeltaruneBox/Margin/VBox/MapLabel
@onready var _player_container: VBoxContainer = $CenterContainer/DeltaruneBox/Margin/VBox/ListBox/MarginList/VBoxList/Rooms
@onready var _empty_label: Label = $CenterContainer/DeltaruneBox/Margin/VBox/ListBox/MarginList/VBoxList/EmptyLabel
@onready var _status_label: Label = $CenterContainer/DeltaruneBox/Margin/VBox/StatusLabel
@onready var _start_btn: Button = $CenterContainer/DeltaruneBox/Margin/VBox/Actions/StartBtn
@onready var _leave_btn: Button = $CenterContainer/DeltaruneBox/Margin/VBox/Actions/LeaveBtn
@onready var _hint: Label = $CenterContainer/DeltaruneBox/Margin/VBox/HintLabel

func _ready() -> void:
	var am0 := get_node_or_null("/root/AudioManager")
	if am0 and am0.has_method("play_menu_drone") and am0.current_global_state != "menu_drone":
		am0.play_menu_drone()
	add_to_group("lobby")
	_update_from_lobby()
	var lm := get_node_or_null("/root/LobbyManager")
	var nm := get_node_or_null("/root/NetworkManager")
	if lm:
		if not lm.lobby_updated.is_connected(_update_player_list):
			lm.lobby_updated.connect(_update_player_list)
		if not lm.player_joined.is_connected(_on_player_joined):
			lm.player_joined.connect(_on_player_joined)
		if not lm.player_left.is_connected(_on_player_left):
			lm.player_left.connect(_on_player_left)
	if nm and not nm.server_disconnected.is_connected(_on_server_disconnected):
		nm.server_disconnected.connect(_on_server_disconnected)
	_rebuild_focus()
	_highlight(_index, true)
	_position_soul(_index, true)
	grab_focus()

func _rebuild_focus() -> void:
	_focusables.clear()
	var lm := get_node_or_null("/root/LobbyManager")
	var is_host: bool = lm.is_host if lm else false
	_start_btn.visible = is_host
	# Si no es host, solo Leave es focuseable
	if is_host:
		_focusables.append(_start_btn)
	_focusables.append(_leave_btn)
	# Deshabilitar Start si menos de 2 jugadores
	if is_host and lm:
		_start_btn.disabled = lm.players.size() < 2
	else:
		if _start_btn:
			_start_btn.disabled = false
	_index = clampi(_index, 0, max(0, _focusables.size() - 1))

func _update_from_lobby() -> void:
	var lm := get_node_or_null("/root/LobbyManager")
	var map_id: String = lm.selected_map if lm else ""
	var map_name: String = map_id
	var room_name: String = lm.room_name if lm and lm.room_name != "" else ""
	var game_mode: String = lm.game_mode if lm else "Escape"
	var mr := get_node_or_null("/root/MapRegistry")
	if lm and mr and mr.has_map(map_id):
		var md = mr.get_map(map_id)
		if md:
			map_name = md.display_name
	if _map_label:
		var prefix := ""
		if room_name != "":
			prefix = room_name + " | "
		_map_label.text = prefix + "MAPA: " + (map_name if map_name != "" else "Cargando...") + " | MODO: " + game_mode
		_map_label.add_theme_color_override("font_color", Color(0, 1, 0, 1))
	_update_player_list()

func _update_player_list() -> void:
	if _player_container == null:
		return
	for c in _player_container.get_children():
		if is_instance_valid(c):
			c.free()
	var lm := get_node_or_null("/root/LobbyManager")
	if lm == null:
		_refresh_empty(true)
		return
	var players: Array = lm.get_player_list() if lm.has_method("get_player_list") else []
	if players.is_empty():
		_refresh_empty(true)
	else:
		_refresh_empty(false)
		for p in players:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var name_lbl := Label.new()
			name_lbl.text = str(p.get("name", "?"))
			if bool(p.get("is_host", false)):
				name_lbl.text += " (HOST)"
			name_lbl.add_theme_font_override("font", preload("res://Fonts/deltarune font.ttf"))
			name_lbl.add_theme_font_size_override("font_size", 18)
			name_lbl.custom_minimum_size = Vector2(200, 0)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.modulate = Color(0, 1, 0, 1) if bool(p.get("is_host", false)) else Color(0, 0.50196081, 0, 1)
			row.add_child(name_lbl)
			var char_lbl := Label.new()
			var cid: int = int(p.get("character_id", -1))
			var char_name: String = "?"
			if cid != -1:
				var cr := get_node_or_null("/root/CharacterRegistry")
				if cr and cr.has_method("get_character"):
					var data = cr.get_character(cid)
					if data:
						char_name = str(data.display_name)
			char_lbl.text = char_name
			char_lbl.add_theme_font_override("font", preload("res://Fonts/deltarune font.ttf"))
			char_lbl.add_theme_font_size_override("font_size", 16)
			char_lbl.modulate = Color(0, 0.50196081, 0, 1)
			char_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			char_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(char_lbl)
			_player_container.add_child(row)
	var lm2 := get_node_or_null("/root/LobbyManager")
	if _status_label and lm2:
		var maxp: int = lm2.max_players if "max_players" in lm2 else lm2.MAX_PLAYERS
		_status_label.text = "Jugadores: %d/%d" % [lm2.players.size(), maxp]
	_rebuild_focus()
	_highlight(_index, false)
	_position_soul(_index, false)

func _refresh_empty(is_empty: bool) -> void:
	if _empty_label:
		_empty_label.visible = is_empty
		if is_empty:
			_empty_label.text = "Esperando jugadores..."
			_empty_label.modulate = Color(0, 1, 0, 1)

func _unhandled_input(event: InputEvent) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	if event.is_action_pressed("menu_up"):
		_move(-1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		_move(1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_accept") or event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_Z):
		_confirm()
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		_on_leave_pressed()
		vp.set_input_as_handled()

func _move(dir: int) -> void:
	if _focusables.is_empty():
		return
	var ni := clampi(_index + dir, 0, _focusables.size() - 1)
	if ni == _index:
		return
	_index = ni
	_highlight(_index, false)
	_position_soul(_index, false)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)

func _highlight(idx: int, instant: bool) -> void:
	if _focusables.is_empty():
		return
	idx = clampi(idx, 0, _focusables.size() - 1)
	for i in _focusables.size():
		var c := _focusables[i]
		if not is_instance_valid(c):
			continue
		if c is Button:
			c.modulate = Color(0, 1, 0, 1) if i == idx else Color(0, 0.50196081, 0, 1)
			if c.disabled:
				c.modulate = Color(0, 0.50196081, 0, 0.5)
	if _hint:
		var cur := _focusables[idx]
		if cur == _start_btn:
			_hint.text = "Iniciar partida [Z] (host)"
		elif cur == _leave_btn:
			_hint.text = "Salir del lobby [X]"

func _position_soul(idx: int, instant: bool) -> void:
	if _soul == null or _focusables.is_empty():
		return
	if idx < 0 or idx >= _focusables.size():
		return
	var t := _focusables[idx]
	if not is_instance_valid(t):
		return
	await get_tree().process_frame
	if not is_instance_valid(t):
		return
	var dest := t.global_position + Vector2(-28, (t.size.y - _soul.size.y)/2.0) - global_position
	if instant:
		_soul.position = dest
	else:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_soul, "position", dest, 0.08)

func _confirm() -> void:
	if _focusables.is_empty():
		return
	var cur := _focusables[_index]
	if cur == _start_btn:
		_on_start_pressed()
	elif cur == _leave_btn:
		_on_leave_pressed()

func _on_player_joined(_peer_id: int, _info: Dictionary) -> void:
	_update_player_list()

func _on_player_left(_peer_id: int) -> void:
	_update_player_list()

func _on_server_disconnected() -> void:
	if not is_inside_tree():
		return
	if _status_label:
		_status_label.text = "Host desconectado. Volviendo al menú..."
		_status_label.modulate = Color(0, 1, 0, 1)

func _on_start_pressed() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.SELECT)
	var lm := get_node_or_null("/root/LobbyManager")
	if lm == null or not lm.is_host:
		return
	if lm.players.size() < 2:
		if _status_label:
			_status_label.text = "No hay suficientes jugadores."
			_status_label.modulate = Color(0, 1, 0, 1)
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.ERROR)
		return
	lm.host_start_character_selection()

func _on_leave_pressed() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.SELECT)
	if not is_inside_tree():
		return
	var mc := get_node_or_null("/root/MatchCoordinator")
	if mc and mc.has_method("reset_to_menu"):
		mc.reset_to_menu()
	else:
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")

func _exit_tree() -> void:
	var lm := get_node_or_null("/root/LobbyManager")
	if lm:
		if lm.lobby_updated.is_connected(_update_player_list):
			lm.lobby_updated.disconnect(_update_player_list)
		if lm.player_joined.is_connected(_on_player_joined):
			lm.player_joined.disconnect(_on_player_joined)
		if lm.player_left.is_connected(_on_player_left):
			lm.player_left.disconnect(_on_player_left)
	var nm := get_node_or_null("/root/NetworkManager")
	if nm and nm.server_disconnected.is_connected(_on_server_disconnected):
		nm.server_disconnected.disconnect(_on_server_disconnected)
