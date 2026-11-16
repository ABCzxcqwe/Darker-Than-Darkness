# res://Network/session/hub_ui.gd
class_name HubUI
extends Node
## UI del hub: tablero, countdown, quick actions, overlay de selección y status.

const TAG := "HubUI"

var _session: Node
var _board_panel: Control
var _hub_board: Node
var _hub_shop: Node
var _shop: Control
var _status_label: Label
var _prompt_label: Label
var _ui_root: Node
var _game_menu: Control
var _quick_bar: VBoxContainer
var _quick_afk_btn: Button
var _quick_spectate_btn: Button
var _quick_partida_btn: Button
var _countdown_left := 0.0
var _countdown_timer: Timer
var _character_overlay: Control
var _character_layer: CanvasLayer


func setup(session: Node) -> void:
	_session = session
	_ui_root = session.get_node_or_null("UI") as Node
	_board_panel = session.get_node_or_null("UI/BoardPanel") as Control
	_hub_board = session.get_node_or_null("HubArea/HubBoard")
	_hub_shop = session.get_node_or_null("HubArea/HubShop")
	_shop = session.get_node_or_null("UI/Shop") as Control
	_status_label = session.get_node_or_null("UI/StatusLabel") as Label
	_prompt_label = session.get_node_or_null("UI/PromptLabel") as Label
	_game_menu = session.get_node_or_null("UI/DarkGameMenu") as Control

	if _hub_board and _hub_board.has_signal("interacted"):
		_hub_board.interacted.connect(_on_board_interacted)
	if _hub_shop and _hub_shop.has_signal("interacted"):
		_hub_shop.interacted.connect(_on_shop_interacted)
	if _shop and _shop.has_signal("closed"):
		_shop.closed.connect(_on_shop_closed)
	_connect_board_signals()

	MatchCoordinator.start_countdown_started.connect(_on_start_countdown_started)
	MatchCoordinator.start_countdown_cancelled.connect(_on_start_countdown_cancelled)
	LobbyManager.character_select_started.connect(_on_character_select_started)

	_countdown_timer = Timer.new()
	_countdown_timer.wait_time = 1.0
	_countdown_timer.one_shot = false
	_countdown_timer.timeout.connect(_on_countdown_tick)
	add_child(_countdown_timer)

	_build_quick_actions()
	_configure_hub_game_menu()


func _connect_board_signals() -> void:
	if _board_panel == null:
		return
	for binding in [
		["start_requested", _on_board_start_requested],
		["closed", _on_board_closed],
		["map_selected", _on_map_selected],
		["cancel_requested", _on_board_cancel_requested],
		["afk_toggle_requested", _on_board_afk_toggle],
		["host_action_requested", _on_board_host_action],
	]:
		if _board_panel.has_signal(binding[0]):
			_board_panel.connect(binding[0], binding[1])


# ── Estado / prompts ──

func on_lobby_changed() -> void:
	update_status()
	refresh_quick_actions()
	if is_board_open():
		_board_panel.refresh()


func show_prompt(text: String) -> void:
	if _prompt_label == null:
		return
	_prompt_label.text = text
	_prompt_label.visible = true


func hide_prompt() -> void:
	if _prompt_label:
		_prompt_label.visible = false


func is_board_open() -> bool:
	return _board_panel != null and _board_panel.is_open()


func is_shop_open() -> bool:
	return _shop != null and _shop.is_open()


func character_select_open() -> bool:
	return is_instance_valid(_character_overlay)


func hide_character_select() -> void:
	if _character_layer and is_instance_valid(_character_layer):
		_character_layer.visible = false


func configure_game_menu() -> void:
	if _game_menu == null or not _game_menu.has_method("set_hub_mode"):
		return
	var show_stats := false
	if multiplayer and multiplayer.multiplayer_peer != null:
		var my_id := multiplayer.get_unique_id()
		show_stats = _session.is_match_running() and LobbyManager.is_match_participant(my_id)
	_game_menu.set_hub_mode(true, show_stats)


func close_hub_overlays() -> void:
	if is_board_open():
		_board_panel.close_panel()
	if is_shop_open():
		_shop.close_shop()
	if _game_menu and _game_menu.has_method("force_close"):
		_game_menu.force_close()
	var chat := _session.get_node_or_null("UI/ChatPanel")
	if chat and chat.has_method("close_input"):
		chat.close_input()


# ── Tienda ──

func _on_shop_interacted(player: Node) -> void:
	if not _session.is_active() or _session.is_in_match() or not _session.is_at_hub():
		return
	if player != _session.get_local_avatar() or is_board_open() or is_shop_open():
		return
	_open_shop()


func _open_shop() -> void:
	if not _session.is_active() or _session.is_in_match() or not _session.is_at_hub():
		return
	hide_prompt()
	_session.set_local_avatar_controls(false)
	if _shop:
		_shop.open_shop()


func _on_shop_closed() -> void:
	if _session.is_at_hub() and not character_select_open():
		_session.set_local_avatar_controls(true)


# ── Tablero ──

func _on_board_interacted(player: Node) -> void:
	if not _session.is_active() or _session.is_in_match():
		return
	if player != _session.get_local_avatar() or is_board_open() or is_shop_open():
		return
	open_board_panel()


func open_board_panel() -> void:
	if not _session.is_active() or _session.is_in_match() or is_shop_open():
		return
	hide_prompt()
	_session.set_local_avatar_controls(false)
	var can_manage: bool = LobbyManager.is_host or LobbyManager.is_room_host()
	_board_panel.open_panel(can_manage)


func _on_board_closed() -> void:
	if _session.is_at_hub() and not character_select_open():
		_session.set_local_avatar_controls(true)


func _on_map_selected(map_id: String) -> void:
	if not (LobbyManager.is_host or LobbyManager.is_room_host()):
		_board_panel.set_status("SOLO EL HOST PUEDE CAMBIAR EL MAPA")
		return
	LobbyManager.request_select_map(map_id)


func _on_board_start_requested() -> void:
	if not _session.is_active():
		return
	if not (LobbyManager.is_host or LobbyManager.is_room_host()):
		_board_panel.set_status("SOLO EL HOST PUEDE INICIAR")
		return
	if LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY or _session.is_match_running():
		_board_panel.set_status("YA HAY UNA PARTIDA EN CURSO")
		return
	var active := LobbyManager.get_active_participants()
	if active.size() < 2 and not DevMode.is_enabled():
		_board_panel.set_status("SE NECESITAN 2 JUGADORES ACTIVOS")
		return
	LobbyManager.request_start()
	_board_panel.refresh()


func _on_board_cancel_requested() -> void:
	LobbyManager.request_cancel()


func _on_board_afk_toggle() -> void:
	LobbyManager.request_toggle_afk()


func _on_board_host_action(action: String, peer_id: int) -> void:
	if not (LobbyManager.is_host or LobbyManager.is_room_host()):
		return
	match action:
		"spectator":
			LobbyManager.request_set_spectator(peer_id)
		"survivor":
			LobbyManager.request_set_survivor(peer_id)
		"killer":
			LobbyManager.request_force_killer(peer_id)
		"kick":
			LobbyManager.request_kick(peer_id)
	_board_panel.refresh()


# ── Countdown ──

func _on_start_countdown_started(seconds: float) -> void:
	if not _session.is_active():
		return
	_countdown_left = seconds
	if _status_label:
		_status_label.text = "INICIANDO PARTIDA..."
	_board_panel.set_countdown(seconds)
	if _countdown_timer:
		_countdown_timer.start()


func _on_start_countdown_cancelled() -> void:
	if not _session.is_active():
		return
	_countdown_left = 0.0
	if _countdown_timer:
		_countdown_timer.stop()
	_board_panel.set_countdown(0.0)
	update_status()


func _on_countdown_tick() -> void:
	if _countdown_left <= 0.0:
		if _countdown_timer:
			_countdown_timer.stop()
		return
	_countdown_left = maxf(_countdown_left - 1.0, 0.0)
	_board_panel.set_countdown(_countdown_left)
	if _status_label:
		_status_label.text = "INICIANDO EN %d..." % int(_countdown_left)
	if _countdown_left <= 0.0 and _countdown_timer:
		_countdown_timer.stop()


# ── Selección de personaje ──

func _on_character_select_started() -> void:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return
	var my_id := multiplayer.get_unique_id()
	if not LobbyManager.is_match_participant(my_id):
		_session.avatars.queue_sync()
		update_status()
		refresh_quick_actions()
		return
	if character_select_open():
		return

	hide_prompt()
	if is_board_open():
		_board_panel.close_panel()
	_session.set_local_avatar_controls(false)

	var packed := load(NetScenes.CHARACTER_SELECT) as PackedScene
	if packed == null:
		NetLog.error(TAG, "No se pudo cargar CharacterSelect (%s)." % NetScenes.CHARACTER_SELECT)
		return

	_character_overlay = packed.instantiate()
	_character_overlay.name = "CharacterSelectOverlay"
	if _character_layer == null or not is_instance_valid(_character_layer):
		_character_layer = CanvasLayer.new()
		_character_layer.name = "CharacterSelectLayer"
		_character_layer.layer = 50
		add_child(_character_layer)
	_character_layer.visible = true
	_character_layer.add_child(_character_overlay)
	_character_overlay.tree_exited.connect(func() -> void:
		_character_overlay = null
		if _session.is_active() and _session.is_at_hub():
			_session.set_local_avatar_controls(true)
		update_status()
		refresh_quick_actions()
	)
	if _status_label:
		_status_label.text = "ELECCIÓN DE PERSONAJE"


# ── Quick actions ──

func _build_quick_actions() -> void:
	if _ui_root == null:
		return
	# `UI` puede ser CanvasLayer o Control; usamos un Control full-rect como
	# ancla para que las posiciones de la barra sean relativas al viewport.
	var anchor_root := Control.new()
	anchor_root.name = "HubQuickActionsRoot"
	anchor_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(anchor_root)
	anchor_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_quick_bar = VBoxContainer.new()
	_quick_bar.name = "HubQuickActions"
	_quick_bar.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_quick_bar.offset_left = 24.0
	_quick_bar.offset_right = 224.0
	_quick_bar.offset_top = -150.0
	_quick_bar.offset_bottom = 150.0
	_quick_bar.add_theme_constant_override("separation", 10)
	anchor_root.add_child(_quick_bar)

	_quick_partida_btn = _make_quick_button("PARTIDA")
	_quick_partida_btn.pressed.connect(_on_quick_partida)
	_quick_bar.add_child(_quick_partida_btn)

	_quick_spectate_btn = _make_quick_button("ESPECTAR")
	_quick_spectate_btn.pressed.connect(_on_quick_spectate)
	_quick_bar.add_child(_quick_spectate_btn)

	_quick_afk_btn = _make_quick_button("AFK")
	_quick_afk_btn.pressed.connect(_on_quick_afk)
	_quick_bar.add_child(_quick_afk_btn)

	refresh_quick_actions()


func _make_quick_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 42)
	var font := load("res://Fonts/deltarune font.ttf") as Font
	if font:
		button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7, 1.0))
	button.focus_mode = Control.FOCUS_ALL
	return button


func refresh_quick_actions() -> void:
	if _quick_bar == null:
		return
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return
	var my_id := multiplayer.get_unique_id()
	var in_lobby: bool = LobbyManager.current_phase == LobbyManager.GamePhase.LOBBY \
		and not _session.is_in_match() and _session.is_at_hub()
	_quick_partida_btn.disabled = not in_lobby
	_quick_spectate_btn.disabled = not _session.is_match_running() or _session.is_match_ended()
	_quick_afk_btn.disabled = not in_lobby or not LobbyManager.can_local_toggle_afk()
	if LobbyManager.players.has(my_id):
		_quick_afk_btn.text = "AFK: SÍ" if LobbyManager.is_afk(my_id) else "AFK: NO"
	else:
		_quick_afk_btn.text = "AFK: NO"


func _on_quick_partida() -> void:
	if not _session.is_active() or _session.is_in_match() or not _session.is_at_hub():
		return
	open_board_panel()


func _on_quick_spectate() -> void:
	if not _session.is_match_running() or _session.is_match_ended() or not _session.is_at_hub():
		return
	if not MatchCoordinator.request_spectate() and _status_label:
		_status_label.text = "SINCRONIZANDO PARTIDA..."


func _on_quick_afk() -> void:
	if LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY or _session.is_in_match():
		return
	LobbyManager.request_toggle_afk()


# ── Status ──

func update_status() -> void:
	if _status_label == null:
		return
	if _session.is_in_match():
		if _session.is_match_ended():
			_status_label.text = "PARTIDA FINALIZADA — ESPERANDO AL HOST"
		elif LobbyManager.current_phase == LobbyManager.GamePhase.CHARACTER_SELECT:
			_status_label.text = "SELECCIÓN DE PERSONAJE EN CURSO"
		elif _session.is_match_running() and _session.is_at_hub():
			_status_label.text = "PARTIDA EN CURSO — PODÉS ESPECTAR"
		elif _session.is_match_running():
			_status_label.text = "PARTIDA EN CURSO"
		else:
			_status_label.text = "PARTIDA (DEBUG) — F2 VOLVER AL HUB"
		return

	var count := LobbyManager.players.size()
	if count <= 1:
		_status_label.text = "HUB — ACERCATE AL TABLERO"
	else:
		_status_label.text = "HUB — %d JUGADORES — ACERCATE AL TABLERO" % count


func _configure_hub_game_menu() -> void:
	configure_game_menu()
