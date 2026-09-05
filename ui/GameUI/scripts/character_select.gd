extends Control

@onready var timer_label: Label = $TopBar/TimerLabel
@onready var timer_sub_label: Label = $TopBar/TimerSubLabel
@onready var role_label: Label = $BottomBar/RoleLabel
@onready var hint_label: Label = $BottomBar/HintLabel
@onready var panels_container: Control = $CenterAnchor/PanelsContainer
@onready var selections_list: ItemList = $PlayerSelectionsList
@onready var countdown_timer: Timer = $CountdownTimer

var time_left: int = 15
var local_role: String = "survivor"
var available_char_ids: Array[int] = []
var selected_char_id: int = -1
var timer_active: bool = true

var _focus_idx := 0
var _selection_locked := false
var _is_animating := false

# Cylinder config
const PANEL_W := 220.0
const PANEL_H := 330.0
const CYLINDER_X_STEP := 200.0
const CYLINDER_SCALE_FALLOFF := 0.18
const CYLINDER_ALPHA_FALLOFF := 0.28
const CYLINDER_ANIM_DURATION := 0.28
const CYLINDER_MIN_SCALE := 0.55


func _ready() -> void:
	add_to_group("character_select_screen")

	LobbyManager.lobby_updated.connect(_on_lobby_updated)
	countdown_timer.timeout.connect(_on_tick)

	var my_id := multiplayer.get_unique_id()
	if LobbyManager.is_spectator(my_id):
		role_label.text = "ROL: ESPECTADOR"
		role_label.modulate = Color.GRAY
		timer_label.text = "--"
		if timer_sub_label:
			timer_sub_label.text = "ESPERANDO INICIO DE PARTIDA..."
		if hint_label:
			hint_label.text = "MODO ESPECTADOR"
		timer_active = false
		countdown_timer.stop()
		return

	if LobbyManager.players.has(my_id):
		local_role = LobbyManager.players[my_id]["assigned_role"]

	if local_role == "killer":
		role_label.text = "ROL: KILLER (CAZADOR)"
		role_label.modulate = Color.MAGENTA
	else:
		role_label.text = "ROL: SURVIVOR (EQUIPO)"
		role_label.modulate = Color.CYAN

	_build_character_options()
	_on_lobby_updated()
	_start_countdown()
	# Recalcular en resize para responsividad
	get_viewport().size_changed.connect(func(): _layout_cylinder(false))


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

	var border_off := StyleBoxFlat.new()
	border_off.bg_color = Color.TRANSPARENT
	border_off.border_color = Color(1, 1, 1, 0)
	border_off.set_corner_radius_all(6)

	for i in available_char_ids.size():
		var char_id = available_char_ids[i]
		var char_data: CharacterData = CharacterRegistry.get_character(char_id)
		if char_data == null:
			continue
		var theme: Color = char_data.theme_color if char_data.theme_color != Color(0,0,0,0) else Color.WHITE

		var border_on := StyleBoxFlat.new()
		border_on.bg_color = Color.TRANSPARENT
		border_on.border_color = theme
		border_on.border_width_left = 4
		border_on.border_width_top = 4
		border_on.border_width_right = 4
		border_on.border_width_bottom = 4
		border_on.set_corner_radius_all(6)
		border_on.shadow_color = Color(theme.r, theme.g, theme.b, 0.45)
		border_on.shadow_size = 8

		var border_locked := StyleBoxFlat.new()
		border_locked.bg_color = Color(1, 1, 0, 0.08)
		border_locked.border_color = Color.YELLOW
		border_locked.border_width_left = 5
		border_locked.border_width_top = 5
		border_locked.border_width_right = 5
		border_locked.border_width_bottom = 5
		border_locked.set_corner_radius_all(6)
		border_locked.shadow_color = Color(1, 1, 0, 0.6)
		border_locked.shadow_size = 12

		# Wrapper vertical: panel + name label (solo teclado — sin mouse)
		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.custom_minimum_size = Vector2(PANEL_W, PANEL_H + 44)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.set_meta("char_id", char_id)
		vbox.set_meta("border_on", border_on)
		vbox.set_meta("border_locked", border_locked)
		vbox.set_meta("border_off", border_off)
		vbox.set_meta("theme_color", theme)

		var panel_wrap := PanelContainer.new()
		panel_wrap.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
		panel_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		panel_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel_wrap.add_theme_stylebox_override("panel", border_off)
		# Guardar refs de borde también en panel_wrap para fácil acceso
		panel_wrap.set_meta("border_on", border_on)
		panel_wrap.set_meta("border_locked", border_locked)
		panel_wrap.set_meta("border_off", border_off)

		var tex := TextureRect.new()
		tex.name = "PanelTexture"
		tex.texture = char_data.panel_texture
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.set_meta("char_id", char_id)
		panel_wrap.add_child(tex)
		vbox.add_child(panel_wrap)

		var name_label := Label.new()
		name_label.name = "NameLabel"
		name_label.text = char_data.display_name.to_upper()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_override("font", load("uid://dvelfumepo3c0"))
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_label.add_theme_color_override("font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override("outline_size", 6)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(name_label)

		panels_container.add_child(vbox)
		# Posición inicial (sin animar) se setea luego en _layout_cylinder
		vbox.position = Vector2(-PANEL_W / 2, -PANEL_H / 2)
		vbox.scale = Vector2.ONE
		vbox.modulate.a = 0.0
		vbox.z_index = 0

	if available_char_ids.size() > 0:
		_focus_idx = 0
		_layout_cylinder(false)
		_update_name_labels()
	else:
		push_warning("[CharacterSelect] No hay personajes para rol: " + local_role)


func _layout_cylinder(animated: bool) -> void:
	var count = panels_container.get_child_count()
	if count == 0:
		return

	for i in count:
		var vbox: Control = panels_container.get_child(i)
		var panel_wrap: PanelContainer = vbox.get_child(0) as PanelContainer
		var offset: int = i - _focus_idx
		var dist: float = abs(float(offset))

		# Posición X cilíndrica con solapamiento; fuera de rango se atenúa más
		var target_x: float = float(offset) * CYLINDER_X_STEP
		# Curvatura leve en Y para simular cilindro (parábola)
		var target_y: float = - (PANEL_H + 44) / 2.0 + dist * 10.0

		var target_scale_val: float = max(CYLINDER_MIN_SCALE, 1.0 - dist * CYLINDER_SCALE_FALLOFF)
		var target_scale := Vector2(target_scale_val, target_scale_val)
		var target_alpha: float = clamp(1.0 - dist * CYLINDER_ALPHA_FALLOFF, 0.25, 1.0)
		var target_z: int = 20 - int(dist * 5)

		# Ocultar completamente si está muy lejos (optimización visual con muchos personajes)
		if dist > 3:
			target_alpha = 0.0
			target_scale_val = CYLINDER_MIN_SCALE

		vbox.z_index = target_z
		# Orden de dibujo: centro arriba
		vbox.z_as_relative = false

		var target_pos := Vector2(target_x - (PANEL_W * target_scale_val) / 2.0 + (PANEL_W * target_scale_val) / 2.0 - (PANEL_W * target_scale_val)/2 + target_x - (PANEL_W*target_scale_val)/2, target_y)
		# Simplificar: centrar: x = offset*step
		target_pos = Vector2(target_x - (PANEL_W * target_scale_val) / 2.0, target_y)

		if animated and not _selection_locked:
			var tw := create_tween()
			tw.set_parallel(true)
			tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(vbox, "position", target_pos, CYLINDER_ANIM_DURATION)
			tw.tween_property(vbox, "scale", target_scale, CYLINDER_ANIM_DURATION)
			tw.tween_property(vbox, "modulate:a", target_alpha, CYLINDER_ANIM_DURATION * 0.8)
		else:
			vbox.position = target_pos
			vbox.scale = target_scale
			vbox.modulate.a = target_alpha

		# Borde y brillo según foco / lock
		if _selection_locked and selected_char_id != -1:
			var sel_idx = available_char_ids.find(selected_char_id)
			if i == sel_idx:
				panel_wrap.add_theme_stylebox_override("panel", panel_wrap.get_meta("border_locked"))
			else:
				panel_wrap.add_theme_stylebox_override("panel", panel_wrap.get_meta("border_off"))
				vbox.modulate.a = min(vbox.modulate.a, 0.35)
		else:
			if i == _focus_idx:
				panel_wrap.add_theme_stylebox_override("panel", panel_wrap.get_meta("border_on"))
			else:
				panel_wrap.add_theme_stylebox_override("panel", panel_wrap.get_meta("border_off"))

	_update_name_labels()


func _update_name_labels() -> void:
	for i in panels_container.get_child_count():
		var vbox: VBoxContainer = panels_container.get_child(i)
		var name_label: Label = vbox.get_node_or_null("NameLabel") as Label
		if name_label == null:
			continue
		var theme: Color = vbox.get_meta("theme_color") if vbox.has_meta("theme_color") else Color.WHITE
		if i == _focus_idx and not _selection_locked:
			name_label.add_theme_color_override("font_color", theme)
			name_label.modulate.a = 1.0
			name_label.scale = Vector2(1.08, 1.08)
		else:
			name_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
			name_label.modulate.a = 0.75 if i != _focus_idx else 1.0
			name_label.scale = Vector2.ONE
		if _selection_locked and selected_char_id != -1:
			var sel_idx = available_char_ids.find(selected_char_id)
			if i == sel_idx:
				name_label.add_theme_color_override("font_color", Color.YELLOW)
				name_label.modulate.a = 1.0
			elif name_label.modulate.a > 0.4:
				name_label.modulate.a = 0.4


func _animate_focus_change(prev_idx: int, new_idx: int) -> void:
	if _is_animating:
		return
	_is_animating = true
	_layout_cylinder(true)
	# Pequeño pulso en el nuevo foco
	if new_idx >= 0 and new_idx < panels_container.get_child_count():
		var vbox: Control = panels_container.get_child(new_idx)
		var orig_scale: Vector2 = vbox.scale
		var tw2 := create_tween()
		tw2.tween_property(vbox, "scale", orig_scale * 1.06, 0.1).set_trans(Tween.TRANS_QUAD)
		tw2.tween_property(vbox, "scale", orig_scale, 0.12).set_trans(Tween.TRANS_QUAD)
		await tw2.finished
	_is_animating = false
	_update_name_labels()


func _update_selection(_prev_idx: int) -> void:
	# Compat: ahora lo hace _layout_cylinder
	_layout_cylinder(true)


func _input(event):
	var vp := get_viewport()
	if vp == null:
		return
	if _selection_locked:
		# Permitir cancelar con ESC si aún hay tiempo (opcional, comentado si quieres bloqueo total)
		if event.is_action_pressed("menu_cancel"):
			# Si quieres permitir deselección, descomenta:
			# _selection_locked = false
			# selected_char_id = -1
			# _layout_cylinder(true)
			# vp.set_input_as_handled()
			pass
		return

	var is_left: bool = event.is_action_pressed("menu_left")
	var is_right: bool = event.is_action_pressed("menu_right")
	var is_enter: bool = event.is_action_pressed("menu_accept")

	if is_enter and available_char_ids.size() > 0:
		AudioManager.play_sfx_ui(SfxId.SELECT)
		_confirm_selection(available_char_ids[_focus_idx])
		vp.set_input_as_handled()
		return

	if not is_left and not is_right:
		return

	if available_char_ids.size() == 0:
		return

	var prev = _focus_idx
	if is_left:
		_focus_idx = (_focus_idx - 1 + available_char_ids.size()) % available_char_ids.size()
	elif is_right:
		_focus_idx = (_focus_idx + 1) % available_char_ids.size()
	else:
		return

	AudioManager.play_sfx_ui(SfxId.MENU_MOVE)
	_animate_focus_change(prev, _focus_idx)
	vp.set_input_as_handled()


func _on_character_clicked(char_id: int) -> void:
	if _selection_locked or not timer_active:
		return
	var idx = available_char_ids.find(char_id)
	if idx == -1:
		return
	var prev = _focus_idx
	_focus_idx = idx
	_animate_focus_change(prev, _focus_idx)


func _confirm_selection(char_id: int) -> void:
	if _selection_locked or not timer_active:
		return
	_selection_locked = true
	selected_char_id = char_id
	LobbyManager.select_character_in_screen(char_id)
	# Feedback visual inmediato: borde amarillo + oscurecer resto
	for i in panels_container.get_child_count():
		var vbox: Control = panels_container.get_child(i)
		var panel_wrap: PanelContainer = vbox.get_child(0) as PanelContainer
		if vbox.get_meta("char_id") == char_id:
			panel_wrap.add_theme_stylebox_override("panel", panel_wrap.get_meta("border_locked"))
			# Pulso de confirmación
			var tw := create_tween()
			tw.tween_property(vbox, "scale", vbox.scale * 1.12, 0.12).set_trans(Tween.TRANS_BACK)
			tw.tween_property(vbox, "scale", vbox.scale, 0.14).set_trans(Tween.TRANS_QUAD)
		else:
			panel_wrap.add_theme_stylebox_override("panel", panel_wrap.get_meta("border_off"))
			vbox.modulate.a = 0.32
	_update_name_labels()
	if hint_label:
		hint_label.text = "¡SELECCIÓN CONFIRMADA! ESPERANDO JUGADORES..."


func _on_lobby_updated() -> void:
	selections_list.clear()
	for p in LobbyManager.get_player_list():
		var text = p.name
		if p.id == multiplayer.get_unique_id():
			text += " (Tú)"
		var char_name = "Eligiendo..."
		var dot_color := Color.GRAY
		if p.character_id != -1:
			var data: CharacterData = CharacterRegistry.get_character(p.character_id)
			if data:
				char_name = data.display_name
				dot_color = data.theme_color
		var display_role = p.get("assigned_role", "survivor").to_upper()
		# bullet con color temático via unicode circle
		var bullet := "●"
		text = "%s %s -> %s [%s]" % [bullet, text, char_name, display_role]
		var idx = selections_list.add_item(text)
		selections_list.set_item_custom_fg_color(idx, dot_color if p.character_id != -1 else Color(0.7,0.7,0.7,1))


func _start_countdown() -> void:
	time_left = 15
	_update_timer_label()
	countdown_timer.wait_time = 1.0
	countdown_timer.start()


func _on_tick() -> void:
	if not timer_active or not is_inside_tree():
		countdown_timer.stop()
		return
	time_left -= 1
	_update_timer_label()
	if time_left <= 0:
		countdown_timer.stop()
		_on_timeout_expired()
	elif time_left <= 3:
		# Parpadeo rojo + shake leve
		timer_label.modulate = Color(1, 0.3, 0.3, 1)
		var tw := create_tween()
		tw.tween_property(timer_label, "scale", Vector2(1.15, 1.15), 0.1)
		tw.tween_property(timer_label, "scale", Vector2.ONE, 0.12)
		AudioManager.play_sfx_ui(SfxId.MENU_MOVE)


func _update_timer_label() -> void:
	if timer_label:
		timer_label.text = "%d" % maxi(time_left, 0)
		if time_left <= 3 and time_left > 0:
			timer_label.modulate = Color(1, 0.4, 0.4, 1)
		elif time_left <= 0:
			timer_label.modulate = Color.GRAY
		else:
			timer_label.modulate = Color.WHITE
	if timer_sub_label:
		if time_left > 3:
			timer_sub_label.text = "ELIGE TU DESTINO"
			timer_sub_label.modulate = Color(0.8, 0.8, 0.8, 1)
		elif time_left > 0:
			timer_sub_label.text = "¡TIEMPO SE AGOTA!"
			timer_sub_label.modulate = Color(1, 0.5, 0.5, 1)
		else:
			timer_sub_label.text = "TIEMPO TERMINADO"
			timer_sub_label.modulate = Color.GRAY


func _on_timeout_expired() -> void:
	timer_active = false
	if not is_inside_tree():
		return
	timer_label.text = "0"
	if timer_sub_label:
		timer_sub_label.text = "¡TIEMPO TERMINADO!"
		timer_sub_label.modulate = Color.GRAY

	if selected_char_id == -1 and available_char_ids.size() > 0:
		var random_id = available_char_ids[randi() % available_char_ids.size()]
		selected_char_id = random_id
		_selection_locked = true
		LobbyManager.select_character_in_screen(random_id)
		_focus_idx = available_char_ids.find(random_id)
		_layout_cylinder(true)
		print("[CharacterSelect] Jugador AFK. Auto-seleccionado ID: ", random_id)

	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return

	if LobbyManager.is_host:
		_host_resolve_missing_selections()
		MatchCoordinator.host_launch_game()


func _host_resolve_missing_selections() -> void:
	for pid in LobbyManager.players:
		if LobbyManager.players[pid]["character_id"] == -1:
			var role = LobbyManager.players[pid]["assigned_role"]
			var fallback_id := 0
			for data in CharacterRegistry.get_all():
				if data.team == role:
					fallback_id = data.id
					break
			LobbyManager.players[pid]["character_id"] = fallback_id
