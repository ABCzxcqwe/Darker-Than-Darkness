# res://ui/GameUI/scripts/match_stats.gd
# Overlay mínimo de fin de partida: resultado + botón para volver al lobby/hub.
# Cualquier jugador puede cerrarlo (no es exclusivo del host).
extends Control

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
