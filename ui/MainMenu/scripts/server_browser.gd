extends Control
## ServerBrowser — LAN IP real + ONLINE real, timeout anti-atasco, soul rojo

const MODE_ONLINE := "ONLINE"
const MODE_LAN := "LAN"
const JOIN_TIMEOUT := 5.0

var _mode: String = MODE_ONLINE
var _focusables: Array[Control] = []
var _index := 0
var _busy := false
var _joining := false
const GAME_MODES := ["Escape", "Juggernaut"]
var _mock_rooms: Array[Dictionary] = []
var _master_rooms: Array[Dictionary] = []
var _steam_lobbies: Array = []

@onready var _soul: TextureRect = $SoulCursor
@onready var _title: Label = $CenterContainer/DeltaruneBox/Margin/VBox/Title
@onready var _list_empty: Label = $CenterContainer/DeltaruneBox/Margin/VBox/ListBox/MarginList/VBoxList/EmptyLabel
@onready var _list_container: VBoxContainer = $CenterContainer/DeltaruneBox/Margin/VBox/ListBox/MarginList/VBoxList/Rooms
@onready var _hint: Label = $CenterContainer/DeltaruneBox/Margin/VBox/HintLabel

# Nodos UI
@onready var _controls_container: VBoxContainer = $CenterContainer/DeltaruneBox/Margin/VBox/ControlsContainer
@onready var _ip_edit: LineEdit = $CenterContainer/DeltaruneBox/Margin/VBox/ControlsContainer/IPRow/IPInput

func _ready() -> void:
	var am0 := get_node_or_null("/root/AudioManager")
	if am0 and am0.has_method("play_menu_drone") and am0.current_global_state != "menu_drone":
		am0.play_menu_drone()
	
	_apply_theme()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.connect(_on_theme_changed)
	
	_mode = _load_mode()
	if _title:
		_title.text = "BUSCAR PARTIDA — " + _mode
	_configure_search_row()

	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		if not nm.connection_succeeded.is_connected(_on_connection_succeeded):
			nm.connection_succeeded.connect(_on_connection_succeeded)
		if not nm.connection_failed.is_connected(_on_connection_failed):
			nm.connection_failed.connect(_on_connection_failed)
		if not nm.server_disconnected.is_connected(_on_server_disconnected):
			nm.server_disconnected.connect(_on_server_disconnected)
		if not nm.steam_lobby_list_updated.is_connected(_on_steam_lobby_list):
			nm.steam_lobby_list_updated.connect(_on_steam_lobby_list)
		
		var sm := get_node_or_null("/root/SettingsManager")
		if _mode == MODE_ONLINE:
			var ok = nm.initialize_steam()
			if not ok or not nm.is_steam_ready():
				print("[ServerBrowser] Online no disponible, forzando LAN")
				_mode = MODE_LAN
				if _title:
					_title.text = "BUSCAR PARTIDA — " + _mode
				_configure_search_row()
				var cfg2 := ConfigFile.new()
				cfg2.load("user://mock_playmode.cfg")
				cfg2.set_value("mock", "mode", _mode)
				cfg2.save("user://mock_playmode.cfg")
				if sm:
					sm.network_mode = 0
					sm.save_settings()
				nm.set_lan_mode()
			else:
				if sm:
					sm.network_mode = 1
					sm.save_settings()
		else:
			if sm:
				sm.network_mode = 0
				sm.save_settings()
			nm.set_lan_mode()

	_rebuild_focusables()
	if _focusables.is_empty():
		_refresh_empty_state()
		return
	# primer foco = Actualizar si no hay salas, si no primera sala
	if _mock_rooms.is_empty():
		for i in _focusables.size():
			if _focusables[i] and _focusables[i].name == "RefreshBtn":
				_index = i
				break
	else:
		_index = 0
	_highlight(_index, true)
	_position_soul(_index, true)
	_refresh_empty_state()
	grab_focus()
	if _ip_edit and not _ip_edit.text_submitted.is_connected(_on_ip_submitted):
		_ip_edit.text_submitted.connect(_on_ip_submitted)
	if _ip_edit and not _ip_edit.focus_exited.is_connected(_on_ip_focus_exited):
		_ip_edit.focus_exited.connect(_on_ip_focus_exited)

	if _mode == MODE_ONLINE:
		_do_refresh()

func _on_ip_submitted(_text: String) -> void:
	# igual que Settings: Enter solo sale de edición, no dispara búsqueda (va por botón)
	_ip_edit.release_focus()
	grab_focus.call_deferred()
	var ams := get_node_or_null("/root/AudioManager")
	if ams and ams.has_method("play_sfx_ui"):
		ams.play_sfx_ui(SfxId.SELECT)

func _on_ip_focus_exited() -> void:
	grab_focus.call_deferred()

func _configure_search_row() -> void:
	if _ip_edit == null:
		return
	var connect_btn := $CenterContainer/DeltaruneBox/Margin/VBox/ControlsContainer/IPRow/ConnectBtn as Button
	if _mode == MODE_ONLINE:
		_ip_edit.placeholder_text = "Buscar sala o host..."
		_ip_edit.text = ""
		if connect_btn:
			connect_btn.text = "BUSCAR"
	else:
		_ip_edit.placeholder_text = "192.168.1.10"
		_ip_edit.text = "127.0.0.1"
		if connect_btn:
			connect_btn.text = "CONECTAR"

func _load_mode() -> String:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm:
		return MODE_ONLINE if sm.network_mode == 1 else MODE_LAN
	var nm := get_node_or_null("/root/NetworkManager")
	if nm and nm.network_mode == 1:
		return MODE_ONLINE
	return MODE_LAN

func _rebuild_focusables() -> void:
	_focusables.clear()
	
	if _list_container:
		for c in _list_container.get_children():
			if is_instance_valid(c) and c is HBoxContainer:
				_focusables.append(c)
				
	var ip_row := _controls_container.get_node_or_null("IPRow")
	var action_row := _controls_container.get_node_or_null("ActionRow")

	# Orden: Actualizar primero entre botones, Connect al final (pedido)
	if action_row:
		if action_row.has_node("RefreshBtn"):
			_focusables.append(action_row.get_node("RefreshBtn"))
		if action_row.has_node("CreateBtn"):
			_focusables.append(action_row.get_node("CreateBtn"))
		if action_row.has_node("BackBtn"):
			_focusables.append(action_row.get_node("BackBtn"))
	if ip_row and is_instance_valid(_ip_edit):
		_focusables.append(_ip_edit)
	if ip_row and ip_row.has_node("ConnectBtn"):
		_focusables.append(ip_row.get_node("ConnectBtn"))

func _unhandled_input(event: InputEvent) -> void:
	if _busy and not _joining:
		return

	if _joining and event.is_action_pressed("menu_cancel"):
		_cancel_join()
		var vp2 := get_viewport()
		if vp2: vp2.set_input_as_handled()
		return

	var vp := get_viewport()
	if vp == null:
		return

	var is_on_search_field := _focusables.size() > _index and is_instance_valid(_focusables[_index]) and _focusables[_index] == _ip_edit
	var editing_search := is_on_search_field and _ip_edit.has_focus()

	if editing_search and event is InputEventKey and event.pressed:
		if event.unicode != 0 and event.keycode != KEY_ENTER and event.keycode != KEY_KP_ENTER and event.keycode != KEY_ESCAPE:
			return
		if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down") or event.is_action_pressed("menu_left") or event.is_action_pressed("menu_right"):
			return

	# auto-edición deshabilitada: solo Z/Enter entra a editar (evita bloqueo al rozar)

	if event is InputEventKey and event.pressed and event.keycode == KEY_C and not editing_search and not _joining:
		_do_refresh()
		vp.set_input_as_handled()
		return

	if event.is_action_pressed("menu_up") or event.is_action_pressed("ui_up"):
		if not _joining:
			_move(-1)
			vp.set_input_as_handled()
	elif event.is_action_pressed("menu_down") or event.is_action_pressed("ui_down"):
		if not _joining:
			_move(1)
			vp.set_input_as_handled()
	elif event.is_action_pressed("menu_accept") or event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_Z):
		if editing_search:
			if event is InputEventKey and event.unicode != 0 and event.keycode == KEY_Z:
				return
			# Z/Enter mientras edita: solo sale de edición (igual que Settings), sin buscar
			if _ip_edit.has_focus():
				_ip_edit.release_focus()
				grab_focus.call_deferred()
				vp.set_input_as_handled()
				return
		if not _joining:
			_confirm()
			vp.set_input_as_handled()
	elif event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		if editing_search:
			_ip_edit.release_focus()
			grab_focus.call_deferred()
			vp.set_input_as_handled()
			return
		if _joining:
			_cancel_join()
		else:
			_go_back()
		vp.set_input_as_handled()

func _move(dir: int) -> void:
	if _focusables.is_empty() or _joining:
		return
	# si IP edit está en foco, salir antes de mover
	if is_instance_valid(_ip_edit) and _ip_edit.has_focus():
		_ip_edit.release_focus()
		grab_focus.call_deferred()
	# bucle circular
	var size := _focusables.size()
	var ni := (_index + dir) % size
	if ni < 0:
		ni += size
	# saltar inválidos
	var attempts := 0
	while attempts < size and not is_instance_valid(_focusables[ni]):
		ni = (ni + dir) % size
		if ni < 0:
			ni += size
		attempts += 1
	if ni == _index or not is_instance_valid(_focusables[ni]):
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
	var sel: Color = pal.get("selected", Color(0, 1, 0, 1))
	var dim: Color = pal.get("dim", Color(0, 0.5, 0, 1))

	for j in _focusables.size():
		var c := _focusables[j]
		if not is_instance_valid(c):
			continue

		if c is HBoxContainer:
			var is_sel := j == idx
			for lbl in c.get_children():
				if is_instance_valid(lbl) and lbl is Label:
					lbl.modulate = sel if is_sel else dim
		elif c is Button:
			c.modulate = sel if j == idx else dim
			c.disabled = _joining
		elif c is LineEdit:
			c.modulate = sel if j == idx else dim

	if _hint and not _joining:
		var cur := _focusables[idx]
		if cur.name == "RefreshBtn":
			_hint.text = "Recargar lista — %d salas" % _mock_rooms.size()
		elif cur.name == "CreateBtn":
			_hint.text = "Abre crear sala"
		elif cur.name == "ConnectBtn":
			if _mode == MODE_ONLINE:
				_hint.text = "Conectar a la sala filtrada"
			else:
				_hint.text = "Conectar a la IP ingresada"
		elif cur.name == "BackBtn":
			_hint.text = "Volver a modo de red"
		elif cur is LineEdit:
			if _mode == MODE_ONLINE:
				_hint.text = "Filtra por nombre o pega IP"
			else:
				_hint.text = "Pega la IP del host"
		else:
			# Row HBoxContainer → mostrar detalle de la sala enfocada
			var row_idx := -1
			var cnt := 0
			for i in _focusables.size():
				if _focusables[i] is HBoxContainer:
					if _focusables[i] == cur:
						row_idx = cnt
						break
					cnt += 1
			if row_idx >= 0 and row_idx < _mock_rooms.size():
				var r: Dictionary = _mock_rooms[row_idx]
				_hint.text = "%s — %s — %s %s" % [str(r.get("nombre","")), str(r.get("mapa","")), str(r.get("jugadores","")), str(r.get("ping",""))]
			else:
				_hint.text = "Sala disponible — detalles"

func _position_soul(idx: int, instant: bool) -> void:
	if _soul == null or _focusables.is_empty():
		return
	idx = clampi(idx, 0, _focusables.size() - 1)
	var target: Control = _focusables[idx]
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		return

	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(target) or not is_instance_valid(_soul):
		return
	if not target.is_visible_in_tree():
		return

	# si es botón, corazón dentro del botón como hijo
	if target is Button:
		if _soul.get_parent() != target:
			# guardar posición global antes de reparent
			var keep_global := _soul.global_position
			if _soul.get_parent():
				_soul.get_parent().remove_child(_soul)
			target.add_child(_soul)
			_soul.global_position = keep_global
		var soul_h2 := _soul.size.y if _soul.size.y > 0 else 20.0
		var inside_pos := Vector2(10, (target.size.y - soul_h2) / 2.0)
		if target is Button:
			# compensar padding del texto del botón
			inside_pos.x = 12
		if instant:
			_soul.position = inside_pos
		else:
			var tw2 := create_tween()
			tw2.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw2.tween_property(_soul, "position", inside_pos, 0.08)
		return
	else:
		# asegurar que soul esté en el root si estaba dentro de un botón
		if _soul.get_parent() != self:
			var keep2 := _soul.global_position
			_soul.get_parent().remove_child(_soul)
			add_child(_soul)
			_soul.global_position = keep2

	var soul_h := _soul.size.y if _soul.size.y > 0 else 20.0
	var dest := target.global_position + Vector2(-28, (target.size.y - soul_h) / 2.0) - global_position
	if instant:
		_soul.position = dest
	else:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_soul, "position", dest, 0.08)

func _confirm() -> void:
	if _focusables.is_empty() or _joining:
		return
	var cur := _focusables[_index]
	if not is_instance_valid(cur):
		return

	var am := get_node_or_null("/root/AudioManager")

	if cur is LineEdit:
		# toggle igual que Settings: Z entra/sale, sin disparar búsqueda
		if not _ip_edit.has_focus():
			_ip_edit.grab_focus()
			_ip_edit.select_all()
		else:
			_ip_edit.release_focus()
			grab_focus.call_deferred()
		return

	if cur.name == "RefreshBtn":
		if am and am.has_method("play_sfx_ui"): am.play_sfx_ui(SfxId.SELECT)
		_do_refresh()
		return

	if cur.name == "CreateBtn":
		if am and am.has_method("play_sfx_ui"): am.play_sfx_ui(SfxId.SELECT)
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/CreateRoom.tscn")
		return

	if cur.name == "ConnectBtn":
		if am and am.has_method("play_sfx_ui"): am.play_sfx_ui(SfxId.SELECT)
		if _mode == MODE_LAN:
			_try_join_lan()
		else:
			_do_search()
		return

	if cur.name == "BackBtn":
		_go_back()
		return

	if cur is HBoxContainer:
		if am and am.has_method("play_sfx_ui"): am.play_sfx_ui(SfxId.SELECT)
		if _mode == MODE_ONLINE:
			var row_index := -1
			var count_hbox := 0
			for i in _focusables.size():
				if _focusables[i] is HBoxContainer:
					if _focusables[i] == cur:
						row_index = count_hbox
						break
					count_hbox += 1
			if row_index >= 0 and row_index < _steam_lobbies.size():
				_try_join_steam(_steam_lobbies[row_index])
		else:
			var row_idx2 := -1
			var cnt2 := 0
			for i in _focusables.size():
				if _focusables[i] is HBoxContainer:
					if _focusables[i] == cur:
						row_idx2 = cnt2
						break
					cnt2 += 1
			if row_idx2 >= 0 and row_idx2 < _mock_rooms.size():
				var ip_target: String = str(_mock_rooms[row_idx2].get("ip", ""))
				_try_join_lan_with_ip(ip_target)

# --- Red / Conexión ---

func _try_join_lan_with_ip(ip: String) -> void:
	if ip.is_empty():
		_hint.text = "Ingresa una IP."
		return
	if not ip.is_valid_ip_address():
		_hint.text = "IP inválida: " + ip
		return
	var sm2 := get_node_or_null("/root/SettingsManager")
	var player_name2: String = sm2.player_name if sm2 and sm2.player_name != "" else "Jugador"
	var nm2 := get_node_or_null("/root/NetworkManager")
	if nm2 == null:
		_hint.text = "NetworkManager no encontrado"
		return
	if nm2.network_mode != nm2.NetworkMode.LAN:
		nm2.set_lan_mode()
	_begin_join("Conectando a " + ip + "...", nm2, player_name2, ip)

func _try_join_lan() -> void:
	var ip := _ip_edit.text.strip_edges()
	_try_join_lan_with_ip(ip)

func _try_join_steam(lobby_id: int) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	var player_name: String = sm.player_name if sm and sm.player_name != "" else "Jugador"
	var nm := get_node_or_null("/root/NetworkManager")
	if nm == null or not nm.is_steam_ready():
		_hint.text = "Online no disponible"
		return
	_begin_join("Conectando a sala online...", nm, player_name, lobby_id)

func _begin_join(msg: String, nm, player_name: String, target) -> void:
	_hint.text = msg
	_joining = true
	_busy = true
	for c in _focusables:
		if c is Button: c.disabled = true
	
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"): am.play_sfx_ui(SfxId.SELECT)
	
	var ok: bool = nm.join_server(player_name, target)
	if not ok:
		_end_join("Error al iniciar conexión")
		return

	await get_tree().create_timer(JOIN_TIMEOUT).timeout
	if _joining:
		_end_join("No se pudo conectar — servidor no responde")

func _end_join(msg: String) -> void:
	_joining = false
	_busy = false
	_hint.text = msg
	for c in _focusables:
		if c is Button: c.disabled = false
	_highlight(_index, false)

func _cancel_join() -> void:
	if not _joining: return
	var nm := get_node_or_null("/root/NetworkManager")
	if nm: nm.disconnect_from_server()
	_end_join("Cancelado [X]")

func _on_connection_succeeded() -> void:
	_joining = false
	_busy = false
	if is_inside_tree():
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/Lobby.tscn")

func _on_connection_failed() -> void:
	_end_join("No se encontró servidor activo en la IP/Lobby")

func _on_server_disconnected() -> void:
	_end_join("Servidor desconectado")

func _on_steam_lobby_list(lobbies: Array) -> void:
	_steam_lobbies = lobbies
	_master_rooms.clear()
	_mock_rooms.clear()
	var usteam = Engine.get_singleton("Steam")
	for lobby_id in lobbies:
		var name_text: String = usteam.getLobbyData(lobby_id, "name") if usteam else str(lobby_id)
		var map_text: String = usteam.getLobbyData(lobby_id, "map") if usteam else "?"
		var members: int = usteam.getNumLobbyMembers(lobby_id) if usteam else 1
		var mode_text: String = GAME_MODES[0]
		var maxp: int = 10
		if usteam:
			var m = usteam.getLobbyData(lobby_id, "mode")
			if m != "": mode_text = m
			var mp_str: String = str(usteam.getLobbyData(lobby_id, "max_players"))
			if mp_str != "": maxp = int(mp_str)
		var d := {"nombre": name_text, "host": name_text, "mapa": map_text, "jugadores": "%d/%d" % [members, maxp], "modo": mode_text, "ping": "-", "ip": name_text}
		_master_rooms.append(d)
	_mock_rooms = _master_rooms.duplicate()
	_populate_rooms()
	_rebuild_focusables()
	_refresh_empty_state()
	_busy = false
	_hint.text = "%d salas encontradas" % _mock_rooms.size() if not _mock_rooms.is_empty() else "No se encontraron salas"

func _do_refresh() -> void:
	if _mode == MODE_ONLINE:
		var nm := get_node_or_null("/root/NetworkManager")
		if nm == null or not nm.is_steam_ready():
			_hint.text = "Online no disponible"
			return
		_busy = true
		_hint.text = "Buscando salas online..."
		_master_rooms.clear()
		_mock_rooms.clear()
		_populate_rooms()
		_rebuild_focusables()
		_refresh_empty_state()
		nm.request_lobby_list()
		await get_tree().create_timer(JOIN_TIMEOUT).timeout
		if _busy and _master_rooms.is_empty():
			_busy = false
			_hint.text = "No se encontraron salas Online"
		return

	_hint.text = "Ingresa IP y presiona CONECTAR"
	_master_rooms.clear()
	_mock_rooms.clear()
	_populate_rooms()
	_rebuild_focusables()
	_refresh_empty_state()

func _do_search() -> void:
	var term := _ip_edit.text.strip_edges().to_lower()
	if term == "":
		_mock_rooms = _master_rooms.duplicate()
	else:
		var filtered: Array[Dictionary] = []
		for r in _master_rooms:
			if str(r["nombre"]).to_lower().contains(term) or str(r.get("ip","")).to_lower().contains(term):
				filtered.append(r)
		_mock_rooms = filtered
	_populate_rooms()
	_rebuild_focusables()
	_refresh_empty_state()

func _populate_rooms() -> void:
	if _list_container == null: return
	for c in _list_container.get_children():
		if is_instance_valid(c): c.free()
	for r in _mock_rooms:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var cols := ["nombre", "host", "mapa", "jugadores", "modo", "ping"]
		var widths := [170, 130, 145, 70, 85, 80]
		for i in cols.size():
			var lbl := Label.new()
			lbl.text = str(r.get(cols[i], ""))
			lbl.add_theme_font_override("font", preload("res://Fonts/deltarune font.ttf"))
			lbl.add_theme_font_size_override("font_size", 18)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.custom_minimum_size = Vector2(widths[i], 22)
			row.add_child(lbl)
		_list_container.add_child(row)

func _refresh_empty_state() -> void:
	if _list_empty == null: return
	_list_empty.visible = _mock_rooms.is_empty()

func _go_back() -> void:
	if _joining:
		_cancel_join()
		return
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"): am.play_sfx_ui(SfxId.SELECT)
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/PlayMode.tscn")

func _on_theme_changed(_id: String) -> void:
	_apply_theme()

func _apply_theme() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null:
		return

	# Busca automáticamente cualquier nodo de fondo posible en la escena
	var bg_node: Node = null
	for target_name in ["Background", "BG", "ColorRect", "BackgroundContainer"]:
		if has_node(target_name):
			bg_node = get_node(target_name)
			break

	if bg_node:
		tm.apply_to_background(bg_node)

	# 2. Aplicar textura del Alma (Cursor)
	var soul_tex: Texture2D = tm.get_soul_texture()
	if soul_tex and _soul:
		_soul.texture = soul_tex

	# 3. Fuente
	var theme_font: FontFile = tm.get_font()

	# 4. Paleta de colores
	var palette: Dictionary = tm.get_palette()
	var border: Color = palette.get("border", Color(0, 0.5, 0, 1))
	var title_col: Color = palette.get("title", Color(0, 1, 0, 1))
	var sel_col: Color = palette.get("selected", Color(0, 1, 0, 1))
	var dim_col: Color = palette.get("dim", border)
	var hint_col: Color = palette.get("hint", sel_col)
	var sep_col: Color = palette.get("separator", border)

	if _title:
		_title.add_theme_color_override("font_color", title_col)
		if theme_font:
			_title.add_theme_font_override("font", theme_font)

	# headers NOMBRE|HOST|MAPA|JUG.|MODO|PING
	var header := get_node_or_null("CenterContainer/DeltaruneBox/Margin/VBox/Header") as HBoxContainer
	if header:
		for ch in header.get_children():
			if ch is Label:
				ch.add_theme_color_override("font_color", dim_col)
				if theme_font:
					ch.add_theme_font_override("font", theme_font)
	# separadores
	var sep1 := get_node_or_null("CenterContainer/DeltaruneBox/Margin/VBox/Separator") as ColorRect
	if sep1:
		sep1.color = sep_col
	var sep2 := get_node_or_null("CenterContainer/DeltaruneBox/Margin/VBox/Separator2") as ColorRect
	if sep2:
		sep2.color = sep_col
	# listbox panel
	var list_box := get_node_or_null("CenterContainer/DeltaruneBox/Margin/VBox/ListBox") as PanelContainer
	if list_box and tm.has_method("make_box_style"):
		list_box.add_theme_stylebox_override("panel", tm.make_box_style())
	if _hint:
		_hint.add_theme_color_override("font_color", hint_col)
	if _list_empty:
		_list_empty.add_theme_color_override("font_color", hint_col)
	var footer := get_node_or_null("Footer") as Label
	if footer:
		footer.add_theme_color_override("font_color", dim_col)
	# IP row label y input
	var ip_label := get_node_or_null("CenterContainer/DeltaruneBox/Margin/VBox/ControlsContainer/IPRow/IPLabel") as Label
	if ip_label:
		ip_label.add_theme_color_override("font_color", hint_col)
	if _ip_edit:
		_ip_edit.add_theme_color_override("font_color", sel_col)
	var box := get_node_or_null("CenterContainer/DeltaruneBox") as PanelContainer
	if box and tm.has_method("make_box_style"):
		box.add_theme_stylebox_override("panel", tm.make_box_style())

	var btns = [
		_controls_container.get_node_or_null("IPRow/ConnectBtn"),
		_controls_container.get_node_or_null("ActionRow/RefreshBtn"),
		_controls_container.get_node_or_null("ActionRow/CreateBtn"),
		_controls_container.get_node_or_null("ActionRow/BackBtn")
	]

	for btn in btns:
		if btn:
			btn.add_theme_color_override("font_color", sel_col)
			if theme_font:
				btn.add_theme_font_override("font", theme_font)
			if tm.has_method("make_box_style"):
				btn.add_theme_stylebox_override("normal", tm.make_box_style())

func _exit_tree() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.disconnect(_on_theme_changed)
	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		if nm.connection_succeeded.is_connected(_on_connection_succeeded):
			nm.connection_succeeded.disconnect(_on_connection_succeeded)
		if nm.connection_failed.is_connected(_on_connection_failed):
			nm.connection_failed.disconnect(_on_connection_failed)
		if nm.server_disconnected.is_connected(_on_server_disconnected):
			nm.server_disconnected.disconnect(_on_server_disconnected)
		if nm.steam_lobby_list_updated.is_connected(_on_steam_lobby_list):
			nm.steam_lobby_list_updated.disconnect(_on_steam_lobby_list)
