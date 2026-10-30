# res://ui/GameUI/scripts/match_stats.gd
# Overlay mínimo de fin de partida: resultado + botón para volver al lobby/hub.
# Cualquier jugador puede cerrarlo (no es exclusivo del host).
extends Control

const FONT := preload("res://Fonts/deltarune font.ttf")

@onready var title_label: Label = $Label
@onready var result_label: Label = $ResultLabel
@onready var host_status_label: Label = $HostStatusLabel
@onready var reset_room_button: Button = $ResetRoomButton

var _closing := false
var _retry_timer: Timer = null


func _ready() -> void:
	_record_theme_progress()
	_setup_texts()
	_setup_result()
	_setup_players_list()
	_setup_close_button()


## Devuelve la traducción si existe; si el CSV todavía no se reimportó,
## muestra un texto legible en vez de la clave cruda.
func _tr_or(key: String, fallback: String) -> String:
	var value := tr(key)
	return value if value != key else fallback


func _setup_texts() -> void:
	if title_label:
		title_label.text = _tr_or("HUD_END_TITLE", "RESULTADOS")
	if host_status_label:
		host_status_label.text = _tr_or("HUD_END_FINISHED", "PARTIDA FINALIZADA")


func _setup_result() -> void:
	var results: Dictionary = MatchCoordinator.last_match_results

	var reason_code: String = ""
	var winner_team: String = ""

	if typeof(results) == TYPE_DICTIONARY and not results.is_empty():
		reason_code = str(results.get("end_reason", results.get("reason", "")))
		winner_team = str(results.get("winner", ""))

	if reason_code == "killer_disconnected":
		result_label.text = tr("HUD_END_KILLER_LEFT")
		result_label.modulate = Color.CYAN
	elif winner_team == "killer" or reason_code == "killer_elimination":
		result_label.text = tr("HUD_END_KILLER_WIN")
		result_label.modulate = Color.MAGENTA
	elif reason_code == "survivors_escaped":
		var escaped: int = int(results.get("escaped_count", 0))
		var total: int = int(results.get("total_survivors", 0))
		var not_escaped: int = total - escaped
		if escaped > 0:
			result_label.text = tr("HUD_END_SURV_ESCAPED") % [escaped, not_escaped]
		else:
			result_label.text = tr("HUD_END_SURV_TIME")
		result_label.modulate = Color.CYAN
	else:
		result_label.text = tr("HUD_END_OVER")
		result_label.modulate = Color.YELLOW

	result_label.add_theme_font_size_override("font_size", 28)
	# Dejar espacio para la lista de jugadores debajo del resultado.
	result_label.anchor_top = 0.21
	result_label.anchor_bottom = 0.31


func _setup_players_list() -> void:
	var results: Dictionary = MatchCoordinator.last_match_results
	if typeof(results) != TYPE_DICTIONARY:
		results = {}
	var snapshot: Dictionary = results.get("players_snapshot", {})
	if snapshot.is_empty():
		snapshot = LobbyManager.players
	if snapshot.is_empty():
		return

	var panel := PanelContainer.new()
	panel.name = "PlayersPanel"
	panel.anchor_left = 0.18
	panel.anchor_top = 0.34
	panel.anchor_right = 0.82
	panel.anchor_bottom = 0.72
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.03, 0.88)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.9, 0.5, 0.55)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 18.0
	style.content_margin_top = 12.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var list := VBoxContainer.new()
	list.name = "PlayersList"
	list.add_theme_constant_override("separation", 7)
	panel.add_child(list)

	var header := Label.new()
	header.text = _tr_or("HUD_END_PLAYERS", "JUGADORES")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_override("font", FONT)
	header.add_theme_font_size_override("font_size", 18)
	list.add_child(header)

	var reason := str(results.get("end_reason", results.get("reason", "")))
	var winner_team := str(results.get("winner", ""))
	var my_id := multiplayer.get_unique_id()
	var ids: Array = snapshot.keys()
	ids.sort()

	for raw_id in ids:
		var pid := int(raw_id)
		var entry = snapshot[raw_id]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var role := str(entry.get("assigned_role", "survivor")).to_lower()
		var p_name := str(entry.get("name", "P%d" % pid))
		if pid == my_id:
			p_name += " " + _tr_or("HUD_END_YOU", "(TÚ)")

		var char_name := "?"
		var char_id := int(entry.get("character_id", -1))
		if char_id > 0 and CharacterRegistry.has_character(char_id):
			var cd := CharacterRegistry.get_character(char_id)
			if cd:
				char_name = cd.display_name

		var won := false
		if reason == "killer_disconnected":
			won = role == "survivor"
		elif winner_team == "killer" or reason == "killer_elimination":
			won = role == "killer"
		elif reason == "survivors_escaped":
			won = role == "survivor"
		elif winner_team != "":
			won = winner_team == role

		var result_text := _tr_or("HUD_END_SPECTATOR", "ESPECTADOR")
		var result_color := Color(0.7, 0.7, 0.7, 1.0)
		if role == "survivor" or role == "killer":
			result_text = _tr_or("HUD_END_WON", "GANÓ") if won else _tr_or("HUD_END_LOST", "PERDIÓ")
			result_color = Color(0.35, 1.0, 0.55, 1.0) if won else Color(1.0, 0.4, 0.4, 1.0)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var name_lbl := Label.new()
		name_lbl.text = p_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_override("font", FONT)
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		row.add_child(name_lbl)

		var role_lbl := Label.new()
		role_lbl.text = role.to_upper()
		role_lbl.custom_minimum_size = Vector2(100, 0)
		role_lbl.add_theme_font_override("font", FONT)
		role_lbl.add_theme_font_size_override("font_size", 15)
		var role_color := Color(0.72, 0.72, 0.72, 1.0)
		if role == "survivor":
			role_color = Color(0.3, 0.85, 1.0, 1.0)
		elif role == "killer":
			role_color = Color(1.0, 0.35, 0.8, 1.0)
		role_lbl.add_theme_color_override("font_color", role_color)
		row.add_child(role_lbl)

		var char_lbl := Label.new()
		char_lbl.text = char_name
		char_lbl.custom_minimum_size = Vector2(140, 0)
		char_lbl.add_theme_font_override("font", FONT)
		char_lbl.add_theme_font_size_override("font_size", 15)
		char_lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72, 1.0))
		row.add_child(char_lbl)

		var result_lbl := Label.new()
		result_lbl.text = result_text
		result_lbl.custom_minimum_size = Vector2(90, 0)
		result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		result_lbl.add_theme_font_override("font", FONT)
		result_lbl.add_theme_font_size_override("font_size", 15)
		result_lbl.add_theme_color_override("font_color", result_color)
		row.add_child(result_lbl)

		list.add_child(row)


func _setup_close_button() -> void:
	reset_room_button.visible = true
	reset_room_button.disabled = false
	reset_room_button.text = _tr_or("HUD_END_BACK_HUB", "VOLVER AL HUB [Z]")
	reset_room_button.add_theme_font_size_override("font_size", 18)
	if not reset_room_button.pressed.is_connected(_on_close_pressed):
		reset_room_button.pressed.connect(_on_close_pressed)
	reset_room_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return

	var accept: bool = event.is_action_pressed("menu_accept") \
			or event.is_action_pressed("ui_accept") \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_Z)
	var cancel: bool = event.is_action_pressed("menu_cancel") \
			or event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_X)

	if accept or cancel:
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()
		_on_close_pressed()


func _on_close_pressed() -> void:
	if _closing:
		return
	_closing = true
	reset_room_button.disabled = true
	reset_room_button.text = _tr_or("HUD_END_RETURNING", "VOLVIENDO...")

	# Timer hijo: si la escena se libera por el cambio al hub, el timer muere
	# con ella. Si el servidor no responde, permite reintentar.
	if _retry_timer == null:
		_retry_timer = Timer.new()
		_retry_timer.one_shot = true
		_retry_timer.wait_time = 3.0
		_retry_timer.timeout.connect(_on_return_timeout)
		add_child(_retry_timer)
	_retry_timer.start()

	MatchCoordinator.request_return_to_lobby()


func _on_return_timeout() -> void:
	if not is_inside_tree():
		return
	_closing = false
	reset_room_button.disabled = false
	reset_room_button.text = _tr_or("HUD_END_BACK_HUB", "VOLVER AL HUB [Z]")


func _record_theme_progress() -> void:
	# Cada cliente registra si él ganó con su personaje (local). Si no hay snapshot, no hace nada.
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null or not sm.has_method("record_win_for_character"):
		return
	var results: Dictionary = MatchCoordinator.last_match_results
	if results.is_empty():
		return
	var my_id := multiplayer.get_unique_id()
	# Snapshot autoritativo (players_snapshot) propagado en _go_to_stats
	var snapshot: Dictionary = results.get("players_snapshot", {})
	if snapshot.is_empty():
		snapshot = LobbyManager.players
	if not snapshot.has(my_id):
		return
	var my_entry: Dictionary = snapshot[my_id] as Dictionary
	var my_role: String = str(my_entry.get("assigned_role", ""))
	var my_char: int = int(my_entry.get("character_id", -1))
	if my_char <= 0:
		return
	var reason: String = str(results.get("end_reason", results.get("reason", "")))
	var winner: String = str(results.get("winner", ""))
	var i_won := false
	if reason == "killer_disconnected":
		i_won = my_role == "survivor"
	elif winner == "killer" or reason == "killer_elimination":
		i_won = my_role == "killer"
	elif reason == "survivors_escaped":
		# Se mantiene el comportamiento actual: los survivors cuentan como ganadores.
		i_won = my_role == "survivor"
	else:
		if winner != "":
			i_won = winner == my_role
	if i_won:
		var was_unlocked: bool = sm.is_theme_unlocked("light")
		sm.record_win_for_character(my_char)
		if not was_unlocked and sm.is_theme_unlocked("light"):
			# Notificación: se auto-activa vía SettingsManager.unlock_theme -> menu_theme
			print("[MatchStats] ¡Tema LIGHT desbloqueado! Tema auto-activado.")
