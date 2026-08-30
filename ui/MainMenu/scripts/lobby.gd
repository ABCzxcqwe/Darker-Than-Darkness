extends Control
##  Lobby — verde #008000/#00FF00 soul rojo, casi fullscreen, teclado-only Z/X

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
	_apply_theme()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.connect(_on_theme_changed)
	add_to_group("lobby")

func _on_theme_changed(_id: String) -> void:
	_apply_theme()
	_update_player_list()

func _apply_theme() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null:
		return
	var bg := get_node_or_null("Background")
	if bg and tm.has_method("apply_to_background"):
		tm.apply_to_background(bg)
	var box := get_node_or_null("CenterContainer/DeltaruneBox") as PanelContainer
	if box and tm.has_method("make_box_style"):
		box.add_theme_stylebox_override("panel", tm.make_box_style())
	var title := get_node_or_null("CenterContainer/DeltaruneBox/Margin/VBox/Title") as Label
	var sep := get_node_or_null("CenterContainer/DeltaruneBox/Margin/VBox/Separator") as ColorRect
	var footer := get_node_or_null("Footer") as Label
	var list_box := get_node_or_null("CenterContainer/DeltaruneBox/Margin/VBox/ListBox") as PanelContainer
	var pal: Dictionary = tm.get_palette() if tm.has_method("get_palette") else {}
	if title:
		title.add_theme_color_override("font_color", pal.get("title", Color(0,1,0,1)))
		if tm.has_method("get_font"):
			var f: FontFile = tm.get_font()
			if f:
				title.add_theme_font_override("font", f)
	if sep:
		sep.color = pal.get("separator", pal.get("border", Color(0,0.5,0,1)))
	if list_box and tm.has_method("make_box_style"):
		list_box.add_theme_stylebox_override("panel", tm.make_box_style())
	if _hint:
		_hint.add_theme_color_override("font_color", pal.get("hint", Color(0,1,0,1)))
	if footer:
		footer.add_theme_color_override("font_color", pal.get("dim", Color(0.5,0.5,0.5,1)))
	var players_header := get_node_or_null("CenterContainer/DeltaruneBox/Margin/VBox/PlayersHeader") as Label
	if players_header:
		players_header.add_theme_color_override("font_color", pal.get("dim", Color(0,0.5,0,1)))
	if _status_label:
		_status_label.add_theme_color_override("font_color", pal.get("hint", Color(0,1,0,1)))
	if _empty_label:
		_empty_label.add_theme_color_override("font_color", pal.get("hint", Color(0,1,0,1)))
	if _soul and tm.has_method("get_soul_texture"):
		var st: Texture2D = tm.get_soul_texture()
		if st:
			_soul.texture = st
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
		var tm2 := get_node_or_null("/root/ThemeManager")
		var pal2: Dictionary = tm2.get_palette() if tm2 and tm2.has_method("get_palette") else {}
		_map_label.add_theme_color_override("font_color", pal2.get("hint", Color(0, 1, 0, 1)))
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
			var tm3 := get_node_or_null("/root/ThemeManager")
			var pal3: Dictionary = tm3.get_palette() if tm3 and tm3.has_method("get_palette") else {}
			var sel_c: Color = pal3.get("selected", Color(0,1,0,1))
			var dim_c: Color = pal3.get("dim", Color(0,0.5,0,1))
			var name_lbl := Label.new()
			name_lbl.text = str(p.get("name", "?"))
			if bool(p.get("is_host", false)):
				name_lbl.text += " (HOST)"
			name_lbl.add_theme_font_override("font", preload("res://Fonts/deltarune font.ttf"))
			name_lbl.add_theme_font_size_override("font_size", 18)
			name_lbl.custom_minimum_size = Vector2(200, 0)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.modulate = sel_c if bool(p.get("is_host", false)) else dim_c
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
			char_lbl.modulate = dim_c
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
			var tm4 := get_node_or_null("/root/ThemeManager")
			var pal4: Dictionary = tm4.get_palette() if tm4 and tm4.has_method("get_palette") else {}
			_empty_label.modulate = pal4.get("hint", Color(0,1,0,1))

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
	var tm := get_node_or_null("/root/ThemeManager")
	var pal: Dictionary = tm.get_palette() if tm and tm.has_method("get_palette") else {}
	var sel: Color = pal.get("selected", Color(0,1,0,1))
	var dim: Color = pal.get("dim", Color(0,0.50196081,0,1))
	for i in _focusables.size():
		var c := _focusables[i]
		if not is_instance_valid(c):
			continue
		if c is Button:
			c.modulate = sel if i == idx else dim
			if c.disabled:
				c.modulate = Color(dim.r, dim.g, dim.b, 0.5)
	if _hint:
		var cur := _focusables[idx]
		var lm := get_node_or_null("/root/LobbyManager")
		if cur == _start_btn:
			if lm and lm.has_method("get_player_list"):
				var cnt: int = lm.players.size() if "players" in lm else 0
				var maxp: int = lm.max_players if "max_players" in lm else 4
				if cnt < 2:
					_hint.text = "Inicia selección de personaje — %d/%d falta 1 jugador" % [cnt, maxp]
				else:
					_hint.text = "Inicia selección de personaje — %d/%d listo" % [cnt, maxp]
			else:
				_hint.text = "Inicia selección de personaje — requiere 2 jugadores"
		elif cur == _leave_btn:
			_hint.text = "Salir y volver al buscador"

func _position_soul(idx: int, instant: bool) -> void:
	if _soul == null or _focusables.is_empty():
		return
	if idx < 0 or idx >= _focusables.size():
		return
	var t := _focusables[idx]
	if not is_instance_valid(t) or not t.is_visible_in_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(t) or not is_instance_valid(_soul):
		return
	if not t.is_visible_in_tree():
		return
	var soul_h := _soul.size.y if _soul.size.y > 0 else 20.0
	var dest := t.global_position + Vector2(-28, (t.size.y - soul_h)/2.0) - global_position
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
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.disconnect(_on_theme_changed)
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
