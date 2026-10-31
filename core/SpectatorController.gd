class_name SpectatorController
extends Node

const CHAT_PANEL_SCENE := preload("res://ui/GameUI/Scenes/ChatPanel.tscn")
const FONT := preload("res://Fonts/deltarune font.ttf")
const SPECTATOR_ZOOM := 0.7

var _active := false
var _ui_layer: CanvasLayer = null
var _spectator_camera: Camera2D = null
var _spectator_panel: PanelContainer = null
var _target_label: Label = null
var _chat_panel: Control = null
var _follow_target: Node = null
var _last_target_peer_id := -1
var _session: Node = null


func _ready() -> void:
	add_to_group(GroupNames.SPECTATOR)
	set_process(false)


func is_active() -> bool:
	return _active


func get_follow_target() -> Node:
	return _follow_target


func activate() -> void:
	if _active:
		return
	_active = true
	set_process(true)
	_session = get_tree().get_first_node_in_group("hub_session")
	print("[SpectatorController] Modo espectador activado para el peer local")

	_disable_local_player_camera()
	_build_ui()
	_spectator_camera.enabled = true
	_spectator_camera.make_current()
	_spectator_panel.visible = true

	_reveal_players()

	var hud := get_tree().get_first_node_in_group(GroupNames.GAME_HUD)
	if hud and hud.has_method("set_spectator_ui_active"):
		hud.set_spectator_ui_active(true)
	else:
		_ensure_chat_panel()

	_select_initial_target()
	# La cámara nace en (0,0). Si el objetivo está en MatchArea (offset 50.000)
	# y dejamos position_smoothing activo, tarda en "volar" hasta la partida y
	# durante ese tiempo parece que el mapa/las posiciones no sincronizaron.
	_snap_camera_to_target()

	# Mantiene el World en el mismo estado aunque la activación venga desde la
	# muerte de un jugador (Player llama directamente a este controlador).
	var world := get_parent()
	if world and world.has_method("set_local_view_mode"):
		world.set_local_view_mode("spectate")

	if _session and _session.has_method("enter_spectator_view"):
		_session.enter_spectator_view()


func deactivate() -> void:
	if not _active and _ui_layer == null:
		return
	_active = false
	set_process(false)
	if _follow_target and is_instance_valid(_follow_target):
		_last_target_peer_id = _follow_target.get_multiplayer_authority()
	_follow_target = null
	if _spectator_camera:
		_spectator_camera.enabled = false
	if _spectator_panel:
		_spectator_panel.visible = false
	if _chat_panel and is_instance_valid(_chat_panel):
		_chat_panel.queue_free()
	_chat_panel = null


func request_return_to_hub() -> void:
	if _session and _session.has_method("return_to_hub_from_spectate"):
		_last_target_peer_id = _current_target_peer_id()
		_session.return_to_hub_from_spectate()
		return
	deactivate()


func _build_ui() -> void:
	if _ui_layer:
		return

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "SpectatorCanvasLayer"
	_ui_layer.layer = 5
	add_child(_ui_layer)

	_spectator_camera = Camera2D.new()
	_spectator_camera.name = "SpectatorCamera"
	_spectator_camera.enabled = false
	_spectator_camera.zoom = Vector2(SPECTATOR_ZOOM, SPECTATOR_ZOOM)
	_spectator_camera.position_smoothing_enabled = true
	_spectator_camera.position_smoothing_speed = 10.0
	add_child(_spectator_camera)

	_spectator_panel = PanelContainer.new()
	_spectator_panel.name = "SpectatorPanel"
	_spectator_panel.custom_minimum_size = Vector2(560, 92)
	_spectator_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spectator_panel.offset_left = -280.0
	_spectator_panel.offset_top = -118.0
	_spectator_panel.offset_right = 280.0
	_spectator_panel.offset_bottom = -26.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.03, 0.86)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.8, 0.8, 0.9, 0.7)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_top = 8
	style.content_margin_right = 14
	style.content_margin_bottom = 8
	_spectator_panel.add_theme_stylebox_override("panel", style)
	_ui_layer.add_child(_spectator_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_spectator_panel.add_child(vbox)

	_target_label = Label.new()
	_target_label.text = "ESPECTANDO: —"
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_label.add_theme_font_override("font", FONT)
	_target_label.add_theme_font_size_override("font_size", 18)
	_target_label.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0, 1.0))
	vbox.add_child(_target_label)

	var hint := Label.new()
	hint.text = "Q/E O ←/→ CAMBIAR   —   ESPACIO VOLVER AL HUB"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_override("font", FONT)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.75, 1.0))
	vbox.add_child(hint)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	vbox.add_child(buttons)

	var prev := Button.new()
	prev.text = "◀"
	prev.custom_minimum_size = Vector2(48, 28)
	prev.add_theme_font_override("font", FONT)
	prev.pressed.connect(_cycle_target.bind(-1))
	buttons.add_child(prev)

	var next := Button.new()
	next.text = "▶"
	next.custom_minimum_size = Vector2(48, 28)
	next.add_theme_font_override("font", FONT)
	next.pressed.connect(_cycle_target.bind(1))
	buttons.add_child(next)

	var hub_btn := Button.new()
	hub_btn.text = "VOLVER AL HUB"
	hub_btn.custom_minimum_size = Vector2(170, 28)
	hub_btn.add_theme_font_override("font", FONT)
	hub_btn.add_theme_font_size_override("font_size", 14)
	hub_btn.pressed.connect(request_return_to_hub)
	buttons.add_child(hub_btn)


func _ensure_chat_panel() -> void:
	if _chat_panel or _ui_layer == null:
		return
	_chat_panel = CHAT_PANEL_SCENE.instantiate()
	_chat_panel.name = "SpectatorChat"
	_chat_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_chat_panel.offset_left = 24.0
	_chat_panel.offset_top = -105.0
	_chat_panel.offset_right = 484.0
	_chat_panel.offset_bottom = 105.0
	_ui_layer.add_child(_chat_panel)


func _select_initial_target() -> void:
	var alive := _alive_players()
	if alive.is_empty():
		_follow_target = null
		return
	if _last_target_peer_id > 0:
		for p in alive:
			if p.get_multiplayer_authority() == _last_target_peer_id:
				_follow_target = p
				return
	_follow_target = alive[0]
	_last_target_peer_id = _follow_target.get_multiplayer_authority()


func _alive_players() -> Array[Node]:
	var result: Array[Node] = []
	for p in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if not is_instance_valid(p):
			continue
		if "health_state" in p and p.health_state == "alive":
			result.append(p)
	result.sort_custom(func(a: Node, b: Node) -> bool:
		return a.get_multiplayer_authority() < b.get_multiplayer_authority()
	)
	return result


func _process(_delta: float) -> void:
	if not _active:
		return
	if MenuUtils.is_any_menu_open(get_tree(), self):
		return
	if _is_chat_input_active():
		return
	_handle_input()
	_update_camera()
	_update_panel()


func _handle_input() -> void:
	if Input.is_action_just_pressed("spec_toggle"):
		request_return_to_hub()
		return

	var direction := 0
	if Input.is_action_just_pressed("spec_next") or Input.is_action_just_pressed("menu_right"):
		direction = 1
	elif Input.is_action_just_pressed("spec_prev") or Input.is_action_just_pressed("menu_left"):
		direction = -1
	if direction != 0:
		_cycle_target(direction)


func _update_camera() -> void:
	if _spectator_camera == null:
		return
	if _follow_target and is_instance_valid(_follow_target) \
			and (not ("health_state" in _follow_target) or _follow_target.health_state == "alive"):
		_spectator_camera.global_position = _follow_target.global_position
	else:
		_cycle_target(1)


func _snap_camera_to_target() -> void:
	if _spectator_camera == null or _follow_target == null \
			or not is_instance_valid(_follow_target):
		return
	_spectator_camera.global_position = _follow_target.global_position
	_spectator_camera.reset_smoothing()


func _cycle_target(direction: int) -> void:
	var alive := _alive_players()
	if alive.is_empty():
		_follow_target = null
		return

	var current_idx := -1
	if _follow_target and is_instance_valid(_follow_target):
		current_idx = alive.find(_follow_target)

	var new_idx := current_idx + direction
	if current_idx == -1:
		new_idx = 0 if direction >= 0 else alive.size() - 1
	while new_idx < 0:
		new_idx += alive.size()
	new_idx %= alive.size()

	_follow_target = alive[new_idx]
	_last_target_peer_id = _follow_target.get_multiplayer_authority()
	if _active:
		_snap_camera_to_target()


func _update_panel() -> void:
	if _target_label == null:
		return
	if _follow_target == null or not is_instance_valid(_follow_target):
		_target_label.text = "ESPECTANDO: SIN JUGADORES VIVOS"
		return
	var pid := _follow_target.get_multiplayer_authority()
	var pdata: Dictionary = LobbyManager.players.get(pid, {})
	var display_name := str(pdata.get("name", "")).strip_edges()
	if display_name == "":
		display_name = "JUGADOR %d" % pid
	_target_label.text = "ESPECTANDO: " + display_name


func _current_target_peer_id() -> int:
	if _follow_target and is_instance_valid(_follow_target):
		return _follow_target.get_multiplayer_authority()
	return _last_target_peer_id


func _is_chat_input_active() -> bool:
	for panel in get_tree().get_nodes_in_group("chat_panel"):
		if panel.has_method("is_input_active") and panel.is_input_active():
			return true
	return false


func _disable_local_player_camera() -> void:
	var my_player := PlayerRegistry.get_player(multiplayer.get_unique_id())
	if my_player and my_player.has_node("Camera2D"):
		my_player.get_node("Camera2D").enabled = false


func _reveal_players() -> void:
	for other in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if not is_instance_valid(other):
			continue
		if "animated_sprite" in other and other.animated_sprite:
			other.animated_sprite.self_modulate.a = 1.0
			other.animated_sprite.visible = true
		if other.has_node("NameTag"):
			other.name_tag.visible = true
