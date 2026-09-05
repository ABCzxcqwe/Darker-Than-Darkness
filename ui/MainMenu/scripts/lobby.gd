extends Control
##  Lobby — verde #008000/#00FF00 soul rojo, casi fullscreen, teclado-only Z/X
##  Host puede seleccionar jugadores y aplicar: espectador / forzar killer / kick

var _focusables: Array[Control] = []
var _index := 0
var _player_ids: Array[int] = []

var _action_visible := false
var _action_index := 0
var _selected_target_id: int = -1
var _selected_target_name: String = ""

var _confirm_visible := false
var _confirm_index := 0 # 0 = SI, 1 = NO

@onready var _soul: TextureRect = $SoulCursor
@onready var _map_label: Label = $CenterContainer/DeltaruneBox/Margin/VBox/MapLabel
@onready var _player_container: VBoxContainer = $CenterContainer/DeltaruneBox/Margin/VBox/ListBox/MarginList/VBoxList/Rooms
@onready var _empty_label: Label = $CenterContainer/DeltaruneBox/Margin/VBox/ListBox/MarginList/VBoxList/EmptyLabel
@onready var _status_label: Label = $CenterContainer/DeltaruneBox/Margin/VBox/StatusLabel
@onready var _start_btn: Button = $CenterContainer/DeltaruneBox/Margin/VBox/Actions/StartBtn
@onready var _lobby3d_btn: Button = $CenterContainer/DeltaruneBox/Margin/VBox/Actions/Lobby3DBtn
@onready var _leave_btn: Button = $CenterContainer/DeltaruneBox/Margin/VBox/Actions/LeaveBtn
@onready var _hint: Label = $CenterContainer/DeltaruneBox/Margin/VBox/HintLabel
@onready var _action_menu: PanelContainer = $ActionMenu
@onready var _action_target: Label = $ActionMenu/MarginAction/VBoxAction/ActionTarget
@onready var _btn_spectator: Button = $ActionMenu/MarginAction/VBoxAction/BtnSpectator
@onready var _btn_survivor: Button = $ActionMenu/MarginAction/VBoxAction/BtnSurvivor
@onready var _btn_killer: Button = $ActionMenu/MarginAction/VBoxAction/BtnKiller
@onready var _btn_kick: Button = $ActionMenu/MarginAction/VBoxAction/BtnKick
@onready var _btn_cancel: Button = $ActionMenu/MarginAction/VBoxAction/BtnCancel
@onready var _confirm_overlay: PanelContainer = $ConfirmOverlay
@onready var _confirm_label: Label = $ConfirmOverlay/MarginConfirm/VBoxConfirm/ConfirmLabel
@onready var _confirm_yes: Button = $ConfirmOverlay/MarginConfirm/VBoxConfirm/HBoxConfirm/ConfirmYes
@onready var _confirm_no: Button = $ConfirmOverlay/MarginConfirm/VBoxConfirm/HBoxConfirm/ConfirmNo

var _action_focusables: Array[Control] = []

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
	# Action menu theming
	if _action_menu and tm.has_method("make_box_style"):
		_action_menu.add_theme_stylebox_override("panel", tm.make_box_style())
	if _confirm_overlay and tm.has_method("make_box_style"):
		_confirm_overlay.add_theme_stylebox_override("panel", tm.make_box_style())
	# Botones con estilo del tema (igual que server_browser, sin helper nuevo)
	var pal_btn: Dictionary = tm.get_palette() if tm.has_method("get_palette") else {}
	var sel_btn: Color = pal_btn.get("selected", Color(0,1,0,1))
	var theme_font_btn: FontFile = tm.get_font() if tm.has_method("get_font") else null
	for btn in [_start_btn, _lobby3d_btn, _leave_btn, _btn_spectator, _btn_survivor, _btn_killer, _btn_kick, _btn_cancel, _confirm_yes, _confirm_no]:
		if btn == null:
			continue
		btn.add_theme_color_override("font_color", sel_btn)
		if theme_font_btn:
			btn.add_theme_font_override("font", theme_font_btn)
		if tm.has_method("make_box_style"):
			btn.add_theme_stylebox_override("normal", tm.make_box_style())
	# Colores de etiquetas dentro del ActionMenu / ConfirmOverlay
	if _action_target:
		_action_target.add_theme_color_override("font_color", pal.get("title", sel_btn))
		if tm.has_method("get_font"):
			var f2: FontFile = tm.get_font()
			if f2:
				_action_target.add_theme_font_override("font", f2)
	if _confirm_label:
		_confirm_label.add_theme_color_override("font_color", pal.get("hint", sel_btn))
	var action_title := get_node_or_null("ActionMenu/MarginAction/VBoxAction/ActionTitle") as Label
	if action_title:
		action_title.add_theme_color_override("font_color", pal.get("title", sel_btn))
		if tm.has_method("get_font"):
			var f3: FontFile = tm.get_font()
			if f3:
				action_title.add_theme_font_override("font", f3)
		var sep_a := get_node_or_null("ActionMenu/MarginAction/VBoxAction/ActionSeparator") as ColorRect
		if sep_a:
			sep_a.color = pal.get("separator", pal.get("border", Color(0,0.5,0,1)))
	var confirm_sep := get_node_or_null("ConfirmOverlay/MarginConfirm/VBoxConfirm/Separator") as ColorRect
	if confirm_sep:
		confirm_sep.color = pal.get("separator", pal.get("border", Color(0,0.5,0,1)))
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
		if lm.has_signal("kicked") and not lm.kicked.is_connected(_on_kicked):
			lm.kicked.connect(_on_kicked)
	if nm and not nm.server_disconnected.is_connected(_on_server_disconnected):
		nm.server_disconnected.connect(_on_server_disconnected)
	_rebuild_focus()
	_highlight(_index, true)
	_position_soul(_index, true)
	grab_focus()

func _rebuild_focus() -> void:
	_focusables.clear()
	_player_ids.clear()
	var lm := get_node_or_null("/root/LobbyManager")
	var is_host: bool = lm.is_host if lm else false
	_start_btn.visible = is_host
	# Recolectar player rows ya creados: están en _player_container
	if is_host and _player_container:
		for child in _player_container.get_children():
			if child.has_meta("peer_id"):
				_focusables.append(child)
				_player_ids.append(int(child.get_meta("peer_id")))
	if is_host:
		_focusables.append(_start_btn)
	# LOBBY 3D visible para todos, entrada individual
	_focusables.append(_lobby3d_btn)
	_focusables.append(_leave_btn)
	if is_host and lm:
		var cnt: int = lm.players.size()
		var cands: Array = lm.get_killer_candidates() if lm.has_method("get_killer_candidates") else []
		_start_btn.disabled = cnt < 2 or cands.is_empty()
	else:
		if _start_btn:
			_start_btn.disabled = false
	_index = clampi(_index, 0, max(0, _focusables.size() - 1))

func _rebuild_action_focus() -> void:
	_action_focusables.clear()
	_action_focusables.append(_btn_spectator)
	_action_focusables.append(_btn_survivor)
	_action_focusables.append(_btn_killer)
	_action_focusables.append(_btn_kick)
	_action_focusables.append(_btn_cancel)
	_action_index = clampi(_action_index, 0, _action_focusables.size() - 1)

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
	# Construir role_tags: una sola etiqueta KILLER/CANDIDATO por proximo killer
	var role_tags: Dictionary = {}
	var forced: int = lm.forced_killer_peer if "forced_killer_peer" in lm else -1
	var forced_valid: bool = forced != -1 and lm.players.has(forced) and not lm.is_spectator(forced)
	if forced_valid:
		role_tags[forced] = "killer_forced"
	else:
		var candidates: Array[int] = lm.get_killer_candidates() if lm.has_method("get_killer_candidates") else []
		if candidates.size() == 1:
			role_tags[candidates[0]] = "killer"
		elif candidates.size() > 1:
			for cid in candidates:
				role_tags[cid] = "candidate"
	if players.is_empty():
		_refresh_empty(true)
	else:
		_refresh_empty(false)
		# Ordenar: host primero, luego por peer_id para estabilidad
		players.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))
		# Host al inicio si existe
		var host_idx := -1
		for i in players.size():
			if bool(players[i].get("is_host", false)):
				host_idx = i
				break
		if host_idx > 0:
			var host_entry = players[host_idx]
			players.remove_at(host_idx)
			players.insert(0, host_entry)
		for p in players:
			var row := _create_player_row(p, role_tags)
			_player_container.add_child(row)
	# Si el target del menú ya no existe, cerrarlo
	if _action_visible and not _player_exists(_selected_target_id):
		_close_action_menu()
	var lm2 := get_node_or_null("/root/LobbyManager")
	if _status_label and lm2:
		var maxp: int = lm2.max_players if "max_players" in lm2 else lm2.MAX_PLAYERS
		_status_label.text = "Jugadores: %d/%d" % [lm2.players.size(), maxp]
	_rebuild_focus()
	# Si el índice quedó fuera del rango de focusables tras rebuild, clampear
	_highlight(_index, false)
	_position_soul(_index, false)
	# Si el menú estaba abierto, refrescar su estado
	if _action_visible:
		_update_action_menu_state()
		_highlight_action(_action_index, false)
		_position_soul_action(_action_index, false)

func _player_exists(peer_id: int) -> bool:
	var lm := get_node_or_null("/root/LobbyManager")
	if lm == null or not lm.players.has(peer_id):
		return false
	return true

func _create_player_row(p: Dictionary, role_tags: Dictionary = {}) -> Control:
	var peer_id: int = int(p.get("id", -1))
	var name_str: String = str(p.get("name", "?"))
	var is_host: bool = bool(p.get("is_host", false))
	var my_id: int = multiplayer.get_unique_id()
	var is_me: bool = peer_id == my_id
	var pts: int = int(p.get("killer_points", 0))
	var is_spec: bool = bool(p.get("is_spectator", false))
	var is_forced: bool = p.has("_prev_killer_points") and pts == 99
	var tag: String = str(role_tags.get(peer_id, ""))

	var tm := get_node_or_null("/root/ThemeManager")
	var pal: Dictionary = tm.get_palette() if tm and tm.has_method("get_palette") else {}
	var sel_c: Color = pal.get("selected", Color(0,1,0,1))
	var dim_c: Color = pal.get("dim", Color(0,0.5,0,1))

	# Panel contenedor para highlight
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_meta("peer_id", peer_id)
	# Stylebox transparente por defecto
	var sb_off := StyleBoxFlat.new()
	sb_off.bg_color = Color(0,0,0,0)
	sb_off.set_corner_radius_all(4)
	sb_off.border_width_left = 0
	row.add_theme_stylebox_override("panel", sb_off)
	row.set_meta("sb_off", sb_off)
	var sb_on := StyleBoxFlat.new()
	sb_on.bg_color = Color(0,1,0,0.08)
	sb_on.border_color = sel_c
	sb_on.border_width_left = 2
	sb_on.border_width_top = 1
	sb_on.border_width_right = 1
	sb_on.border_width_bottom = 1
	sb_on.set_corner_radius_all(4)
	row.add_theme_stylebox_override("panel", sb_off)
	row.set_meta("sb_on", sb_on)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	row.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	margin.add_child(hbox)

	var name_lbl := Label.new()
	var display_name := name_str
	if is_host:
		display_name += " (HOST)"
	if is_me:
		display_name += " (TÚ)"
	name_lbl.text = display_name
	name_lbl.add_theme_font_override("font", preload("res://Fonts/deltarune font.ttf"))
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.custom_minimum_size = Vector2(180, 0)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	# Forzado y host destacan con selected; el resto dim. La etiqueta tag ya indica killer/candidato.
	var name_base: Color = sel_c if (is_host or tag != "") else dim_c
	name_lbl.add_theme_color_override("font_color", name_base)
	name_lbl.set_meta("base_color", name_base)
	hbox.add_child(name_lbl)

	var pts_lbl := Label.new()
	pts_lbl.text = "PTS:%d" % pts
	pts_lbl.add_theme_font_override("font", preload("res://Fonts/deltarune font.ttf"))
	pts_lbl.add_theme_font_size_override("font_size", 13)
	pts_lbl.custom_minimum_size = Vector2(70, 0)
	pts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pts_lbl.add_theme_color_override("font_color", dim_c)
	# Guardar color base para highlight
	pts_lbl.set_meta("base_color", dim_c)
	hbox.add_child(pts_lbl)

	var spec_lbl := Label.new()
	spec_lbl.text = "ESP: " + ("SI" if is_spec else "NO")
	spec_lbl.add_theme_font_override("font", preload("res://Fonts/deltarune font.ttf"))
	spec_lbl.add_theme_font_size_override("font_size", 13)
	spec_lbl.custom_minimum_size = Vector2(70, 0)
	spec_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spec_lbl.add_theme_color_override("font_color", pal.get("hint", dim_c) if is_spec else dim_c)
	spec_lbl.set_meta("base_color", pal.get("hint", dim_c) if is_spec else dim_c)
	hbox.add_child(spec_lbl)

	# Etiqueta unica KILLER / CANDIDATO — solo colores del tema (selected para destacar, dim para vacio)
	var tag_lbl := Label.new()
	tag_lbl.add_theme_font_override("font", preload("res://Fonts/deltarune font.ttf"))
	tag_lbl.add_theme_font_size_override("font_size", 12)
	tag_lbl.custom_minimum_size = Vector2(110, 0)
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if tag == "killer_forced":
		tag_lbl.text = "★ KILLER"
		tag_lbl.add_theme_color_override("font_color", sel_c)
		tag_lbl.set_meta("base_color", sel_c)
	elif tag == "killer":
		tag_lbl.text = "★ KILLER"
		tag_lbl.add_theme_color_override("font_color", sel_c)
		tag_lbl.set_meta("base_color", sel_c)
	elif tag == "candidate":
		tag_lbl.text = "★ CANDIDATO"
		tag_lbl.add_theme_color_override("font_color", sel_c)
		tag_lbl.set_meta("base_color", sel_c)
	else:
		tag_lbl.text = ""
		tag_lbl.add_theme_color_override("font_color", dim_c)
		tag_lbl.set_meta("base_color", dim_c)
	hbox.add_child(tag_lbl)

	return row

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
	# Confirm overlay tiene prioridad máxima
	if _confirm_visible:
		if event.is_action_pressed("menu_up"):
			_move_confirm(-1)
			vp.set_input_as_handled()
		elif event.is_action_pressed("menu_down"):
			_move_confirm(1)
			vp.set_input_as_handled()
		elif event.is_action_pressed("menu_left"):
			_move_confirm(-1)
			vp.set_input_as_handled()
		elif event.is_action_pressed("menu_right"):
			_move_confirm(1)
			vp.set_input_as_handled()
		elif event.is_action_pressed("menu_accept") or event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_Z):
			_confirm_confirm()
			vp.set_input_as_handled()
		elif event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
			_close_confirm()
			vp.set_input_as_handled()
		return
	if _action_visible:
		if event.is_action_pressed("menu_up"):
			_move_action(-1)
			vp.set_input_as_handled()
		elif event.is_action_pressed("menu_down"):
			_move_action(1)
			vp.set_input_as_handled()
		elif event.is_action_pressed("menu_accept") or event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_Z):
			_confirm_action()
			vp.set_input_as_handled()
		elif event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
			_close_action_menu()
			vp.set_input_as_handled()
		return
	# Lobby normal
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
		if _action_visible:
			_close_action_menu()
			vp.set_input_as_handled()
		else:
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

func _move_action(dir: int) -> void:
	if _action_focusables.is_empty():
		return
	# Saltar botones deshabilitados
	var cur := _action_index
	var tries := 0
	while tries < _action_focusables.size():
		cur = (cur + dir + _action_focusables.size()) % _action_focusables.size()
		var c := _action_focusables[cur]
		if not c.disabled:
			break
		tries += 1
		if tries >= _action_focusables.size():
			return
	if cur == _action_index and _action_focusables[cur].disabled:
		return
	_action_index = cur
	_highlight_action(_action_index, false)
	_position_soul_action(_action_index, false)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)

func _move_confirm(dir: int) -> void:
	var ni := (_confirm_index + dir + 2) % 2
	if ni == _confirm_index:
		return
	_confirm_index = ni
	_highlight_confirm(_confirm_index, false)
	_position_soul_confirm(_confirm_index, false)
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
		var is_sel: bool = i == idx
		if c is Button:
			c.modulate = sel if is_sel else dim
			if c.disabled:
				c.modulate = Color(dim.r, dim.g, dim.b, 0.5)
		elif c is PanelContainer:
			var sb_on: StyleBoxFlat = c.get_meta("sb_on") if c.has_meta("sb_on") else null
			var sb_off: StyleBoxFlat = c.get_meta("sb_off") if c.has_meta("sb_off") else null
			if is_sel and sb_on:
				c.add_theme_stylebox_override("panel", sb_on)
				c.modulate = Color(1,1,1,1)
			elif sb_off:
				c.add_theme_stylebox_override("panel", sb_off)
				c.modulate = Color(1,1,1,1)
			# Opcion A: al seleccionar, el texto pasa a selected (verde del tema) y pierde el color semantico — nitido
			var hbox := c.get_node_or_null("MarginContainer/HBoxContainer")
			if hbox:
				for lbl in hbox.get_children():
					if lbl is Label:
						if is_sel:
							lbl.add_theme_color_override("font_color", sel)
							lbl.modulate = Color(1,1,1,1)
						else:
							var base: Color = lbl.get_meta("base_color") if lbl.has_meta("base_color") else dim
							lbl.add_theme_color_override("font_color", base)
							lbl.modulate = Color(1,1,1,1)
	if _hint and not _action_visible and not _confirm_visible:
		var cur := _focusables[idx]
		var lm := get_node_or_null("/root/LobbyManager")
		var is_host: bool = lm.is_host if lm else false
		if cur.has_meta("peer_id"):
			var pid: int = int(cur.get_meta("peer_id"))
			var info: Dictionary = lm.players.get(pid, {}) if lm else {}
			var nm: String = str(info.get("name", "?"))
			_hint.text = "Jugador: %s — [Z] Acciones  [↑↓] Mover" % nm
			if is_host and pid == LobbyManager.forced_killer_peer:
				_hint.text += " (KILLER FORZADO 99)"
		elif cur == _start_btn:
			if lm:
				var cnt: int = lm.players.size() if "players" in lm else 0
				var maxp: int = lm.max_players if "max_players" in lm else 4
				if cnt < 2:
					_hint.text = "Inicia selección de personaje — %d/%d falta 1 jugador" % [cnt, maxp]
				else:
					var cands: Array = lm.get_killer_candidates() if lm.has_method("get_killer_candidates") else []
					if cands.is_empty():
						_hint.text = "No hay jugador para ser killer — quita espectadores"
					elif lm.forced_killer_peer != -1 and lm.players.has(lm.forced_killer_peer) and not lm.is_spectator(lm.forced_killer_peer):
						var fname: String = str(lm.players[lm.forced_killer_peer].get("name", "?"))
						_hint.text = "Killer forzado: %s (99) — [Z] Iniciar" % fname
					elif cands.size() > 1:
						var top_pts: int = int(lm.players[cands[0]].get("killer_points", 0)) if lm.players.has(cands[0]) else 0
						_hint.text = "%d empatan (%d pts) — Killer aleatorio — [Z]" % [cands.size(), top_pts]
					else:
						var kname: String = str(lm.players[cands[0]].get("name", "?")) if lm.players.has(cands[0]) else "?"
						var kpts: int = int(lm.players[cands[0]].get("killer_points", 0)) if lm.players.has(cands[0]) else 0
						_hint.text = "Killer: %s (%d pts) — [Z] Iniciar" % [kname, kpts]
			else:
				_hint.text = "Inicia selección de personaje — requiere 2 jugadores"
		elif cur == _lobby3d_btn:
			_hint.text = "Entrar al LOBBY 3D — solo mapa y corazón [C] — [Z] Entrar"
		elif cur == _leave_btn:
			_hint.text = "Salir y volver al buscador — [Z] Confirmar"

func _highlight_action(idx: int, instant: bool) -> void:
	if _action_focusables.is_empty():
		return
	idx = clampi(idx, 0, _action_focusables.size() - 1)
	var tm := get_node_or_null("/root/ThemeManager")
	var pal: Dictionary = tm.get_palette() if tm and tm.has_method("get_palette") else {}
	var sel: Color = pal.get("selected", Color(0,1,0,1))
	var dim: Color = pal.get("dim", Color(0,0.50196081,0,1))
	for i in _action_focusables.size():
		var c := _action_focusables[i]
		if not is_instance_valid(c):
			continue
		c.modulate = sel if i == idx else dim
		if c.disabled:
			c.modulate = Color(dim.r, dim.g, dim.b, 0.45)
	if _hint:
		var cur := _action_focusables[idx]
		if cur == _btn_spectator:
			_hint.text = "Poner a %s como ESPECTADOR" % _selected_target_name
		elif cur == _btn_survivor:
			_hint.text = "Restaurar a %s como SURVIVOR" % _selected_target_name
		elif cur == _btn_killer:
			_hint.text = "Forzar a %s como KILLER (99 pts)" % _selected_target_name
		elif cur == _btn_kick:
			_hint.text = "Expulsar a %s de la sala" % _selected_target_name
		elif cur == _btn_cancel:
			_hint.text = "Cerrar menú — [X] Volver"

func _highlight_confirm(idx: int, instant: bool) -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	var pal: Dictionary = tm.get_palette() if tm and tm.has_method("get_palette") else {}
	var sel: Color = pal.get("selected", Color(0,1,0,1))
	var dim: Color = pal.get("dim", Color(0,0.50196081,0,1))
	var btns: Array[Control] = [_confirm_yes, _confirm_no]
	for i in btns.size():
		var c := btns[i]
		if not is_instance_valid(c):
			continue
		c.modulate = sel if i == idx else dim
		if c.disabled:
			c.modulate = Color(dim.r, dim.g, dim.b, 0.5)
	if _hint:
		if idx == 0:
			_hint.text = "Confirmar expulsión de %s — [Z] Sí" % _selected_target_name
		else:
			_hint.text = "Cancelar expulsión — [X] No"

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
	_soul.visible = true
	if instant:
		_soul.position = dest
	else:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_soul, "position", dest, 0.08)

func _position_soul_action(idx: int, instant: bool) -> void:
	if _soul == null or _action_focusables.is_empty():
		return
	if idx < 0 or idx >= _action_focusables.size():
		return
	var t := _action_focusables[idx]
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
	_soul.visible = true
	if instant:
		_soul.position = dest
	else:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_soul, "position", dest, 0.08)

func _position_soul_confirm(idx: int, instant: bool) -> void:
	if _soul == null:
		return
	var t: Control = _confirm_yes if idx == 0 else _confirm_no
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
	_soul.visible = true
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
	if cur.has_meta("peer_id"):
		var pid: int = int(cur.get_meta("peer_id"))
		var lm := get_node_or_null("/root/LobbyManager")
		var pname: String = str(lm.players[pid].get("name", "?")) if lm and lm.players.has(pid) else "?"
		_open_action_menu(pid, pname)
	elif cur == _start_btn:
		_on_start_pressed()
	elif cur == _lobby3d_btn:
		_on_lobby3d_pressed()
	elif cur == _leave_btn:
		_on_leave_pressed()

func _open_action_menu(peer_id: int, pname: String) -> void:
	var lm := get_node_or_null("/root/LobbyManager")
	if lm == null or not lm.is_host:
		return
	_selected_target_id = peer_id
	_selected_target_name = pname
	_action_visible = true
	if _action_target:
		_action_target.text = "JUGADOR: %s" % pname
	_update_action_menu_state()
	_rebuild_action_focus()
	# Saltar a primer botón habilitado
	for i in _action_focusables.size():
		if not _action_focusables[i].disabled:
			_action_index = i
			break
	if _action_menu:
		_action_menu.visible = true
	_highlight_action(_action_index, true)
	_position_soul_action(_action_index, true)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.SELECT)

func _close_action_menu() -> void:
	_action_visible = false
	if _action_menu:
		_action_menu.visible = false
	_highlight(_index, false)
	_position_soul(_index, false)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)

func _update_action_menu_state() -> void:
	var lm := get_node_or_null("/root/LobbyManager")
	if lm == null or not lm.players.has(_selected_target_id):
		return
	var info: Dictionary = lm.players[_selected_target_id]
	var is_spec: bool = bool(info.get("is_spectator", false))
	var role: String = str(info.get("assigned_role", "survivor"))
	var is_killer: bool = role == "killer"
	var my_id: int = multiplayer.get_unique_id()
	var is_self: bool = _selected_target_id == my_id
	if _btn_spectator:
		_btn_spectator.disabled = is_spec
	if _btn_survivor:
		_btn_survivor.disabled = not is_spec
	if _btn_killer:
		_btn_killer.disabled = is_killer and int(info.get("killer_points", 0)) == 99
	if _btn_kick:
		_btn_kick.disabled = is_self

func _confirm_action() -> void:
	if _action_focusables.is_empty():
		return
	var cur := _action_focusables[_action_index]
	if cur.disabled:
		var am := get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.ERROR)
		return
	if cur == _btn_spectator:
		_execute_spectator()
	elif cur == _btn_survivor:
		_execute_survivor()
	elif cur == _btn_killer:
		_execute_killer()
	elif cur == _btn_kick:
		_open_confirm_kick()
	elif cur == _btn_cancel:
		_close_action_menu()

func _execute_spectator() -> void:
	var lm := get_node_or_null("/root/LobbyManager")
	if lm and lm.has_method("admin_set_spectator"):
		var ok: bool = lm.admin_set_spectator(_selected_target_id)
		var am := get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.SELECT if ok else SfxId.ERROR)
	_close_action_menu()

func _execute_survivor() -> void:
	var lm := get_node_or_null("/root/LobbyManager")
	if lm and lm.has_method("admin_set_survivor"):
		var ok: bool = lm.admin_set_survivor(_selected_target_id)
		var am := get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.SELECT if ok else SfxId.ERROR)
	_close_action_menu()

func _execute_killer() -> void:
	var lm := get_node_or_null("/root/LobbyManager")
	if lm and lm.has_method("admin_force_killer"):
		var ok: bool = lm.admin_force_killer(_selected_target_id)
		var am := get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.SELECT if ok else SfxId.ERROR)
	_close_action_menu()

func _open_confirm_kick() -> void:
	_confirm_visible = true
	_confirm_index = 1 # por defecto NO para evitar accidentes
	if _confirm_label:
		_confirm_label.text = "¿Expulsar a %s?" % _selected_target_name
	if _confirm_overlay:
		_confirm_overlay.visible = true
	_highlight_confirm(_confirm_index, true)
	_position_soul_confirm(_confirm_index, true)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.SELECT)

func _close_confirm() -> void:
	_confirm_visible = false
	if _confirm_overlay:
		_confirm_overlay.visible = false
	# Volver al menú de acciones
	_highlight_action(_action_index, false)
	_position_soul_action(_action_index, false)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)

func _confirm_confirm() -> void:
	if _confirm_index == 0:
		_execute_kick()
	else:
		_close_confirm()

func _execute_kick() -> void:
	var lm := get_node_or_null("/root/LobbyManager")
	if lm and lm.has_method("admin_kick_player"):
		var ok: bool = lm.admin_kick_player(_selected_target_id)
		var am := get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.SELECT if ok else SfxId.ERROR)
	_confirm_visible = false
	if _confirm_overlay:
		_confirm_overlay.visible = false
	_close_action_menu()

func _on_player_joined(_peer_id: int, _info: Dictionary) -> void:
	_update_player_list()

func _on_player_left(_peer_id: int) -> void:
	_update_player_list()

func _on_kicked(reason: String) -> void:
	if not is_inside_tree():
		return
	if _status_label:
		_status_label.text = "Expulsado: %s" % reason
		_status_label.modulate = Color(1, 0.3, 0.3, 1)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.ERROR)

func _on_server_disconnected() -> void:
	if not is_inside_tree():
		return
	if _confirm_visible or _action_visible:
		return # No pisar el mensaje de expulsión
	if _status_label:
		_status_label.text = "Host desconectado. Volviendo al menú..."
		_status_label.modulate = Color(0, 1, 0, 1)
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return
	var mc := get_node_or_null("/root/MatchCoordinator")
	if mc and mc.has_method("reset_to_menu"):
		mc.reset_to_menu()
	else:
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/ServerBrowser.tscn")

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
	var cands: Array = lm.get_killer_candidates() if lm.has_method("get_killer_candidates") else []
	if cands.is_empty():
		if _status_label:
			_status_label.text = "No hay jugador para ser killer — quita espectadores."
			_status_label.modulate = Color(1, 0.6, 0.2, 1)
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.ERROR)
		return
	lm.host_start_character_selection()

func _on_lobby3d_pressed() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.SELECT)
	# Entrada individual: cada peer entra solo a su instancia del mapa 3D
	get_tree().change_scene_to_file("res://Maps/LobbyWorld.tscn")


func _on_leave_pressed() -> void:
	if _action_visible:
		_close_action_menu()
		return
	if _confirm_visible:
		_close_confirm()
		return
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
		if lm.has_signal("kicked") and lm.kicked.is_connected(_on_kicked):
			lm.kicked.disconnect(_on_kicked)
	var nm := get_node_or_null("/root/NetworkManager")
	if nm and nm.server_disconnected.is_connected(_on_server_disconnected):
		nm.server_disconnected.disconnect(_on_server_disconnected)
