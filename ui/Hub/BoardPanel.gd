# res://ui/Hub/BoardPanel.gd
# Tablero de sala del hub: roster/AFK en una pestaña y configuración del
# host en otra. No muestra el personaje elegido por cada jugador.
extends Control

signal start_requested
signal cancel_requested
signal closed
signal map_selected(map_id: String)
signal afk_toggle_requested
signal host_action_requested(action: String, peer_id: int)

const FONT := preload("res://Fonts/deltarune font.ttf")

var _ui: Control
var _players_tab: Control
var _config_tab: Control
var _players_list: VBoxContainer
var _players_tab_btn: Button
var _config_tab_btn: Button
var _afk_btn: Button
var _start_btn: Button
var _cancel_btn: Button
var _status_label: Label
var _map_label: Label
var _info_label: Label
var _max_label: Label
var _max_minus: Button
var _max_plus: Button
var _action_buttons: Dictionary = {}
var _selected_pid := -1
var _can_manage := false
var _tab := 0
var _maps: Array = []
var _map_index := 0
var _countdown := 0.0


func _ready() -> void:
	add_to_group("hub_ui")
	add_to_group(GroupNames.GAME_MENU)
	# Ocultar la UI vieja del .tscn; construimos la nueva acá.
	var old_dim := get_node_or_null("Dim")
	var old_center := get_node_or_null("Center")
	if old_dim:
		old_dim.visible = false
	if old_center:
		old_center.visible = false
	_build_ui()
	visible = false


func is_open() -> bool:
	return visible


func open_panel(can_manage: bool) -> void:
	_can_manage = can_manage
	visible = true
	_tab = 0
	_refresh()
	_set_tab(0)
	if _players_tab_btn:
		_players_tab_btn.grab_focus()


func close_panel() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func set_status(text: String) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.visible = text != ""


func set_countdown(seconds: float) -> void:
	_countdown = maxf(seconds, 0.0)
	if _status_label:
		if _countdown > 0.0:
			_status_label.text = "INICIANDO EN %d..." % int(ceil(_countdown))
			_status_label.visible = true
		else:
			_status_label.text = ""
			_status_label.visible = false
	if _start_btn:
		_start_btn.disabled = _countdown > 0.0 or not _can_manage
	if _cancel_btn:
		_cancel_btn.visible = _countdown > 0.0 and _can_manage
	_refresh_config()


func refresh() -> void:
	if not visible:
		return
	_refresh()


func refresh_map_info() -> void:
	_refresh_map()


func _build_ui() -> void:
	_ui = Control.new()
	_ui.name = "LobbyUI"
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ui)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 600)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.025, 0.97)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.2, 0.8, 0.35, 1)
	style.content_margin_left = 26
	style.content_margin_top = 20
	style.content_margin_right = 26
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "SALA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55, 1))
	vbox.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 12)
	vbox.add_child(tabs)
	_players_tab_btn = _make_tab_button("JUGADORES")
	_players_tab_btn.pressed.connect(_set_tab.bind(0))
	tabs.add_child(_players_tab_btn)
	_config_tab_btn = _make_tab_button("CONFIGURACIÓN")
	_config_tab_btn.pressed.connect(_set_tab.bind(1))
	tabs.add_child(_config_tab_btn)

	var content := Control.new()
	content.custom_minimum_size = Vector2(760, 390)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content)

	_build_players_tab(content)
	_build_config_tab(content)

	_status_label = Label.new()
	_status_label.visible = false
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_override("font", FONT)
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(1, 0.75, 0.35, 1))
	vbox.add_child(_status_label)

	var close := Button.new()
	close.text = "CERRAR [X]"
	close.custom_minimum_size = Vector2(0, 38)
	close.add_theme_font_override("font", FONT)
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(close_panel)
	vbox.add_child(close)


func _build_players_tab(parent: Control) -> void:
	_players_tab = VBoxContainer.new()
	_players_tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_players_tab.add_theme_constant_override("separation", 8)
	parent.add_child(_players_tab)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(760, 250)
	_players_tab.add_child(scroll)

	_players_list = VBoxContainer.new()
	_players_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_players_list)

	_afk_btn = Button.new()
	_afk_btn.custom_minimum_size = Vector2(0, 38)
	_afk_btn.add_theme_font_override("font", FONT)
	_afk_btn.add_theme_font_size_override("font_size", 17)
	_afk_btn.pressed.connect(func() -> void: afk_toggle_requested.emit())
	_players_tab.add_child(_afk_btn)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	_players_tab.add_child(actions)
	_add_action_button(actions, "ESPECTADOR", "spectator")
	_add_action_button(actions, "SURVIVOR", "survivor")
	_add_action_button(actions, "KILLER", "killer")
	_add_action_button(actions, "EXPULSAR", "kick")


func _build_config_tab(parent: Control) -> void:
	_config_tab = VBoxContainer.new()
	_config_tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_config_tab.add_theme_constant_override("separation", 12)
	parent.add_child(_config_tab)

	var map_row := HBoxContainer.new()
	map_row.alignment = BoxContainer.ALIGNMENT_CENTER
	map_row.add_theme_constant_override("separation", 10)
	_config_tab.add_child(map_row)

	var prev := Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(48, 40)
	prev.add_theme_font_override("font", FONT)
	prev.add_theme_font_size_override("font_size", 20)
	prev.pressed.connect(_cycle_map.bind(-1))
	map_row.add_child(prev)

	_map_label = Label.new()
	_map_label.custom_minimum_size = Vector2(400, 40)
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_map_label.add_theme_font_override("font", FONT)
	_map_label.add_theme_font_size_override("font_size", 18)
	map_row.add_child(_map_label)

	var next := Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(48, 40)
	next.add_theme_font_override("font", FONT)
	next.add_theme_font_size_override("font_size", 20)
	next.pressed.connect(_cycle_map.bind(1))
	map_row.add_child(next)

	var max_row := HBoxContainer.new()
	max_row.alignment = BoxContainer.ALIGNMENT_CENTER
	max_row.add_theme_constant_override("separation", 10)
	_config_tab.add_child(max_row)
	var max_title := Label.new()
	max_title.text = "MÁXIMO JUGADORES"
	max_title.add_theme_font_override("font", FONT)
	max_title.add_theme_font_size_override("font_size", 16)
	max_row.add_child(max_title)
	_max_minus = Button.new()
	_max_minus.text = "-"
	_max_minus.custom_minimum_size = Vector2(42, 34)
	_max_minus.pressed.connect(_change_max_players.bind(-1))
	max_row.add_child(_max_minus)
	_max_label = Label.new()
	_max_label.custom_minimum_size = Vector2(60, 34)
	_max_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_max_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_max_label.add_theme_font_override("font", FONT)
	_max_label.add_theme_font_size_override("font_size", 18)
	max_row.add_child(_max_label)
	_max_plus = Button.new()
	_max_plus.text = "+"
	_max_plus.custom_minimum_size = Vector2(42, 34)
	_max_plus.pressed.connect(_change_max_players.bind(1))
	max_row.add_child(_max_plus)

	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_override("font", FONT)
	_info_label.add_theme_font_size_override("font_size", 16)
	_info_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.75, 1))
	_config_tab.add_child(_info_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_config_tab.add_child(spacer)

	_start_btn = Button.new()
	_start_btn.text = "INICIAR PARTIDA"
	_start_btn.custom_minimum_size = Vector2(0, 46)
	_start_btn.add_theme_font_override("font", FONT)
	_start_btn.add_theme_font_size_override("font_size", 21)
	_start_btn.pressed.connect(func() -> void: start_requested.emit())
	_config_tab.add_child(_start_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text = "CANCELAR INICIO"
	_cancel_btn.custom_minimum_size = Vector2(0, 38)
	_cancel_btn.add_theme_font_override("font", FONT)
	_cancel_btn.add_theme_font_size_override("font_size", 17)
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(func() -> void: cancel_requested.emit())
	_config_tab.add_child(_cancel_btn)


func _make_tab_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(180, 36)
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 17)
	return b


func _add_action_button(parent: HBoxContainer, text: String, action: String) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 36)
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(func() -> void:
		if _selected_pid > 0:
			host_action_requested.emit(action, _selected_pid)
	)
	_action_buttons[action] = b
	parent.add_child(b)


func _set_tab(tab: int) -> void:
	if tab == 1 and not _can_manage:
		tab = 0
	_tab = tab
	_players_tab.visible = tab == 0
	_config_tab.visible = tab == 1
	_players_tab_btn.disabled = tab == 0
	_config_tab_btn.disabled = tab == 1
	_config_tab_btn.visible = _can_manage
	_refresh()


func _refresh() -> void:
	if _ui == null:
		return
	_players_tab_btn.visible = true
	_config_tab_btn.visible = _can_manage
	_refresh_players()
	_refresh_map()
	_refresh_config()
	if _status_label and _countdown > 0.0:
		_status_label.text = "INICIANDO EN %d..." % int(ceil(_countdown))
		_status_label.visible = true


func _refresh_players() -> void:
	if _players_list == null:
		return
	for c in _players_list.get_children():
		c.queue_free()

	var ids: Array = LobbyManager.players.keys()
	ids.sort()
	if _selected_pid == -1 or not LobbyManager.players.has(_selected_pid):
		_selected_pid = multiplayer.get_unique_id() if LobbyManager.players.has(multiplayer.get_unique_id()) else (int(ids[0]) if not ids.is_empty() else -1)

	var candidates := LobbyManager.get_killer_candidates()
	for pid in ids:
		var info: Dictionary = LobbyManager.players[pid]
		var name := str(info.get("name", "Jugador %d" % int(pid)))
		var tags: Array[String] = []
		if LobbyManager.room_host_peer == int(pid) or bool(info.get("is_host", false)):
			tags.append("HOST")
		if LobbyManager.is_afk(pid):
			tags.append("AFK")
		if LobbyManager.is_spectator(pid):
			tags.append("ESPECTADOR")
		var presence := str(info.get("presence", "hub"))
		if presence == "match":
			tags.append("EN PARTIDA")
		elif presence == "spectate":
			tags.append("ESPECTANDO")
		if LobbyManager.forced_killer_peer == int(pid) or str(info.get("assigned_role", "")) == "killer":
			tags.append("KILLER")
		elif candidates.has(int(pid)):
			tags.append("CANDIDATO KILLER")
		var points := int(info.get("killer_points", 0))
		var text := "%s   %d pts" % [name, points]
		if not tags.is_empty():
			text += "   [" + " / ".join(tags) + "]"
		var row := Button.new()
		row.text = text
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(720, 34)
		row.add_theme_font_override("font", FONT)
		row.add_theme_font_size_override("font_size", 16)
		if int(pid) == _selected_pid:
			row.add_theme_color_override("font_color", Color(1, 0.9, 0.35, 1))
		row.pressed.connect(_select_player.bind(int(pid)))
		_players_list.add_child(row)

	var my_id := multiplayer.get_unique_id()
	if _afk_btn:
		_afk_btn.text = "AFK: SÍ" if LobbyManager.is_afk(my_id) else "AFK: NO"
		_afk_btn.disabled = LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY \
			or not LobbyManager.can_local_toggle_afk()
	for action in _action_buttons:
		var b: Button = _action_buttons[action]
		b.visible = _can_manage
		b.disabled = not _can_manage or _selected_pid <= 0


func _select_player(pid: int) -> void:
	_selected_pid = pid
	_refresh_players()


func _refresh_map() -> void:
	_maps = MapRegistry.get_all()
	_maps.sort_custom(func(a, b) -> bool:
		return str(a.display_name).naturalnocasecmp_to(str(b.display_name)) < 0
	)
	var map_id := LobbyManager.selected_map
	var map_name := "SIN MAPA"
	_map_index = 0
	for i in _maps.size():
		if str(_maps[i].id) == map_id:
			_map_index = i
			map_name = str(_maps[i].display_name)
			break
	if _map_label:
		_map_label.text = "MAPA: " + map_name
	# Los botones de mapa se deshabilitan si no es host o hay partida.
	for child in _config_tab.get_children():
		if child is HBoxContainer:
			for c in child.get_children():
				if c is Button and (c.text == "<" or c.text == ">"):
					c.disabled = not _can_manage or LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY


func _refresh_config() -> void:
	if _info_label == null:
		return
	var mode := LobbyManager.game_mode if LobbyManager.game_mode != "" else "Escape"
	_info_label.text = "Modo: %s    Sala: %s" % [
		mode,
		LobbyManager.room_name if LobbyManager.room_name != "" else "—"
	]
	if _max_label:
		_max_label.text = str(LobbyManager.max_players)
	if _max_minus:
		_max_minus.disabled = not _can_manage or LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY
	if _max_plus:
		_max_plus.disabled = not _can_manage or LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY
	if _start_btn:
		var enough := LobbyManager.get_active_participants().size() >= 2 or DevMode.is_enabled()
		var map_ok := LobbyManager.selected_map != "" and MapRegistry.has_map(LobbyManager.selected_map)
		var can_start := _can_manage and LobbyManager.current_phase == LobbyManager.GamePhase.LOBBY \
			and _countdown <= 0.0 and enough and map_ok
		_start_btn.disabled = not can_start
		_start_btn.text = "INICIAR PARTIDA" if _can_manage else "ESPERANDO AL HOST"
	if _cancel_btn:
		_cancel_btn.visible = _can_manage and _countdown > 0.0


func _cycle_map(direction: int) -> void:
	if not _can_manage or LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY:
		return
	if _maps.size() <= 1:
		return
	_map_index = (_map_index + direction + _maps.size()) % _maps.size()
	map_selected.emit(str(_maps[_map_index].id))


func _change_max_players(direction: int) -> void:
	if not _can_manage or LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY:
		return
	LobbyManager.request_set_max_players(LobbyManager.max_players + direction)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu_cancel") \
			or event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()
		close_panel()
