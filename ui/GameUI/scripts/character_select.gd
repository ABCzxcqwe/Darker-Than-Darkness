extends Control

@onready var timer_label: Label = $TimerLabel
@onready var role_label: Label = $RoleLabel
@onready var panels_container: Control = $PanelsContainer
@onready var selections_list: ItemList = $PlayerSelectionsList

var time_left: int = 10
var local_role: String = "survivor"
var available_char_ids: Array[int] = []
var selected_char_id: int = -1
var timer_active: bool = true

var _focus_idx := 0
var _selection_locked := false


func _ready() -> void:
	add_to_group("character_select_screen")

	NetworkManager.lobby_updated.connect(_on_lobby_updated)

	var my_id := multiplayer.get_unique_id()
	if NetworkManager.players.has(my_id):
		local_role = NetworkManager.players[my_id]["assigned_role"]

	if local_role == "killer":
		role_label.text = "ROL: KILLER (CAZADOR)"
		role_label.modulate = Color.MAGENTA
	else:
		role_label.text = "ROL: SURVIVOR (EQUIPO)"
		role_label.modulate = Color.CYAN

	_build_character_options()
	_on_lobby_updated()
	_start_countdown()


func _build_character_options() -> void:
	for child in panels_container.get_children():
		child.queue_free()

	available_char_ids.clear()

	for data in CharacterRegistry.get_all():
		if data.team.to_lower().strip_edges() == local_role.to_lower().strip_edges():
			if data.panel_texture:
				available_char_ids.append(data.id)

	_focus_idx = 0
	_selection_locked = false

	var border_on := StyleBoxFlat.new()
	border_on.bg_color = Color.TRANSPARENT
	border_on.border_color = Color.WHITE
	border_on.border_width_left = 4
	border_on.border_width_top = 4
	border_on.border_width_right = 4
	border_on.border_width_bottom = 4
	border_on.set_corner_radius_all(4)

	var border_locked := StyleBoxFlat.new()
	border_locked.bg_color = Color.TRANSPARENT
	border_locked.border_color = Color.YELLOW
	border_locked.border_width_left = 4
	border_locked.border_width_top = 4
	border_locked.border_width_right = 4
	border_locked.border_width_bottom = 4
	border_locked.set_corner_radius_all(4)

	var border_off := StyleBoxFlat.new()
	border_off.bg_color = Color.TRANSPARENT
	border_off.border_color = Color(1, 1, 1, 0)

	for i in available_char_ids.size():
		var char_id = available_char_ids[i]
		var char_data = CharacterRegistry.get_character(char_id)

		var panel_wrap := PanelContainer.new()
		panel_wrap.custom_minimum_size = Vector2(220, 330)
		panel_wrap.add_theme_stylebox_override("panel", border_off)
		panel_wrap.set_meta("border_on", border_on)
		panel_wrap.set_meta("border_locked", border_locked)
		panel_wrap.set_meta("border_off", border_off)

		var tex := TextureRect.new()
		tex.texture = char_data.panel_texture
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_STOP
		tex.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				AudioManager.play_sfx_ui(1)
				_focus_idx = available_char_ids.find(char_id)
				_confirm_selection(char_id)
		)
		panel_wrap.add_child(tex)
		panels_container.add_child(panel_wrap)

		panel_wrap.set_meta("char_id", char_id)

	# Default-highlight first
	if available_char_ids.size() > 0:
		_on_character_clicked(available_char_ids[0])

	_reposition_panels()


func _reposition_panels() -> void:
	var count = available_char_ids.size()
	if count == 0:
		return

	var panel_w = 220
	var gap = 40
	var total_w = count * panel_w + (count - 1) * gap
	var start_x = -total_w / 2 + panel_w / 2

	for i in panels_container.get_child_count():
		var child = panels_container.get_child(i)
		child.position = Vector2(start_x + i * (panel_w + gap), -child.custom_minimum_size.y / 2)


func _update_selection(prev_idx: int) -> void:
	if prev_idx >= 0 and prev_idx < panels_container.get_child_count():
		var prev = panels_container.get_child(prev_idx)
		prev.add_theme_stylebox_override("panel", prev.get_meta("border_off"))

	if _focus_idx >= 0 and _focus_idx < panels_container.get_child_count():
		var cur = panels_container.get_child(_focus_idx)
		cur.add_theme_stylebox_override("panel", cur.get_meta("border_on"))


func _input(event):
	if event is InputEventKey and event.pressed and not event.is_echo():
		var kc = event.keycode
		var pkc = event.physical_keycode
		var is_left = (kc == KEY_A or pkc == KEY_A or kc == KEY_LEFT or pkc == KEY_LEFT)
		var is_right = (kc == KEY_D or pkc == KEY_D or kc == KEY_RIGHT or pkc == KEY_RIGHT)
		var is_enter = (kc == KEY_ENTER or kc == KEY_KP_ENTER or kc == KEY_SPACE)

		if _selection_locked:
			return

		if is_enter and available_char_ids.size() > 0:
			AudioManager.play_sfx_ui(1)
			_confirm_selection(available_char_ids[_focus_idx])
			get_viewport().set_input_as_handled()
			return

		if not is_left and not is_right:
			return

		var prev = _focus_idx
		if is_left and _focus_idx > 0:
			_focus_idx -= 1
		elif is_right and _focus_idx < available_char_ids.size() - 1:
			_focus_idx += 1
		else:
			return

		AudioManager.play_sfx_ui(2)
		_update_selection(prev)
		get_viewport().set_input_as_handled()


func _on_character_clicked(char_id: int) -> void:
	if _selection_locked or not timer_active:
		return
	for i in panels_container.get_child_count():
		var _wrap = panels_container.get_child(i)
		if _wrap.get_meta("char_id") == char_id:
			_wrap.add_theme_stylebox_override("panel", _wrap.get_meta("border_on"))
		else:
			_wrap.add_theme_stylebox_override("panel", _wrap.get_meta("border_off"))
	_focus_idx = available_char_ids.find(char_id)


func _confirm_selection(char_id: int) -> void:
	if _selection_locked or not timer_active:
		return
	_selection_locked = true
	selected_char_id = char_id
	NetworkManager.select_character_in_screen(char_id)
	for i in panels_container.get_child_count():
		var _wrap = panels_container.get_child(i)
		if _wrap.get_meta("char_id") == char_id:
			_wrap.add_theme_stylebox_override("panel", _wrap.get_meta("border_locked"))
		else:
			_wrap.add_theme_stylebox_override("panel", _wrap.get_meta("border_off"))


func _on_lobby_updated() -> void:
	selections_list.clear()

	for p in NetworkManager.get_player_list():
		var text = p.name
		if p.id == multiplayer.get_unique_id():
			text += " (Tú)"

		var char_name = "Eligiendo..."
		if p.character_id != -1:
			var data := CharacterRegistry.get_character(p.character_id)
			char_name = data.display_name if data else "?"

		var display_role = p.get("assigned_role", "survivor").to_upper()
		text += " -> " + char_name + " [" + display_role + "]"
		selections_list.add_item(text)


func _start_countdown() -> void:
	while time_left > 0 and timer_active and is_inside_tree():
		timer_label.text = "Tiempo restante: %d" % time_left
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
		time_left -= 1

	if timer_active and is_inside_tree():
		_on_timeout_expired()


func _on_timeout_expired() -> void:
	timer_active = false
	if not is_inside_tree():
		return
	timer_label.text = "¡Tiempo Terminado!"

	if selected_char_id == -1 and available_char_ids.size() > 0:
		var random_id = available_char_ids[randi() % available_char_ids.size()]
		selected_char_id = random_id
		_selection_locked = true
		NetworkManager.select_character_in_screen(random_id)
		for i in panels_container.get_child_count():
			var _wrap = panels_container.get_child(i)
			if _wrap.get_meta("char_id") == random_id:
				_wrap.add_theme_stylebox_override("panel", _wrap.get_meta("border_locked"))
			else:
				_wrap.add_theme_stylebox_override("panel", _wrap.get_meta("border_off"))
		print("[CharacterSelect] Jugador AFK. Auto-seleccionado ID: ", random_id)

	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return

	if NetworkManager.is_host:
		_host_resolve_missing_selections()
		MatchCoordinator.host_launch_game()


func _host_resolve_missing_selections() -> void:
	for pid in NetworkManager.players:
		if NetworkManager.players[pid]["character_id"] == -1:
			var role = NetworkManager.players[pid]["assigned_role"]
			var fallback_id := 0
			for data in CharacterRegistry.get_all():
				if data.team == role:
					fallback_id = data.id
					break
			NetworkManager.players[pid]["character_id"] = fallback_id
