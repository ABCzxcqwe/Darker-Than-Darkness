extends PanelContainer

var _peer_id:      int   = -1
var _theme_color:  Color = Color(0.27, 0.78, 0.95)


func setup(player_node: Node) -> void:
	if not player_node.character_data:
		return

	_peer_id     = player_node.get_multiplayer_authority()
	var data: CharacterData = player_node.character_data
	_theme_color = data.theme_color

	_apply_border_color(_theme_color)

func _apply_border_color(color: Color) -> void:
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var s := style.duplicate() as StyleBoxFlat
		s.border_color = color
		add_theme_stylebox_override("panel", s)
