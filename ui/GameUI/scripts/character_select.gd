extends Control

@onready var timer_label: Label = $TimerLabel
@onready var role_label: Label = $RoleLabel
@onready var options_container: GridContainer = $CharacterOptionsContainer
@onready var selections_list: ItemList = $PlayerSelectionsList

var time_left: int = 10
var local_role: String = "survivor"
var available_char_ids: Array[int] = []
var selected_char_id: int = -1
var timer_active: bool = true

var _focus_items: Array[Control] = []
var _focus_idx := 0

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
	_setup_focus()

func _setup_focus() -> void:
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color(0.114, 0.114, 0.114, 1)
	focus_style.border_color = Color.WHITE
	focus_style.border_width_left = 3
	focus_style.border_width_top = 3
	focus_style.border_width_right = 3
	focus_style.border_width_bottom = 3
	focus_style.set_corner_radius_all(3)
	focus_style.set_expand_margin_all(5)
	_focus_items = []
	for c in options_container.get_children():
		if c is Button:
			_focus_items.append(c)
	for i in _focus_items.size():
		_focus_items[i].add_theme_stylebox_override("focus", focus_style)
		_focus_items[i].focus_entered.connect(_update_focus.bind(i))
	if _focus_items.size() > 0:
		_focus_items[0].grab_focus()
		_focus_idx = 0

func _update_focus(i: int) -> void:
	_focus_idx = i

func _input(event):
	if event is InputEventKey and event.pressed and not event.is_echo():
		var kc = event.keycode
		var pkc = event.physical_keycode
		if kc != KEY_W and kc != KEY_S and pkc != KEY_W and pkc != KEY_S:
			return

		if (kc == KEY_W or pkc == KEY_W) and _focus_idx > 0:
			_focus_idx -= 1
			_focus_items[_focus_idx].grab_focus()
			AudioManager.play_sfx_ui(2)
			get_viewport().set_input_as_handled()
		elif (kc == KEY_S or pkc == KEY_S) and _focus_idx < _focus_items.size() - 1:
			_focus_idx += 1
			_focus_items[_focus_idx].grab_focus()
			AudioManager.play_sfx_ui(2)
			get_viewport().set_input_as_handled()


func _build_character_options() -> void:
	for child in options_container.get_children():
		child.queue_free()

	available_char_ids.clear()

	print("[CharacterSelect] Cargando opciones desde CharacterRegistry para el rol: ", local_role)

	for data in CharacterRegistry.get_all():
		if data.team.to_lower().strip_edges() == local_role.to_lower().strip_edges():
			print("[CharacterSelect] Personaje viable detectado: ID %d (%s)" % [data.id, data.display_name])
			available_char_ids.append(data.id)
			_create_character_button(data.id, data)

	print("[CharacterSelect] Inicialización de botones completa. Total: ", available_char_ids.size())


func _create_character_button(char_id: int, data: CharacterData) -> void:
	var btn := Button.new()
	btn.text = data.display_name
	btn.custom_minimum_size = Vector2(120, 50)

	if data.icon:
		btn.icon = data.icon
		btn.expand_icon = true

	btn.pressed.connect(func(): _on_character_clicked(char_id))
	options_container.add_child(btn)


func _on_character_clicked(char_id: int) -> void:
	if not timer_active: return
	AudioManager.play_sfx_ui(1)
	selected_char_id = char_id

	NetworkManager.select_character_in_screen(char_id)

	for child in options_container.get_children():
		if child is Button:
			if child.get_index() == available_char_ids.find(char_id):
				child.modulate = Color.GREEN
			else:
				child.modulate = Color.WHITE


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
		NetworkManager.select_character_in_screen(random_id)
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
