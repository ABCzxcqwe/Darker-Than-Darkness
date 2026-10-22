# res://ui/InGameMenu/dev_menu.gd
#
# Menú de herramientas para el HOST en modo dev.
# Solo se instancia desde World cuando DevMode está activo y este peer es el
# servidor con jugador local. No se usa en TEST/RELEASE ni en clientes.
#
# Se abre con L1 + Select. No pausa el mundo; bloquea el input del jugador
# porque se registra en GroupNames.GAME_MENU.
extends Control

const FONT_UID := "uid://dvelfumepo3c0"
const DEV_COLOR := Color(1.0, 0.35, 0.9)
const GOLD := Color(1.0, 0.82, 0.3)
const OK_COLOR := Color(0.55, 1.0, 0.65)
const ERR_COLOR := Color(1.0, 0.45, 0.45)
const STEP := 1.0

const DEV_COMBO_L1 := JOY_BUTTON_LEFT_SHOULDER
const DEV_COMBO_SELECT := JOY_BUTTON_BACK

var _is_open := false
var _player: Node = null
var _host_name := "HOST"
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _font: Font = null

var _overlay: ColorRect = null
var _panel: PanelContainer = null
var _status_label: Label = null
var _target_label: Label = null
var _feedback_label: Label = null
var _host_label: Label = null

# Filas navegables: target, heal, damage, invuln, tp, stamina, time_add, time_sub.
var _rows: Array[Dictionary] = []
var _focus_idx := 0

var _heal_spin: SpinBox = null
var _damage_spin: SpinBox = null
var _invuln_spin: SpinBox = null
var _tp_spin: SpinBox = null
var _stamina_spin: SpinBox = null
var _time_add_spin: SpinBox = null
var _time_sub_spin: SpinBox = null

var _target_ids: Array[int] = []
var _target_idx := 0

var _dev_l1_down := false
var _dev_select_down := false
var _dev_combo_latched := false
var _state_accum := 0.0


func _ready() -> void:
	add_to_group(GroupNames.GAME_MENU)
	add_to_group(GroupNames.DEV_MENU)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_font = load(FONT_UID) as Font
	_build_ui()
	_set_open_visuals(false)
	set_process(false)

	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	LobbyManager.player_joined.connect(_on_roster_changed)
	LobbyManager.player_left.connect(_on_roster_changed)


func setup(player_node: Node) -> void:
	_player = player_node
	var my_id := multiplayer.get_unique_id()
	if LobbyManager.players.has(my_id):
		_host_name = String(LobbyManager.players[my_id].get("name", "HOST"))
	if _host_label:
		_host_label.text = "HOST: " + _host_name
	if _is_open:
		_refresh_targets()


func is_open() -> bool:
	return _is_open


# ── Construcción de UI ────────────────────────────────────────────────

func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.62)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -350.0
	_panel.offset_right = 350.0
	_panel.offset_top = -355.0
	_panel.offset_bottom = 355.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.025, 0.05, 0.98)
	style.border_color = DEV_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(1.0, 0.2, 0.8, 0.25)
	style.shadow_size = 14
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := _make_label("DEV MENU", 26, DEV_COLOR)
	vbox.add_child(title)

	_host_label = _make_label("HOST: HOST", 13, Color(0.7, 0.7, 0.8))
	vbox.add_child(_host_label)

	_status_label = _make_label("HP --/--   TP --/--   STAMINA --/--   TIEMPO --:--", 15, Color.WHITE)
	vbox.add_child(_status_label)

	vbox.add_child(HSeparator.new())

	# ── Objetivo ──
	var target_row := HBoxContainer.new()
	target_row.add_theme_constant_override("separation", 8)
	var target_title := _make_label("OBJETIVO", 16, GOLD)
	target_title.custom_minimum_size = Vector2(190, 0)
	target_row.add_child(target_title)
	_target_label = _make_label("< SIN JUGADORES >", 16, Color.WHITE)
	_target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_row.add_child(_target_label)
	var prev_btn := _make_button("<")
	prev_btn.pressed.connect(func() -> void: _cycle_target(-1))
	target_row.add_child(prev_btn)
	var next_btn := _make_button(">")
	next_btn.pressed.connect(func() -> void: _cycle_target(1))
	target_row.add_child(next_btn)
	vbox.add_child(target_row)
	_rows.append({"kind": "target", "label": target_title, "spin": null})

	vbox.add_child(HSeparator.new())

	# ── Jugador ──
	vbox.add_child(_make_label("JUGADOR", 18, GOLD))
	_heal_spin = _add_number_row(vbox, "Cura", 50.0, _apply_heal)
	_damage_spin = _add_number_row(vbox, "Daño", 25.0, _apply_damage)
	_invuln_spin = _add_number_row(vbox, "Invulnerabilidad (s)", 5.0, _apply_invulnerability)
	_tp_spin = _add_number_row(vbox, "TP (fijar)", 100.0, _apply_tp)
	_stamina_spin = _add_number_row(vbox, "Stamina (fijar)", 100.0, _apply_stamina)

	vbox.add_child(HSeparator.new())

	# ── Tiempo ──
	vbox.add_child(_make_label("TIEMPO", 18, GOLD))
	_time_add_spin = _add_number_row(vbox, "Añadir segundos", 60.0, _apply_time_add)
	_time_sub_spin = _add_number_row(vbox, "Quitar segundos", 60.0, _apply_time_sub)

	_feedback_label = _make_label("", 14, GOLD)
	vbox.add_child(_feedback_label)

	var hint := _make_label(
		"[↑↓] Navegar   [←→] Ajustar / Objetivo   [Enter] Aplicar   [B/Esc] Cerrar",
		13, Color(0.7, 0.7, 0.8))
	vbox.add_child(hint)

	var close_btn := _make_button("CERRAR")
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(_close)
	vbox.add_child(close_btn)


func _add_number_row(parent: VBoxContainer, title: String, default_value: float,
		callback: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := _make_label(title, 16, Color.WHITE)
	label.custom_minimum_size = Vector2(190, 0)
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 99999.0
	spin.step = 1.0
	spin.value = default_value
	spin.custom_minimum_size = Vector2(130, 0)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line := spin.get_line_edit()
	if line and _font:
		line.add_theme_font_override("font", _font)
		line.add_theme_font_size_override("font_size", 16)
	row.add_child(spin)

	var run_apply := func() -> void:
		# Commitear el texto tecleado antes de leer spin.value.
		spin.apply()
		callback.call(spin.value)

	var apply := _make_button("APLICAR")
	apply.pressed.connect(run_apply)
	row.add_child(apply)

	parent.add_child(row)
	_rows.append({
		"kind": "number",
		"label": label,
		"spin": spin,
		"apply": run_apply,
	})
	return spin


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	if _font:
		label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	if _font:
		button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", GOLD)
	return button


# ── Apertura / cierre ─────────────────────────────────────────────────

func _open() -> void:
	if _is_open or not DevMode.is_enabled():
		return
	if MenuUtils.is_any_menu_open(get_tree(), self):
		return
	_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_targets()
	_set_open_visuals(true)
	_focus_idx = 0
	_focus_row()
	_feedback_label.text = ""
	set_process(true)


func _close() -> void:
	if not _is_open:
		return
	_is_open = false
	_set_open_visuals(false)
	if get_viewport():
		get_viewport().gui_release_focus()
	Input.mouse_mode = _prev_mouse_mode
	set_process(false)


func _set_open_visuals(value: bool) -> void:
	_overlay.visible = value
	_panel.visible = value


func _process(delta: float) -> void:
	if not _is_open:
		return
	_state_accum += delta
	if _state_accum >= 0.2:
		_state_accum = 0.0
		_refresh_state()


# ── Input ─────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	var vp := get_viewport()
	if vp == null:
		return

	# Combo L1 + Select (igual que en CharacterSelect).
	if event is InputEventJoypadButton:
		var joy_event := event as InputEventJoypadButton
		if joy_event.button_index == DEV_COMBO_L1:
			_dev_l1_down = joy_event.pressed
		elif joy_event.button_index == DEV_COMBO_SELECT:
			_dev_select_down = joy_event.pressed

		var combo_down := _dev_l1_down and _dev_select_down
		if combo_down:
			if not _dev_combo_latched:
				if _is_open:
					_dev_combo_latched = true
					_close()
					vp.set_input_as_handled()
					return
				elif not MenuUtils.is_any_menu_open(get_tree(), self):
					_dev_combo_latched = true
					_open()
					vp.set_input_as_handled()
					return
		else:
			_dev_combo_latched = false

	if not _is_open:
		return

	if event.is_action_pressed("menu_cancel") or event.is_action_pressed("pause"):
		_close()
		vp.set_input_as_handled()
		return

	if event.is_action_pressed("menu_up"):
		_focus_idx = (_focus_idx - 1 + _rows.size()) % _rows.size()
		_focus_row()
		vp.set_input_as_handled()
		return
	if event.is_action_pressed("menu_down"):
		_focus_idx = (_focus_idx + 1) % _rows.size()
		_focus_row()
		vp.set_input_as_handled()
		return

	if event.is_action_pressed("menu_left") or event.is_action_pressed("menu_right"):
		var direction := -1 if event.is_action_pressed("menu_left") else 1
		var row := _rows[_focus_idx]
		if row.get("kind") == "target":
			_cycle_target(direction)
			vp.set_input_as_handled()
			return
		# Ajuste con mando: no consumimos las flechas del teclado para que el
		# LineEdit del SpinBox pueda mover el cursor al editar.
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			var spin: SpinBox = row.get("spin")
			if spin:
				spin.apply()
				spin.value = maxf(0.0, spin.value + direction * STEP)
				vp.set_input_as_handled()
				return

	if event.is_action_pressed("menu_accept"):
		var row := _rows[_focus_idx]
		if row.get("kind") == "target":
			_refresh_state()
		else:
			var callback: Callable = row.get("apply")
			if callback.is_valid():
				callback.call()
		vp.set_input_as_handled()
		return


func _focus_row() -> void:
	for i in _rows.size():
		var row := _rows[i]
		var label: Label = row.get("label")
		if label:
			label.add_theme_color_override("font_color", DEV_COLOR if i == _focus_idx else Color.WHITE)

	if _focus_idx < 0 or _focus_idx >= _rows.size():
		return

	var row := _rows[_focus_idx]
	var spin: SpinBox = row.get("spin")
	if spin:
		spin.grab_focus()
		var line := spin.get_line_edit()
		if line:
			line.select_all()
	elif get_viewport():
		get_viewport().gui_release_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_reset_dev_combo()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_reset_dev_combo()


func _on_roster_changed(_arg1: Variant = null, _arg2: Variant = null) -> void:
	if _is_open:
		_refresh_targets()


func _reset_dev_combo() -> void:
	_dev_l1_down = false
	_dev_select_down = false
	_dev_combo_latched = false


# ── Objetivo / estado ─────────────────────────────────────────────────

func _refresh_targets() -> void:
	var previous := _selected_peer_id()
	_target_ids.clear()

	for info in LobbyManager.get_player_list():
		if info.get("is_spectator", false):
			continue
		if String(info.get("assigned_role", "")) == "spectator":
			continue
		_target_ids.append(int(info.id))

	_target_ids.sort()

	if _target_ids.is_empty():
		_target_idx = 0
		_target_label.text = "< SIN JUGADORES >"
		_refresh_state()
		return

	var found := _target_ids.find(previous)
	_target_idx = found if found >= 0 else 0
	_update_target_label()
	_refresh_state()


func _update_target_label() -> void:
	var peer := _selected_peer_id()
	if peer <= 0 or not LobbyManager.players.has(peer):
		_target_label.text = "< SIN JUGADORES >"
		return
	var info: Dictionary = LobbyManager.players[peer]
	var role := String(info.get("assigned_role", "survivor")).to_upper()
	_target_label.text = "< %s  [%s] >" % [String(info.get("name", "JUGADOR")), role]


func _cycle_target(direction: int) -> void:
	if _target_ids.is_empty():
		return
	_target_idx = (_target_idx + direction + _target_ids.size()) % _target_ids.size()
	_update_target_label()
	_refresh_state()


func _selected_peer_id() -> int:
	if _target_idx < 0 or _target_idx >= _target_ids.size():
		return -1
	return _target_ids[_target_idx]


func _selected_player() -> Node:
	var peer := _selected_peer_id()
	if peer <= 0:
		return null
	return PlayerRegistry.get_player(peer)


func _selected_character_data() -> CharacterData:
	var peer := _selected_peer_id()
	if peer <= 0:
		return null
	var player := _selected_player()
	if player and "character_data" in player and player.character_data:
		return player.character_data
	if LobbyManager.players.has(peer):
		var char_id := int(LobbyManager.players[peer].get("character_id", -1))
		if char_id > 0:
			return CharacterRegistry.get_character(char_id)
	return null


func _refresh_state() -> void:
	var peer := _selected_peer_id()
	if peer <= 0:
		_status_label.text = "HP --/--   TP --/--   STAMINA --/--   TIEMPO --:--"
		return

	var player := _selected_player()
	var data := _selected_character_data()

	var hp := 0
	if player and "health" in player:
		hp = int(player.health)
	var max_hp := int(data.max_health) if data else 0

	var tp_svc = GameServiceLocator.tp
	var stam_svc = GameServiceLocator.stamina
	var timer_svc = GameServiceLocator.timer

	var tp := int(tp_svc.get_tp_for_peer(peer)) if tp_svc else 0
	var tp_max := int(data.tp_max) if data else 0
	var stamina := int(stam_svc.get_stamina(peer)) if stam_svc else 0
	var stamina_max := int(data.stamina_max) if data else 0

	var time_left := 0.0
	if timer_svc:
		time_left = timer_svc.time_left
	var minutes := int(time_left / 60.0)
	var seconds := int(time_left) % 60

	_status_label.text = "HP %d/%d   TP %d/%d   STAMINA %d/%d   TIEMPO %02d:%02d" % [
		hp, max_hp, tp, tp_max, stamina, stamina_max, minutes, seconds
	]


func _set_feedback(text: String, color: Color = GOLD) -> void:
	_feedback_label.text = text
	_feedback_label.add_theme_color_override("font_color", color)


# ── Acciones ──────────────────────────────────────────────────────────

func _apply_heal(value: float) -> void:
	var player := _selected_player()
	var health = GameServiceLocator.health
	if not player or not health:
		_set_feedback("Objetivo no válido.", ERR_COLOR)
		return
	var peer := _selected_peer_id()
	if health.has_method("is_alive") and not health.is_alive(peer):
		_set_feedback("El objetivo no está vivo.", ERR_COLOR)
		return
	health.heal(player, int(maxf(0.0, value)))
	_set_feedback("Curado %d." % int(maxf(0.0, value)), OK_COLOR)
	_refresh_state()


func _apply_damage(value: float) -> void:
	var player := _selected_player()
	var health = GameServiceLocator.health
	if not player or not health:
		_set_feedback("Objetivo no válido.", ERR_COLOR)
		return
	if "character_data" in player and player.character_data \
			and player.character_data.team == "killer":
		_set_feedback("El daño normal no afecta a killers.", ERR_COLOR)
		return
	health.take_damage(player, int(maxf(0.0, value)), "dev")
	_set_feedback("Daño aplicado: %d." % int(maxf(0.0, value)), OK_COLOR)
	_refresh_state()


func _apply_invulnerability(value: float) -> void:
	var player := _selected_player()
	if not player:
		_set_feedback("Objetivo no válido.", ERR_COLOR)
		return
	var ms := int(maxf(0.0, value) * 1000.0)
	player.rpc("_sync_invincibility", ms)
	_set_feedback("Invulnerabilidad: %d s." % int(maxf(0.0, value)), OK_COLOR)
	_refresh_state()


func _apply_tp(value: float) -> void:
	var peer := _selected_peer_id()
	var tp_svc = GameServiceLocator.tp
	if peer <= 0 or not tp_svc:
		_set_feedback("Objetivo no válido.", ERR_COLOR)
		return
	tp_svc.dev_set_tp(peer, maxf(0.0, value))
	_set_feedback("TP fijado en %d." % int(maxf(0.0, value)), OK_COLOR)
	_refresh_state()


func _apply_stamina(value: float) -> void:
	var peer := _selected_peer_id()
	var stam_svc = GameServiceLocator.stamina
	if peer <= 0 or not stam_svc:
		_set_feedback("Objetivo no válido.", ERR_COLOR)
		return
	stam_svc.dev_set_stamina(peer, maxf(0.0, value))
	_set_feedback("Stamina fijada en %d." % int(maxf(0.0, value)), OK_COLOR)
	_refresh_state()


func _apply_time_add(value: float) -> void:
	var timer_svc = GameServiceLocator.timer
	if not timer_svc:
		_set_feedback("Timer no disponible.", ERR_COLOR)
		return
	timer_svc.modify_time(maxf(0.0, value))
	_set_feedback("Tiempo añadido: %d s." % int(maxf(0.0, value)), OK_COLOR)
	_refresh_state()


func _apply_time_sub(value: float) -> void:
	var timer_svc = GameServiceLocator.timer
	if not timer_svc:
		_set_feedback("Timer no disponible.", ERR_COLOR)
		return
	timer_svc.modify_time(-maxf(0.0, value))
	_set_feedback("Tiempo quitado: %d s." % int(maxf(0.0, value)), OK_COLOR)
	_refresh_state()
