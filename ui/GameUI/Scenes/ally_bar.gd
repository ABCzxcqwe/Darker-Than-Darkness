# ally_bar.gd
extends Control

@onready var icon_rect:  TextureRect = $HBoxContainer/IconRect
@onready var name_label: Label       = $HBoxContainer/NameLabel
@onready var hp_bar:     ProgressBar = $HBoxContainer/InfoColumn/HPRow/HPBar
@onready var hp_label:   Label       = $HBoxContainer/InfoColumn/NameRow/HPLabel
@onready var bg_panel:   Panel       = $BGPanel

var _peer_id:     int   = -1
var _theme_color: Color = Color.WHITE


func setup(player_node: Node) -> void:
	if not player_node.character_data:
		push_warning("[AllyBar] Player sin character_data.")
		return

	_peer_id     = player_node.get_multiplayer_authority()
	var data     = player_node.character_data
	_theme_color = data.theme_color

	if icon_rect:
		icon_rect.texture = data.icon if data.icon else null
	if name_label:
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

	var coord = GameServiceLocator.get_service("MapEventCoordinator")
	if coord and coord.has_player_escaped(_peer_id):
		if name_label: name_label.text = "★ ESCAPED ★"
		_apply_bar_color("escaped")
		_apply_border_color(Color(0.0, 0.8, 0.8))

	var hs = GameServiceLocator.get_service("HealthService")
	if hs:
		hs.health_changed.connect(_on_health_changed)
		hs.player_state_changed.connect(_on_state_changed)


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


func _format_hp(cur: int, max_hp: int) -> String:
	return "%d/ %d" % [cur, max_hp]
