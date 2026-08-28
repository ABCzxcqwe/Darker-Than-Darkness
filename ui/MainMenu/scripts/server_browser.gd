extends Control
## Mock ServerBrowser — LAN IP real + ONLINE Steam real, timeout anti-atasco, soul rojo

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
@onready var _ip_edit: LineEdit = $CenterContainer/DeltaruneBox/Margin/VBox/IPRow/IPInput

func _ready() -> void:
	var am0 := get_node_or_null("/root/AudioManager")
	if am0 and am0.has_method("play_menu_drone") and am0.current_global_state != "menu_drone":
		am0.play_menu_drone()
	_mode = _load_mode()
	if _title:
		_title.text = "BUSCAR PARTIDA — " + _mode
	_configure_search_row()
	# Conectar señales reales
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
				print("[Mock_ServerBrowser] Steam no disponible, forzando LAN")
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
	_highlight(_index, true)
	_position_soul(_index, true)
	_refresh_empty_state()
	grab_focus()
	# Auto buscar si ONLINE y steam listo
	if _mode == MODE_ONLINE:
		_do_refresh()

func _configure_search_row() -> void:
	if _ip_edit == null:
		return
	var connect_btn := $CenterContainer/DeltaruneBox/Margin/VBox/IPRow/ConnectBtn as Button
	if _mode == MODE_ONLINE:
		_ip_edit.placeholder_text = "Buscar sala o host..."
		_ip_edit.text = ""
		if connect_btn:
			connect_btn.text = "BUSCAR"
	else:
		_ip_edit.placeholder_text = "Filtrar por IP o nombre"
		_ip_edit.text = "127.0.0.1"
		if connect_btn:
			connect_btn.text = "BUSCAR"

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
			if not is_instance_valid(c):
				continue
			if c is HBoxContainer:
				_focusables.append(c)
	var actions := $CenterContainer/DeltaruneBox/Margin/VBox/Actions
	var ip_row := $CenterContainer/DeltaruneBox/Margin/VBox/IPRow
	var back_row := $CenterContainer/DeltaruneBox/Margin/VBox/BackRow
	if actions and actions.has_node("RefreshBtn"):
		_focusables.append(actions.get_node("RefreshBtn"))
	if actions and actions.has_node("CreateBtn"):
		_focusables.append(actions.get_node("CreateBtn"))
	if ip_row and is_instance_valid(_ip_edit):
		_focusables.append(_ip_edit)
	if ip_row and ip_row.has_node("ConnectBtn"):
		_focusables.append(ip_row.get_node("ConnectBtn"))
	if back_row and back_row.has_node("BackBtn"):
		_focusables.append(back_row.get_node("BackBtn"))
	if _focusables.is_empty():
		return

func _unhandled_input(event: InputEvent) -> void:
	if _busy and not _joining:
		return
	# Si está en join timeout, ignorar todo excepto X para cancelar?
	if _joining and event.is_action_pressed("menu_cancel"):
		_cancel_join()
		var vp2 := get_viewport()
		if vp2:
			vp2.set_input_as_handled()
		return
	var vp := get_viewport()
	if vp == null:
		return
	var is_on_search_field := _focusables.size() > _index and is_instance_valid(_focusables[_index]) and _focusables[_index] == _ip_edit
	var editing_search := is_on_search_field and _ip_edit.has_focus()
	if is_on_search_field and not editing_search and event is InputEventKey and event.pressed and event.unicode != 0 and event.keycode != KEY_ENTER and event.keycode != KEY_KP_ENTER and event.keycode != KEY_ESCAPE:
		_ip_edit.grab_focus()
		var ch := char(event.unicode)
		_ip_edit.text += ch
		_ip_edit.caret_column = _ip_edit.text.length()
		vp.set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_C and not editing_search and not _joining:
		_do_refresh()
		vp.set_input_as_handled()
		return
	if event.is_action_pressed("menu_up"):
		if _joining:
			return
		_move(-1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		if _joining:
			return
		_move(1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_accept") or event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_Z):
		if editing_search:
			if event is InputEventKey and event.keycode == KEY_Z and event.unicode != 0:
				return
		if _joining:
			return
		_confirm()
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		if editing_search:
			_ip_edit.release_focus()
			vp.set_input_as_handled()
			return
		if _joining:
			_cancel_join()
			vp.set_input_as_handled()
			return
		_go_back()
		vp.set_input_as_handled()

func _move(dir: int) -> void:
	if _focusables.is_empty() or _joining:
		return
	var ni := clampi(_index + dir, 0, _focusables.size() - 1)
	if ni == _index:
		return
	if not is_instance_valid(_focusables[ni]):
		return
	_index = ni
	_highlight(_index, false)
	_position_soul(_index, false)
	if _focusables[_index] == _ip_edit:
		_ip_edit.grab_focus()
	else:
		if is_instance_valid(_ip_edit) and _ip_edit.has_focus():
			_ip_edit.release_focus()
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)

func _highlight(idx: int, instant: bool) -> void:
	if _focusables.is_empty():
		return
	idx = clampi(idx, 0, _focusables.size() - 1)
	for j in _focusables.size():
		var c := _focusables[j]
		if not is_instance_valid(c):
			continue
		if c is HBoxContainer:
			var is_sel := j == idx
			for lbl in c.get_children():
				if not is_instance_valid(lbl):
					continue
				if lbl is Label:
					lbl.modulate = Color(0, 1, 0, 1) if is_sel else Color(0, 0.50196081, 0, 1)
			var first: Label = c.get_child(0) as Label if c.get_child_count() > 0 else null
			if first and is_instance_valid(first):
				var base := first.text.trim_prefix("  ").trim_prefix("    ").strip_edges()
				first.text = ("    " + base) if is_sel else ("  " + base)
		elif c is Button:
			if not is_instance_valid(c):
				continue
			c.modulate = Color(0, 1, 0, 1) if j == idx else Color(0, 0.50196081, 0, 1)
			c.disabled = _joining
		elif c is LineEdit:
			if not is_instance_valid(c):
				continue
			if j == idx:
				c.modulate = Color(0, 1, 0, 1)
				if not _joining:
					c.grab_focus()
			else:
				c.modulate = Color(0, 0.50196081, 0, 1)
				if c.has_focus():
					c.release_focus()
	if _hint and not _joining:
		if idx < 0 or idx >= _focusables.size():
			return
		var cur := _focusables[idx]
		if cur.name == "RefreshBtn":
			_hint.text = "Actualizar lista [C]"
		elif cur.name == "CreateBtn":
			_hint.text = "Crear nueva sala"
		elif cur.name == "ConnectBtn":
			if _mode == MODE_ONLINE:
				_hint.text = "Buscar por nombre/host [Z]"
			else:
				_hint.text = "Buscar por IP [Z]"
		elif cur.name == "BackBtn":
			_hint.text = "Volver [X]"
		else:
			_hint.text = "Unirse a sala seleccionada [Z]"

func _position_soul(idx: int, instant: bool) -> void:
	if _soul == null or _focusables.is_empty():
		return
	if idx < 0 or idx >= _focusables.size():
		return
	var t0 := _focusables[idx]
	if not is_instance_valid(t0):
		return
	await get_tree().process_frame
	if not is_instance_valid(t0) or _focusables.is_empty() or idx >= _focusables.size():
		return
	if not is_instance_valid(_soul):
		return
	var target: Control = _focusables[idx]
	if not is_instance_valid(target):
		return
	var dest := target.global_position + Vector2(-28, (target.size.y - _soul.size.y) / 2.0) - global_position
	if instant:
		_soul.position = dest
	else:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_soul, "position", dest, 0.08)

func _confirm() -> void:
	if _focusables.is_empty() or _joining:
		return
	if _index < 0 or _index >= _focusables.size():
		return
	var cur := _focusables[_index]
	if not is_instance_valid(cur):
		return
	if cur is LineEdit:
		if not _ip_edit.has_focus():
			_ip_edit.grab_focus()
			var am0 := get_node_or_null("/root/AudioManager")
			if am0 and am0.has_method("play_sfx_ui"):
				am0.play_sfx_ui(SfxId.SELECT)
			return
		if _mode == MODE_ONLINE:
			var am0b := get_node_or_null("/root/AudioManager")
			if am0b and am0b.has_method("play_sfx_ui"):
				am0b.play_sfx_ui(SfxId.SELECT)
			_do_search()
			_ip_edit.release_focus()
		else:
			_ip_edit.release_focus()
		_do_search()
		return
	var am := get_node_or_null("/root/AudioManager")
	if cur.name == "RefreshBtn":
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.SELECT)
		_do_refresh()
		return
	if cur.name == "CreateBtn":
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.SELECT)
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/CreateRoom.tscn")
		return
	if cur.name == "ConnectBtn":
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.SELECT)
		if _mode == MODE_ONLINE:
			_do_search()
		else:
			_do_search()
		return
	if cur.name == "BackBtn":
		_go_back()
		return
	if cur is HBoxContainer:
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.SELECT)
		# ONLINE: unirse al lobby seleccionado
		if _mode == MODE_ONLINE:
			var lobby_idx := _focusables.find(cur)
			# HBox rows están antes de los botones, su Á­ndice es también Á­ndice de lobby si hay lobbies
			# Buscar Á­ndice real entre los HBox
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
				_hint.text = "→ (mock) Unirse a " + str(cur.get_child(0).get("text")).strip_edges()
		else:
			# LAN: buscar IP de la fila seleccionada
			var row_idx2 := -1
			var cnt2 := 0
			for i in _focusables.size():
				if _focusables[i] is HBoxContainer:
					if _focusables[i] == cur:
						row_idx2 = cnt2
						break
					cnt2 += 1
			if row_idx2 >= 0 and row_idx2 < _mock_rooms.size():
				var ip_target: String = str(_mock_rooms[row_idx2].get("ip", _mock_rooms[row_idx2].get("host","")))
				if ip_target.is_valid_ip_address():
					_try_join_lan_with_ip(ip_target)
				else:
					_hint.text = "IP no válida en fila"
			else:
				var nombre2: Label = cur.get_child(0) as Label
				_hint.text = "→ (mock) Unirse a " + (nombre2.text.strip_edges() if nombre2 else cur.name)

# â”€â”€ Red real â”€â”€

func _try_join_lan_with_ip(ip: String) -> void:
	if ip.is_empty():
		_hint.text = "Ingresá una IP."
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
	if ip.is_empty():
		_hint.text = "Ingresá una IP."
		var am := get_node_or_null("/root/AudioManager")
		if am: am.play_sfx_ui(SfxId.ERROR)
		return
	if not ip.is_valid_ip_address():
		_hint.text = "IP inválida: " + ip
		var am2 := get_node_or_null("/root/AudioManager")
		if am2: am2.play_sfx_ui(SfxId.ERROR)
		return
	var sm := get_node_or_null("/root/SettingsManager")
	var player_name: String = sm.player_name if sm and sm.player_name != "" else "Jugador"
	var nm := get_node_or_null("/root/NetworkManager")
	if nm == null:
		_hint.text = "NetworkManager no encontrado"
		return
	# Validar modo
	if nm.network_mode != nm.NetworkMode.LAN:
		nm.set_lan_mode()
	_begin_join("Conectando a " + ip + "...", nm, player_name, ip)

func _try_join_steam(lobby_id: int) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	var player_name: String = sm.player_name if sm and sm.player_name != "" else "Jugador"
	var nm := get_node_or_null("/root/NetworkManager")
	if nm == null:
		_hint.text = "NetworkManager no encontrado"
		return
	if not nm.is_steam_ready():
		_hint.text = "Steam no disponible"
		var am := get_node_or_null("/root/AudioManager")
		if am: am.play_sfx_ui(SfxId.ERROR)
		return
	_begin_join("Conectando a lobby...", nm, player_name, lobby_id)

func _begin_join(msg: String, nm, player_name: String, target) -> void:
	_hint.text = msg
	_joining = true
	_busy = true
	# Deshabilitar botones para evitar doble click
	for c in _focusables:
		if c is Button:
			c.disabled = true
	var am := get_node_or_null("/root/AudioManager")
	if am: am.play_sfx_ui(SfxId.SELECT)
	var ok: bool = nm.join_server(player_name, target)
	if not ok:
		_end_join("Error al iniciar conexión")
		return
	# Timeout anti-atasco
	await get_tree().create_timer(JOIN_TIMEOUT).timeout
	if _joining:
		_end_join("Tiempo agotado — verifica IP/puerto 4242 o Steam")

func _end_join(msg: String) -> void:
	_joining = false
	_busy = false
	_hint.text = msg
	for c in _focusables:
		if c is Button:
			c.disabled = false
	_highlight(_index, false)
	var am := get_node_or_null("/root/AudioManager")
	if am: am.play_sfx_ui(SfxId.ERROR)

func _cancel_join() -> void:
	if not _joining:
		return
	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		nm.disconnect_from_server()
	_end_join("Cancelado [X]")

func _on_connection_succeeded() -> void:
	if not _joining:
		# Puede ser host creando sala, no join
		if is_inside_tree():
			get_tree().change_scene_to_file("res://ui/MainMenu/scenes/Lobby.tscn")
		return
	_joining = false
	_busy = false
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/Lobby.tscn")

func _on_connection_failed() -> void:
	if _joining:
		_end_join("No se pudo conectar — IP/puerto o Steam")
	else:
		_hint.text = "Error de conexión"
		_highlight(_index, false)

func _on_server_disconnected() -> void:
	if _joining:
		_end_join("Servidor desconectado")
	else:
		_hint.text = "Servidor desconectado"
		for c in _focusables:
			if c is Button:
				c.disabled = false

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
		# Intentar leer modo si está en lobby data
		if usteam:
			var m = usteam.getLobbyData(lobby_id, "mode")
			if m != "":
				mode_text = m
		var room_text2: String = name_text
		var host_text2: String = name_text
		var maxp: int = 10
		if usteam:
			var mp_str: String = str(usteam.getLobbyData(lobby_id, "max_players"))
			if mp_str != "":
				maxp = int(mp_str)
		var d := {"nombre": room_text2, "host": host_text2, "mapa": map_text, "jugadores": "%d/%d" % [members, maxp], "modo": mode_text, "ping": "-", "ip": host_text2}
		_master_rooms.append(d)
	_mock_rooms = _master_rooms.duplicate()
	_populate_rooms()
	_rebuild_focusables()
	_index = clampi(_index, 0, max(0, _focusables.size() - 1))
	if not _focusables.is_empty():
		_highlight(_index, false)
		_position_soul(_index, false)
	_refresh_empty_state()
	_busy = false
	if _mock_rooms.is_empty():
		_hint.text = "No se encontraron salas"
	else:
		_hint.text = "%d salas encontradas" % _mock_rooms.size()

func _do_refresh() -> void:
	if _mode == MODE_ONLINE:
		var nm := get_node_or_null("/root/NetworkManager")
		if nm == null or not nm.is_steam_ready():
			_hint.text = "Steam no disponible — usa LAN o activa Steam"
			var am := get_node_or_null("/root/AudioManager")
			if am: am.play_sfx_ui(SfxId.ERROR)
			return
		_busy = true
		_hint.text = "Buscando salas Online..."
		# Vaciar antes de pedir
		_master_rooms.clear()
		_mock_rooms.clear()
		_populate_rooms()
		_rebuild_focusables()
		_refresh_empty_state()
		nm.request_lobby_list()
		# Timeout para búsqueda: si en 5s no llega lista, mostrar vacÁ­o
		await get_tree().create_timer(JOIN_TIMEOUT).timeout
		if _busy and _master_rooms.is_empty():
			_busy = false
			_hint.text = "No se encontraron salas Online"
		else:
			_busy = false
		return
	# LAN: no hay descubrimiento, solo IP directa
	_hint.text = "Ingresá IP y pulsa CONECTAR"
	_master_rooms.clear()
	_mock_rooms.clear()
	_populate_rooms()
	_rebuild_focusables()
	_refresh_empty_state()
	_busy = false

func _do_search() -> void:
	var term := _ip_edit.text.strip_edges().to_lower()
	if term == "":
		_mock_rooms = _master_rooms.duplicate()
		_hint.text = "Mostrando todas (%d)" % _mock_rooms.size()
	else:
		var filtered: Array[Dictionary] = []
		for r in _master_rooms:
			if str(r["nombre"]).to_lower().contains(term) or str(r["host"]).to_lower().contains(term) or str(r["mapa"]).to_lower().contains(term) or str(r["modo"]).to_lower().contains(term) or str(r.get("ip","")).to_lower().contains(term):
				filtered.append(r)
		# LAN: si term es IP válida y no hay resultados, ofrecer entrada directa como fila filtrable
		if filtered.is_empty() and _mode == MODE_LAN and term.is_valid_ip_address():
			var dummy := {"nombre": "Servidor " + term, "host": term, "mapa": "Desconocido", "jugadores": "1/10", "modo": "Escape", "ping": "-", "ip": term}
			filtered.append(dummy)
		_mock_rooms = filtered
		if _mock_rooms.is_empty():
			_hint.text = "Sin resultados para '%s'" % term
		else:
			_hint.text = "%d coinciden con '%s'" % [_mock_rooms.size(), term]
	_populate_rooms()
	_rebuild_focusables()
	_index = clampi(_index, 0, max(0, _focusables.size() - 1))
	if not _focusables.is_empty():
		_highlight(_index, false)
		_position_soul(_index, false)
	_refresh_empty_state()

func _populate_rooms() -> void:
	if _list_container == null:
		return
	for c in _list_container.get_children():
		if is_instance_valid(c):
			c.free()
	for r in _mock_rooms:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var cols := ["nombre", "host", "mapa", "jugadores", "modo", "ping"]
		var widths := [170, 130, 145, 70, 85, 80]
		for i in cols.size():
			var lbl := Label.new()
			var raw := str(r.get(cols[i], ""))
			if i == 0:
				raw = "  " + raw
			lbl.text = raw
			lbl.add_theme_font_override("font", preload("res://Fonts/deltarune font.ttf"))
			lbl.add_theme_font_size_override("font_size", 18)
			lbl.clip_text = true
			lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			lbl.ellipsis_char = "..."
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
			lbl.custom_minimum_size = Vector2(widths[i], 22)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
		_list_container.add_child(row)

func _refresh_empty_state() -> void:
	if _list_empty == null:
		return
	_list_empty.visible = _mock_rooms.is_empty()
	if _mock_rooms.is_empty():
		_list_empty.text = "NO SE ENCONTRARON PARTIDAS"
		_list_empty.modulate = Color(0, 1, 0, 1)
		_list_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _go_back() -> void:
	if _joining:
		_cancel_join()
		return
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.SELECT)
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/PlayMode.tscn")

func _exit_tree() -> void:
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
