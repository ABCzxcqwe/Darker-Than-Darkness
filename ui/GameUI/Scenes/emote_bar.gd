extends HBoxContainer

const KEY_NAMES := {
	0: "1",
	1: "2",
	2: "3",
	3: "4",
}

var _player_node: Node = null

func setup(player_node: Node) -> void:
	_player_node = player_node
	if not player_node.character_data:
		push_warning("[EmoteBar] Player sin character_data.")
		return
	var slots: Array = player_node.character_data.emote_slots
	for i in slots.size():
		var data: EmoteData = slots[i]
		if not data:
			continue

		var key_name: String = KEY_NAMES.get(i, str(i))

		var btn := Control.new()
		btn.custom_minimum_size = Vector2(75, 75)

		# Panel con fondo oscuro + borde naranja
		var panel := Panel.new()
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.47)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.82, 0.47, 0.0, 1.0)
		style.set_corner_radius_all(3)
		style.corner_detail = 1
		panel.add_theme_stylebox_override("panel", style)
		btn.add_child(panel)

		# Icono con margen 2px para que no tape el borde
		var icon_rect := TextureRect.new()
		icon_rect.anchor_left = 0.0
		icon_rect.anchor_top = 0.0
		icon_rect.anchor_right = 1.0
		icon_rect.anchor_bottom = 1.0
		icon_rect.offset_left = 2
		icon_rect.offset_top = 2
		icon_rect.offset_right = -2
		icon_rect.offset_bottom = -2
		icon_rect.texture = data.icon if data.icon else null
		icon_rect.expand_mode = 1
		icon_rect.stretch_mode = 5
		panel.add_child(icon_rect)

		# Tecla (1-4) en esquina superior derecha
		var key_label := Label.new()
		key_label.anchors_preset = 1
		key_label.anchor_left = 1.0
		key_label.anchor_right = 1.0
		key_label.offset_left = -14.0
		key_label.offset_bottom = 21.0
		key_label.grow_horizontal = 0
		key_label.text = key_name
		key_label.uppercase = true
		var font := preload("res://Fonts/deltarune font.ttf")
		key_label.add_theme_font_override("font", font)
		key_label.add_theme_font_size_override("font_size", 20)
		btn.add_child(key_label)

		add_child(btn)
