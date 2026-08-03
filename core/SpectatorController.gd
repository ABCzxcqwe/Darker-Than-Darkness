class_name SpectatorController
extends Node

const SPECTATOR_PANEL_SCENE := preload("res://ui/GameUI/Scenes/SpectatorPanel.tscn")
const GAME_MENU_SCENE := preload("res://ui/hud/GameMenu.tscn")
const SPECTATOR_ZOOM := 0.7

var _active := false
var _ui_layer: CanvasLayer = null
var _spectator_camera: Camera2D = null
var _spectator_panel: PanelContainer = null
var _follow_target: Node = null
var _spec_freecam_offset: Vector2 = Vector2.ZERO
var _spec_freecam_speed: float = 400.0
var _spec_is_freecam := false


func _ready() -> void:
	add_to_group(GroupNames.SPECTATOR)
	set_process(false)


func get_follow_target() -> Node:
	return _follow_target


func activate() -> void:
	if _active:
		return
	_active = true
	print("[SpectatorController] Modo espectador activado para el peer local")

	_disable_local_player_camera()

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "SpectatorCanvasLayer"
	_ui_layer.layer = 5
	add_child(_ui_layer)

	_spectator_camera = Camera2D.new()
	_spectator_camera.name = "SpectatorCamera"
	_spectator_camera.enabled = true
	_spectator_camera.zoom = Vector2(SPECTATOR_ZOOM, SPECTATOR_ZOOM)
	_spectator_camera.position_smoothing_enabled = true
	_spectator_camera.position_smoothing_speed = 10.0
	add_child(_spectator_camera)

	_spectator_panel = SPECTATOR_PANEL_SCENE.instantiate()
	_spectator_panel.prev_requested.connect(_cycle_target.bind(-1))
	_spectator_panel.next_requested.connect(_cycle_target.bind(1))
	_ui_layer.add_child(_spectator_panel)

	_setup_pause_menu()

	_hide_canvas_modulates()
	_reveal_players()

	var hud := get_tree().get_first_node_in_group(GroupNames.GAME_HUD)
	if hud and hud.has_method("set_spectator_ui_active"):
		hud.set_spectator_ui_active(true)

	set_process(true)


func _disable_local_player_camera() -> void:
	var my_player := PlayerRegistry.get_player(multiplayer.get_unique_id())
	if my_player and my_player.has_node("Camera2D"):
		my_player.get_node("Camera2D").enabled = false


func _setup_pause_menu() -> void:
	var hud := get_tree().get_first_node_in_group(GroupNames.GAME_HUD)
	if hud:
		return
	var menu := GAME_MENU_SCENE.instantiate()
	menu.name = "SpectatorMenu"
	_ui_layer.add_child(menu)


func _process(delta: float) -> void:
	if not _active:
		return
	_handle_input(delta)
	_update_camera(delta)
	_update_panel()


func _handle_input(delta: float) -> void:
	if Input.is_action_just_pressed("spec_toggle"):
		_spec_is_freecam = not _spec_is_freecam
		if _spectator_camera:
			if _spec_is_freecam:
				_spec_freecam_offset = _spectator_camera.position
			_spectator_camera.position_smoothing_enabled = not _spec_is_freecam
		if not _spec_is_freecam:
			_cycle_target(1)

	var next_dir := 0
	if Input.is_action_just_pressed("spec_next"):
		next_dir = 1
	elif Input.is_action_just_pressed("spec_prev"):
		next_dir = -1
	if next_dir != 0:
		_cycle_target(next_dir)

	if _spec_is_freecam:
		var move := Input.get_vector("spec_left", "spec_right", "spec_up", "spec_down")
		_spec_freecam_offset += move * _spec_freecam_speed * delta


func _update_camera(_delta: float) -> void:
	if not _spectator_camera:
		return
	if _spec_is_freecam:
		_spectator_camera.position = _spec_freecam_offset
	else:
		if _follow_target and is_instance_valid(_follow_target):
			_spectator_camera.global_position = _follow_target.global_position
		else:
			_cycle_target(1)


func _cycle_target(direction: int) -> void:
	var all_players := get_tree().get_nodes_in_group(GroupNames.PLAYERS)
	var alive_players: Array[Node] = []
	for p in all_players:
		if is_instance_valid(p) and "health_state" in p and p.health_state == "alive":
			alive_players.append(p)
	if alive_players.is_empty():
		_follow_target = null
		return

	var current_idx := -1
	if _follow_target and is_instance_valid(_follow_target):
		current_idx = alive_players.find(_follow_target)

	var new_idx := current_idx + direction
	while new_idx < 0:
		new_idx += alive_players.size()
	new_idx = new_idx % alive_players.size()

	_follow_target = alive_players[new_idx]


func _update_panel() -> void:
	if not _spectator_panel:
		return

	if not _follow_target or not is_instance_valid(_follow_target):
		_spectator_panel.set_target(-1, "?", "", null)
		_spectator_panel.set_hp(0, 100)
		return

	var pid := _follow_target.get_multiplayer_authority()
	if "health_state" in _follow_target and _follow_target.health_state != "alive":
		_cycle_target(1)
		return

	var pdata: Dictionary = LobbyManager.players.get(pid, {})
	var char_id: int = pdata.get("character_id", -1)
	if char_id == -1 and "character_data" in _follow_target and _follow_target.character_data:
		char_id = _follow_target.character_data.id

	var display_name := "?"
	var icon_frames: SpriteFrames = null
	var fallback_tex: Texture2D = null
	if char_id != -1:
		var cdata: CharacterData = CharacterRegistry.get_character(char_id)
		if cdata:
			display_name = cdata.display_name
			icon_frames = cdata.animation_frames
			fallback_tex = cdata.icon

	var player_name: String = pdata.get("name", "")
	_spectator_panel.set_target(pid, display_name, player_name, icon_frames, fallback_tex)

	var hp := 0
	var max_hp := 100
	if "health" in _follow_target:
		hp = _follow_target.health
	if "character_data" in _follow_target and _follow_target.character_data:
		max_hp = _follow_target.character_data.max_health
	_spectator_panel.set_hp(hp, max_hp)


func _hide_canvas_modulates() -> void:
	for cm in _get_all_nodes_of_type(get_tree().root, "CanvasModulate"):
		cm.visible = false


func _reveal_players() -> void:
	for other in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if not is_instance_valid(other):
			continue
		if "animated_sprite" in other and other.animated_sprite:
			other.animated_sprite.self_modulate.a = 1.0
			other.animated_sprite.visible = true
		if other.has_node("NameTag"):
			other.name_tag.visible = true


func _get_all_nodes_of_type(from: Node, type_name: String) -> Array[Node]:
	var result: Array[Node] = []
	if from.get_class() == type_name:
		result.append(from)
	for child in from.get_children():
		result.append_array(_get_all_nodes_of_type(child, type_name))
	return result
