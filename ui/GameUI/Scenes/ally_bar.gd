# ally_bar.gd
extends Control

@onready var icon_rect:  AnimatedIcon = $HBoxContainer/IconRect
@onready var name_label: Label       = $HBoxContainer/NameLabel
@onready var hp_bar:     ProgressBar = $HBoxContainer/InfoColumn/HPRow/HPBar
@onready var hp_label:   Label       = $HBoxContainer/InfoColumn/NameRow/HPLabel
@onready var bg_panel:   Panel       = $BGPanel
@onready var target_frame: Control  = $TargetFrame
@onready var _corner_tl_h: ColorRect = $TargetFrame/CornerTL_H
@onready var _corner_tl_v: ColorRect = $TargetFrame/CornerTL_V
@onready var _corner_br_h: ColorRect = $TargetFrame/CornerBR_H
@onready var _corner_br_v: ColorRect = $TargetFrame/CornerBR_V
@onready var _label_objetivo: Label = $TargetFrame/LabelObjetivo

var _peer_id:     int   = -1
var _theme_color: Color = Color.WHITE
var _player_node: Node = null
var _chase_poll_timer: float = 0.0
var _is_chased: bool = false
var _is_dead_state: bool = false
var _tween_chase: Tween = null
var _form_a: bool = true


func setup(player_node: Node) -> void:
	if not player_node.character_data:
		push_warning("[AllyBar] Player sin character_data.")
		return

	_peer_id     = player_node.get_multiplayer_authority()
	_player_node = player_node
	var data     = player_node.character_data
	_theme_color = data.theme_color

	if icon_rect:
		icon_rect.setup(data.animation_frames, "icon", data.icon)
	if name_label:
		var pinfo: Dictionary = LobbyManager.players.get(_peer_id, {})
		var pname: String = str(pinfo.get("name", "")).strip_edges()
		if pname != "":
			name_label.text = pname.to_upper()
		else:
			name_label.text = data.display_name.to_upper()
	if hp_bar:
		hp_bar.max_value = data.max_health
		hp_bar.value     = player_node.health
	if hp_label:
		hp_label.text = _format_hp(player_node.health, data.max_health)

	var current_state = player_node.health_state if "health_state" in player_node else "alive"
	_apply_bar_color(current_state)
	match current_state:
		"dead":
			if name_label: name_label.modulate = Color(0.3, 0.3, 0.3)
			_apply_border_color(Color(0.2, 0.2, 0.2))
			modulate.a = 0.35
		"downed":
			if name_label: name_label.modulate = Color(1.0, 0.5, 0.0)
			_apply_border_color(Color(1.0, 0.5, 0.0))
		_:
			_apply_border_color(_theme_color)

	var relay: Node = GameServiceLocator.get_client_relay()
	if relay:
		if relay.has_signal("health_changed"):
			relay.health_changed.connect(_on_health_changed)
		if relay.has_signal("player_state_changed"):
			relay.player_state_changed.connect(_on_state_changed)

	# Inicializar marco objetivo oculto y activar poll de chase
	if target_frame:
		target_frame.visible = false
	_apply_target_frame_form(true)
	set_process(true)


func _on_health_changed(peer_id: int, current_hp: int, max_hp: int) -> void:
	if peer_id != _peer_id:
		return
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value     = current_hp
	if hp_label:
		hp_label.text = _format_hp(current_hp, max_hp)


func _on_state_changed(peer_id: int, state: String) -> void:
	if peer_id != _peer_id:
		return
	_is_dead_state = state in ["dead", "escaped"]
	_apply_bar_color(state)
	match state:
		"downed":
			if name_label: name_label.modulate = Color(1.0, 0.5, 0.0)
			_apply_border_color(Color(1.0, 0.5, 0.0))
		"dead":
			if name_label: name_label.modulate = Color(0.3, 0.3, 0.3)
			_apply_border_color(Color(0.2, 0.2, 0.2))
			modulate.a = 0.35
		"escaped":
			if name_label: name_label.text = "★ ESCAPED ★"
			_apply_border_color(Color(0.0, 0.8, 0.8))
		"alive":
			if name_label: name_label.modulate = Color.WHITE
			_apply_border_color(_theme_color)
			modulate.a = 1.0
	if _is_dead_state and _is_chased:
		_set_chased(false)


func _apply_bar_color(state: String) -> void:
	if not hp_bar:
		return
	var color: Color
	match state:
		"downed":  color = Color(1.0, 0.5, 0.0)
		"dead":    color = Color(0.3, 0.3, 0.3)
		"escaped": color = Color(0.0, 0.8, 0.8)
		_:         color = _theme_color
	var sb = hp_bar.get_theme_stylebox("fill").duplicate()
	if sb is StyleBoxFlat:
		sb.bg_color = color
		hp_bar.add_theme_stylebox_override("fill", sb)


func _apply_border_color(color: Color) -> void:
	if not bg_panel:
		return
	var style = bg_panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var s := style.duplicate() as StyleBoxFlat
		s.border_color = color
		bg_panel.add_theme_stylebox_override("panel", s)


func _process(delta: float) -> void:
	if _is_dead_state or not is_instance_valid(_player_node):
		return
	_chase_poll_timer += delta
	if _chase_poll_timer < 0.15:
		return
	_chase_poll_timer = 0.0
	var chased_now: bool = _is_player_chased()
	if chased_now != _is_chased:
		_set_chased(chased_now)


func _is_player_chased() -> bool:
	if not is_instance_valid(_player_node):
		return false
	if _player_node.health_state != "alive":
		return false
	var killers: Array = get_tree().get_nodes_in_group(GroupNames.KILLER)
	if killers.is_empty():
		killers = get_tree().get_nodes_in_group("killer")
	if killers.is_empty():
		return false
	var my_pos: Vector2 = _player_node.global_position
	for k in killers:
		if not is_instance_valid(k) or not k.character_data:
			continue
		var base_r: float = float(k.character_data.chase_radius) if "chase_radius" in k.character_data else 200.0
		var chase_r: float = base_r * 2.0
		if my_pos.distance_to(k.global_position) < chase_r:
			return true
	return false


func _set_chased(chased: bool) -> void:
	_is_chased = chased
	if not target_frame:
		return
	if chased:
		target_frame.visible = true
		# Borde blanco más grande que panel (8px expand ya en escena) + forzar borde BGPanel a blanco
		_apply_border_color(Color.WHITE)
		_start_chase_tween()
	else:
		target_frame.visible = false
		_stop_chase_tween()
		# Restaurar borde según estado
		var state: String = _player_node.health_state if _player_node and "health_state" in _player_node else "alive"
		if state == "downed":
			_apply_border_color(Color(1.0, 0.5, 0.0))
		elif state == "dead":
			_apply_border_color(Color(0.2, 0.2, 0.2))
		else:
			_apply_border_color(_theme_color)


func _apply_target_frame_form(is_form_a: bool) -> void:
	if not target_frame:
		return
	_form_a = is_form_a
	if not _corner_tl_h or not _corner_tl_v or not _corner_br_h or not _corner_br_v:
		return
	if is_form_a:
		# Forma A: TL largo (40) desde -10 => 30, V30 desde -12 => 18; BR corto H28 (-18) / V32 (-22)
		_corner_tl_h.offset_right = 30.0
		_corner_tl_v.offset_bottom = 18.0
		_corner_br_h.offset_left = -18.0
		_corner_br_v.offset_top = -22.0
	else:
		# Forma B: TL corto (24) => 14, V18 => 6; BR largo H42 (-32) / V24 (-14)
		_corner_tl_h.offset_right = 14.0
		_corner_tl_v.offset_bottom = 6.0
		_corner_br_h.offset_left = -32.0
		_corner_br_v.offset_top = -14.0


func _start_chase_tween() -> void:
	if _tween_chase and _tween_chase.is_valid():
		_tween_chase.kill()
	_tween_chase = create_tween()
	_tween_chase.set_loops()
	_tween_chase.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween_chase.tween_callback(func() -> void: _apply_target_frame_form(false)).set_delay(0.45)
	_tween_chase.tween_callback(func() -> void: _apply_target_frame_form(true)).set_delay(0.45)


func _stop_chase_tween() -> void:
	if _tween_chase and _tween_chase.is_valid():
		_tween_chase.kill()
	_tween_chase = null
	_apply_target_frame_form(true)


func _exit_tree() -> void:
	if _tween_chase and _tween_chase.is_valid():
		_tween_chase.kill()
	_tween_chase = null


func _format_hp(cur: int, max_hp: int) -> String:
	return "%d/ %d" % [cur, max_hp]
