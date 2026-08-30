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
	_apply_theme()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.connect(_on_theme_changed)
	var sm := get_node_or_null("/root/SettingsManager")
	var nm := get_node_or_null("/root/NetworkManager")
	# Mostrar modo red actual desde SettingsManager (no  cfg)
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
	# Enter es consumido por LineEdit → conectar señales del nodo
	if _name_edit and not _name_edit.text_submitted.is_connected(_on_name_submitted):
		_name_edit.text_submitted.connect(_on_name_submitted)
	if _name_edit and not _name_edit.focus_exited.is_connected(_on_name_focus_exited):
		_name_edit.focus_exited.connect(_on_name_focus_exited)

func _on_name_submitted(_text: String) -> void:
	_name_edit.release_focus()
	grab_focus.call_deferred()
	var ams := get_node_or_null("/root/AudioManager")
	if ams and ams.has_method("play_sfx_ui"):
		ams.play_sfx_ui(SfxId.SELECT)

func _on_name_focus_exited() -> void:
	grab_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var editing := _field_nodes[_focus_idx] == _name_edit and _name_edit.has_focus()
	if editing and event is InputEventKey and event.pressed:
		if event.unicode != 0 and event.keycode != KEY_ENTER and event.keycode != KEY_KP_ENTER and event.keycode != KEY_ESCAPE:
			return
		# bloquea navegación del soul mientras se tipeabal
		if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down"):
			return
		if event.is_action_pressed("menu_left") or event.is_action_pressed("menu_right"):
			return
		if event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
			_name_edit.release_focus()
			grab_focus.call_deferred()
			vp.set_input_as_handled()
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
	# si está editando, salir de edición guardando valor
	if _field_nodes[_focus_idx] == _name_edit and _name_edit.has_focus():
		_name_edit.release_focus()
		grab_focus.call_deferred()
	var ni := clampi(_focus_idx + dir, 0, _field_nodes.size() - 1)
	if ni == _focus_idx:
		return
	_focus_idx = ni
	_highlight(_focus_idx)
	_position_soul(_focus_idx, false)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)
	# no auto-grab focus para LineEdit, solo al confirmar con Z
	if _name_edit.has_focus() and _field_nodes[_focus_idx] != _name_edit:
		_name_edit.release_focus()

func _highlight(idx: int) -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	var pal: Dictionary = tm.get_palette() if tm and tm.has_method("get_palette") else {}
	var sel: Color = pal.get("selected", Color(0,1,0,1))
	var dim: Color = pal.get("dim", Color(0,0.50196081,0,1))
	for i in _field_nodes.size():
		var c := _field_nodes[i]
		if c is LineEdit:
			c.modulate = sel if i == idx else dim
		elif c is Label:
			c.modulate = sel if i == idx else dim
		elif c is Button:
			c.modulate = sel if i == idx else dim
	if _hint:
		match idx:
			0:
				var cur_name: String = _name_edit.text.strip_edges()
				_hint.text = "Título visible en el buscador — %s" % (cur_name if cur_name != "" else "vacío")
			1:
				var cur_map: String = _map_label.text if _map_label else ""
				_hint.text = "Mapa — %s (%d/%d)" % [cur_map, _map_idx + 1, maxi(_available_maps.size(), 1)]
			2: _hint.text = "Modo juego — Escape supervivencia"
			3: _hint.text = "Máximo %d en sala" % _max_players
			4: _hint.text = "Crea y entra al lobby"
			5: _hint.text = "Volver al buscador"

func _position_soul(idx: int, instant: bool) -> void:
	if _soul == null or _field_nodes.is_empty():
		return
	if idx < 0 or idx >= _field_nodes.size():
		return
	var target: Control = _field_nodes[idx]
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(target) or not is_instance_valid(_soul):
		return
	if not target.is_visible_in_tree():
		return
	var soul_h := _soul.size.y if _soul.size.y > 0 else 20.0
	var dest := target.global_position + Vector2(-28, (target.size.y - soul_h)/2.0) - global_position
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
		# toggle edición LineEdit
		if not _name_edit.has_focus():
			_name_edit.grab_focus()
			_name_edit.select_all()
		else:
			_name_edit.release_focus()
			grab_focus.call_deferred()
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
	_hint.text = "Error al crear lobby (Online no disponible?)"
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.ERROR)

func _go_back() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.SELECT)
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/ServerBrowser.tscn")

func _on_theme_changed(_id: String) -> void:
	_apply_theme()
	_highlight(_focus_idx)

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
	var pal: Dictionary = tm.get_palette() if tm.has_method("get_palette") else {}
	var title := get_node_or_null("CenterContainer/DeltaruneBox/Margin/VBox/Title") as Label
	var sep := get_node_or_null("CenterContainer/DeltaruneBox/Margin/VBox/Separator") as ColorRect
	var footer := get_node_or_null("Footer") as Label
	if title:
		title.add_theme_color_override("font_color", pal.get("title", Color(0,1,0,1)))
		if tm.has_method("get_font"):
			var f: FontFile = tm.get_font()
			if f:
				title.add_theme_font_override("font", f)
	if sep:
		sep.color = pal.get("separator", pal.get("border", Color(0,0.5,0,1)))
	if _hint:
		_hint.add_theme_color_override("font_color", pal.get("hint", Color(0,1,0,1)))
	if footer:
		footer.add_theme_color_override("font_color", pal.get("dim", Color(0.5,0.5,0.5,1)))
	if _soul and tm.has_method("get_soul_texture"):
		var st: Texture2D = tm.get_soul_texture()
		if st:
			_soul.texture = st
	# tematizar filas y flechas verdes residuales
	var pal_dim: Color = pal.get("dim", Color(0,0.5,0,1))
	for path in ["CenterContainer/DeltaruneBox/Margin/VBox/NameRow/NameLabel", "CenterContainer/DeltaruneBox/Margin/VBox/ModeRow/ModeLabel", "CenterContainer/DeltaruneBox/Margin/VBox/MapRow/MapText", "CenterContainer/DeltaruneBox/Margin/VBox/GameModeRow/GameModeText", "CenterContainer/DeltaruneBox/Margin/VBox/PlayersRow/PlayersText"]:
		var lbl := get_node_or_null(path) as Label
		if lbl:
			lbl.add_theme_color_override("font_color", pal_dim)
	for path2 in ["CenterContainer/DeltaruneBox/Margin/VBox/MapRow/MapLeft", "CenterContainer/DeltaruneBox/Margin/VBox/MapRow/MapRight", "CenterContainer/DeltaruneBox/Margin/VBox/GameModeRow/GameModeLeft", "CenterContainer/DeltaruneBox/Margin/VBox/GameModeRow/GameModeRight", "CenterContainer/DeltaruneBox/Margin/VBox/PlayersRow/PlayersLeft", "CenterContainer/DeltaruneBox/Margin/VBox/PlayersRow/PlayersRight"]:
		var arr := get_node_or_null(path2) as Label
		if arr:
			arr.add_theme_color_override("font_color", pal_dim)
	if _name_edit:
		_name_edit.add_theme_color_override("font_color", pal.get("selected", Color(0,1,0,1)))
	if _mode_label:
		_mode_label.add_theme_color_override("font_color", pal_dim)
	if _map_label:
		_map_label.add_theme_color_override("font_color", pal_dim)
	if _game_mode_label:
		_game_mode_label.add_theme_color_override("font_color", pal_dim)
	if _players_label:
		_players_label.add_theme_color_override("font_color", pal_dim)

func _exit_tree() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.disconnect(_on_theme_changed)
	var nm := get_node_or_null("/root/NetworkManager")
	if nm:
		if nm.connection_succeeded.is_connected(_on_server_created):
			nm.connection_succeeded.disconnect(_on_server_created)
		if nm.connection_failed.is_connected(_on_create_failed):
			nm.connection_failed.disconnect(_on_create_failed)
