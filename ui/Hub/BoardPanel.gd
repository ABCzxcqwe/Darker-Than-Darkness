# res://ui/Hub/BoardPanel.gd
# Tablero de sala del hub: roster/AFK en una pestaña y configuración del
# host en otra. La UI vive en BoardPanel.tscn (editable/tematizable) y este
# script sólo contiene la lógica, como el resto de menús.
extends Control

const TAG := "BoardPanel"

signal start_requested
signal cancel_requested
signal closed
signal map_selected(map_id: String)
signal afk_toggle_requested
signal host_action_requested(action: String, peer_id: int)

const FONT := preload("res://Fonts/deltarune font.ttf")

@onready var _panel: PanelContainer = $Center/Panel
@onready var _title: Label = $Center/Panel/Margin/VBox/Title
@onready var _players_tab_btn: Button = $Center/Panel/Margin/VBox/Tabs/PlayersTabBtn
@onready var _config_tab_btn: Button = $Center/Panel/Margin/VBox/Tabs/ConfigTabBtn
@onready var _tab_hint: Label = $Center/Panel/Margin/VBox/TabHint
@onready var _players_tab: Control = $Center/Panel/Margin/VBox/Content/PlayersTab
@onready var _config_tab: Control = $Center/Panel/Margin/VBox/Content/ConfigTab
@onready var _players_list: VBoxContainer = $Center/Panel/Margin/VBox/Content/PlayersTab/Scroll/PlayersList
@onready var _afk_btn: Button = $Center/Panel/Margin/VBox/Content/PlayersTab/AfkBtn
@onready var _spectator_btn: Button = $Center/Panel/Margin/VBox/Content/PlayersTab/Actions/SpectatorBtn
@onready var _survivor_btn: Button = $Center/Panel/Margin/VBox/Content/PlayersTab/Actions/SurvivorBtn
@onready var _killer_btn: Button = $Center/Panel/Margin/VBox/Content/PlayersTab/Actions/KillerBtn
@onready var _kick_btn: Button = $Center/Panel/Margin/VBox/Content/PlayersTab/Actions/KickBtn
@onready var _prev_map_btn: Button = $Center/Panel/Margin/VBox/Content/ConfigTab/MapRow/PrevMapBtn
@onready var _map_label: Label = $Center/Panel/Margin/VBox/Content/ConfigTab/MapRow/MapLabel
@onready var _next_map_btn: Button = $Center/Panel/Margin/VBox/Content/ConfigTab/MapRow/NextMapBtn
@onready var _max_title: Label = $Center/Panel/Margin/VBox/Content/ConfigTab/MaxRow/MaxTitle
@onready var _max_minus: Button = $Center/Panel/Margin/VBox/Content/ConfigTab/MaxRow/MaxMinus
@onready var _max_label: Label = $Center/Panel/Margin/VBox/Content/ConfigTab/MaxRow/MaxLabel
@onready var _max_plus: Button = $Center/Panel/Margin/VBox/Content/ConfigTab/MaxRow/MaxPlus
@onready var _info_label: Label = $Center/Panel/Margin/VBox/Content/ConfigTab/InfoLabel
@onready var _status_label: Label = $Center/Panel/Margin/VBox/StatusLabel
@onready var _start_btn: Button = $Center/Panel/Margin/VBox/Footer/StartBtn
@onready var _cancel_btn: Button = $Center/Panel/Margin/VBox/Footer/CancelBtn
@onready var _close_btn: Button = $Center/Panel/Margin/VBox/Footer/CloseBtn

var _action_buttons: Dictionary = {}
var _selected_pid := -1
var _can_manage := false
var _tab := 0
var _maps: Array = []
var _map_index := 0
var _countdown := 0.0
var _auto_map_requested := false


func _ready() -> void:
	add_to_group("hub_ui")
	add_to_group(GroupNames.GAME_MENU)
	_action_buttons = {
		"spectator": _spectator_btn,
		"survivor": _survivor_btn,
		"killer": _killer_btn,
		"kick": _kick_btn,
	}
	_wire_buttons()
	_connect_theme()
	_apply_theme()
	visible = false


func _wire_buttons() -> void:
	_bind(_players_tab_btn, _set_tab.bind(0))
	_bind(_config_tab_btn, _set_tab.bind(1))
	_bind(_prev_map_btn, _cycle_map.bind(-1))
	_bind(_next_map_btn, _cycle_map.bind(1))
	_bind(_max_minus, _change_max_players.bind(-1))
	_bind(_max_plus, _change_max_players.bind(1))
	_bind(_afk_btn, func() -> void: afk_toggle_requested.emit())
	_bind(_start_btn, func() -> void: start_requested.emit())
	_bind(_cancel_btn, func() -> void: cancel_requested.emit())
	_bind(_close_btn, close_panel)
	for action in _action_buttons:
		_bind(_action_buttons[action], _on_host_action.bind(action))


func _bind(btn: BaseButton, handler: Callable) -> void:
	if btn and not btn.pressed.is_connected(handler):
		btn.pressed.connect(handler)


func _on_host_action(action: String) -> void:
	if _selected_pid > 0:
		host_action_requested.emit(action, _selected_pid)


func is_open() -> bool:
	return visible


func open_panel(can_manage: bool) -> void:
	_can_manage = can_manage
	_auto_map_requested = false
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
	_refresh_config()


func refresh() -> void:
	if not visible:
		return
	_refresh()


func refresh_map_info() -> void:
	_refresh_map()


# ── Tema ─────────────────────────────────────────────────────────────

func _connect_theme() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm:
		if tm.has_signal("theme_changed") and not tm.theme_changed.is_connected(_on_theme_arg):
			tm.theme_changed.connect(_on_theme_arg)
		if tm.has_signal("palette_changed") and not tm.palette_changed.is_connected(_on_theme_arg):
			tm.palette_changed.connect(_on_theme_arg)


func _on_theme_arg(_arg: Variant = null) -> void:
	_apply_theme()
	if visible:
		_refresh()


func _apply_theme() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null or not tm.has_method("get_palette"):
		return
	var pal: Dictionary = tm.get_palette()
	var font: Font = tm.get_font() if tm.has_method("get_font") else null
	if _panel and tm.has_method("make_box_style"):
		_panel.add_theme_stylebox_override("panel", tm.make_box_style())

	var title_c: Color = pal.get("title", Color(0, 1, 0, 1))
	var hint_c: Color = pal.get("hint", title_c)
	var dim_c: Color = pal.get("dim", title_c)
	for lbl in [_title, _tab_hint, _info_label, _status_label, _map_label, _max_label, _max_title]:
		if lbl == null:
			continue
		if lbl == _title:
			lbl.add_theme_color_override("font_color", title_c)
		elif lbl == _status_label:
			lbl.add_theme_color_override("font_color", hint_c)
		elif lbl == _map_label:
			lbl.add_theme_color_override("font_color", hint_c)
		else:
			lbl.add_theme_color_override("font_color", dim_c)
		if font:
			lbl.add_theme_font_override("font", font)

	for btn in [
		_players_tab_btn, _config_tab_btn, _afk_btn, _spectator_btn,
		_survivor_btn, _killer_btn, _kick_btn, _prev_map_btn, _next_map_btn,
		_max_minus, _max_plus, _start_btn, _cancel_btn, _close_btn,
	]:
		_style_button(btn, true)
		if btn and font:
			btn.add_theme_font_override("font", font)
	if visible:
		_refresh_players()


## Estilo temático compartido por todos los botones del tablero.
func _style_button(btn: Button, highlighted: bool = true) -> void:
	if btn == null:
		return
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null or not tm.has_method("get_palette"):
		return
	var pal: Dictionary = tm.get_palette()
	var selected: Color = pal.get("selected", Color(0, 1, 0, 1))
	var dim: Color = pal.get("dim", selected)
	var bg: Color = pal.get("bg", Color(0, 0, 0, 1))
	var base: StyleBoxFlat = tm.make_box_style() if tm.has_method("make_box_style") else null
	if base:
		btn.add_theme_stylebox_override("normal", base)
		var hover: StyleBoxFlat = base.duplicate()
		hover.bg_color = Color(selected.r, selected.g, selected.b, 0.12)
		btn.add_theme_stylebox_override("hover", hover)
		var pressed: StyleBoxFlat = base.duplicate()
		pressed.bg_color = Color(selected.r, selected.g, selected.b, 0.24)
		btn.add_theme_stylebox_override("pressed", pressed)
		var disabled: StyleBoxFlat = base.duplicate()
		disabled.bg_color = Color(bg.r, bg.g, bg.b, 0.35)
		disabled.border_color = Color(dim.r, dim.g, dim.b, 0.6)
		btn.add_theme_stylebox_override("disabled", disabled)
	var text_c := selected if highlighted else dim
	btn.add_theme_color_override("font_color", text_c)
	btn.add_theme_color_override("font_hover_color", selected)
	btn.add_theme_color_override("font_pressed_color", selected)
	btn.add_theme_color_override("font_disabled_color", dim)


# ── Pestañas ─────────────────────────────────────────────────────────

func _set_tab(tab: int) -> void:
	if tab == 1 and not _can_manage:
		tab = 0
	_tab = tab
	_players_tab.visible = tab == 0
	_config_tab.visible = tab == 1
	var tm := get_node_or_null("/root/ThemeManager")
	var pal: Dictionary = tm.get_palette() if tm and tm.has_method("get_palette") else {}
	var sel: Color = pal.get("selected", Color(0, 1, 0, 1))
	var dim: Color = pal.get("dim", Color(0, 0.5, 0, 1))
	_players_tab_btn.add_theme_color_override("font_color", sel if tab == 0 else dim)
	_config_tab_btn.add_theme_color_override("font_color", sel if tab == 1 else dim)
	_config_tab_btn.visible = _can_manage
	_refresh()


# ── Refresco de datos ────────────────────────────────────────────────

func _refresh() -> void:
	if _panel == null or not is_inside_tree():
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
		row.custom_minimum_size = Vector2(760, 48)
		row.add_theme_font_override("font", FONT)
		row.add_theme_font_size_override("font_size", 17)
		row.focus_mode = Control.FOCUS_NONE
		_style_button(row, int(pid) == _selected_pid)
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
	var found := false
	for i in _maps.size():
		if str(_maps[i].id) == map_id:
			_map_index = i
			map_name = str(_maps[i].display_name)
			found = true
			break
	# Si el host entra sin mapa (p. ej. hub tras reinicio), elegimos el primero
	# para que INICIAR PARTIDA no quede bloqueado sin explicación.
	if not found and _can_manage and not _maps.is_empty() and not _auto_map_requested:
		_auto_map_requested = true
		_map_index = 0
		map_name = str(_maps[0].display_name)
		map_selected.emit(str(_maps[0].id))
	if _map_label:
		_map_label.text = "MAPA: " + map_name
	var can_change := _can_manage and LobbyManager.current_phase == LobbyManager.GamePhase.LOBBY
	if _prev_map_btn:
		_prev_map_btn.disabled = not can_change
	if _next_map_btn:
		_next_map_btn.disabled = not can_change


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
	var can_change := _can_manage and LobbyManager.current_phase == LobbyManager.GamePhase.LOBBY
	if _max_minus:
		_max_minus.disabled = not can_change
	if _max_plus:
		_max_plus.disabled = not can_change
	if _start_btn:
		var active := LobbyManager.get_active_participants().size()
		var enough := active >= 2 or DevMode.is_enabled()
		var map_ok := LobbyManager.selected_map != "" and MapRegistry.has_map(LobbyManager.selected_map)
		var can_start := _can_manage \
			and LobbyManager.current_phase == LobbyManager.GamePhase.LOBBY \
			and _countdown <= 0.0 and enough and map_ok
		_start_btn.disabled = not can_start
		if can_start:
			_start_btn.text = "INICIAR PARTIDA"
		elif not _can_manage:
			_start_btn.text = "ESPERANDO AL HOST"
		elif LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY:
			_start_btn.text = "PARTIDA EN CURSO"
		elif _countdown > 0.0:
			_start_btn.text = "INICIANDO..."
		elif not enough:
			_start_btn.text = "FALTAN JUGADORES (%d/2)" % active
		elif not map_ok:
			_start_btn.text = "ELEGÍ UN MAPA"
		else:
			_start_btn.text = "INICIAR PARTIDA"
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

	if _can_manage:
		var vp_nav := get_viewport()
		var focus: Control = vp_nav.gui_get_focus_owner() if vp_nav else null
		var go_left := event.is_action_pressed("menu_left") or event.is_action_pressed("ui_left")
		var go_right := event.is_action_pressed("menu_right") or event.is_action_pressed("ui_right")
		if go_right and focus == _players_tab_btn and _config_tab_btn.visible:
			_config_tab_btn.grab_focus()
			if vp_nav:
				vp_nav.set_input_as_handled()
			return
		if go_left and focus == _config_tab_btn:
			_players_tab_btn.grab_focus()
			if vp_nav:
				vp_nav.set_input_as_handled()
			return

	if event.is_action_pressed("menu_cancel") \
			or event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()
		close_panel()


func _exit_tree() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm:
		if tm.has_signal("theme_changed") and tm.theme_changed.is_connected(_on_theme_arg):
			tm.theme_changed.disconnect(_on_theme_arg)
		if tm.has_signal("palette_changed") and tm.palette_changed.is_connected(_on_theme_arg):
			tm.palette_changed.disconnect(_on_theme_arg)
