extends HBoxContainer

var _player_node: Node = null
var _buttons: Array = []

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

		var btn := _build_button(i)

		add_child(btn)
		_buttons.append({"slot": i, "btn": btn})

	if InputService.device_changed.is_connected(_on_device_changed):
		InputService.device_changed.disconnect(_on_device_changed)
	InputService.device_changed.connect(_on_device_changed)
	_refresh_labels()


func _build_button(slot: int) -> Control:
	var key_name: String = InputService.get_emote_label(slot)
	var data: EmoteData = _player_node.character_data.emote_slots[slot]

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
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE as TextureRect.ExpandMode
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED as TextureRect.StretchMode
	panel.add_child(icon_rect)

	# Tecla (1-4 / DPAD) en esquina superior derecha
	var key_label := Label.new()
	key_label.anchors_preset = 1
	key_label.anchor_left = 1.0
	key_label.anchor_right = 1.0
	key_label.offset_left = -14.0
	key_label.offset_bottom = 21.0
	key_label.grow_horizontal = 0
	key_label.text = key_name
	key_label.uppercase = true
	key_label.name = "KeyLabel"
	var font := preload("res://Fonts/deltarune font.ttf")
	key_label.add_theme_font_override("font", font)
	key_label.add_theme_font_size_override("font_size", 20)
	btn.add_child(key_label)

	return btn


func _refresh_labels() -> void:
	for entry in _buttons:
		var slot: int = entry["slot"]
		var btn: Control = entry["btn"]
		var key_label: Label = btn.get_node_or_null("KeyLabel")
		if key_label:
			key_label.text = InputService.get_emote_label(slot)


func _on_device_changed(_device: int) -> void:
	_refresh_labels()
