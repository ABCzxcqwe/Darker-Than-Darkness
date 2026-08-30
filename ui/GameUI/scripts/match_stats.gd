# res://scenes/MatchStats.gd
extends Control

@onready var result_label: Label = $ResultLabel
@onready var host_status_label: Label = $HostStatusLabel
@onready var reset_room_button: Button = $ResetRoomButton

func _ready() -> void:
	_record_theme_progress()
	# 1. Obtener resultados de red de forma segura
	var results: Dictionary = MatchCoordinator.last_match_results
	
	# Inicializamos variables por defecto por si el diccionario viene corrupto o vacío
	var reason_code: String = ""
	var winner_team: String = ""
	
	# Extraemos los datos usando .get() SOLAMENTE si results no es nulo y tiene datos
	if typeof(results) == TYPE_DICTIONARY and not results.is_empty():
		reason_code = results.get("end_reason", results.get("reason", ""))
		winner_team = results.get("winner", "")

	# 2. EVALUACIÓN DEFENSIVA (Si no encuentra claves, no crashea)
	if reason_code == "killer_disconnected":
		result_label.text = "¡LOS SURVIVORS GANAN!\nEl Killer abandonó la partida."
		result_label.modulate = Color.CYAN
	elif winner_team == "killer" or reason_code == "killer_elimination":
		result_label.text = "¡VICTORIA DEL KILLER!\nEl tiempo se agotó. Nadie logró escapar."
		result_label.modulate = Color.MAGENTA
	elif reason_code == "survivors_escaped":
		var escaped = results.get("escaped_count", 0)
		var total = results.get("total_survivors", 0)
		var not_escaped = total - escaped
		if escaped > 0:
			result_label.text = "¡LOS SURVIVORS GANAN!\n%d escaparon, %d no lo lograron." % [escaped, not_escaped]
		else:
			result_label.text = "¡LOS SURVIVORS GANAN!\nEl tiempo se acabó antes del rescate."
		result_label.modulate = Color.CYAN
	else:
		# Fallback por si el cliente se desconectó de golpe y el diccionario se rompió
		result_label.text = "Partida concluida.\nUn jugador abandonó el juego."
		result_label.modulate = Color.YELLOW

	# 3. Configuración asimétrica de la UI de cierre
	if LobbyManager.is_host:
		host_status_label.text = "Eres el Host. Reconfigura la sala cuando estés listo."
		reset_room_button.visible = true
		reset_room_button.text = "Crear nueva sala (Volver al Lobby)"
		if not reset_room_button.pressed.is_connected(_on_reset_room_pressed):
			reset_room_button.pressed.connect(_on_reset_room_pressed)
	else:
		host_status_label.text = "Esperando a que el host cree una nueva sala..."
		reset_room_button.visible = false


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
		# Solo survivors que escaparon o siguen vivos cuentan; simplificado: survivors vivos ganan
		if my_role == "survivor":
			# Si tenemos coord, verificar escape, sino asumir vivo = ganancia
			var hes := get_node_or_null("/root/GameServiceLocator")
			i_won = true
			# Refinar si MapEventCoordinator disponible (opcional)
			var mec = get_node_or_null("/root/MatchCoordinator")
			if mec != null:
				# no bloquear si no hay info, mantener true para survivors_escaped
				pass
	else:
		# Fallback winner team
		if winner != "":
			i_won = winner == my_role
	if i_won:
		var was_unlocked: bool = sm.is_theme_unlocked("light")
		sm.record_win_for_character(my_char)
		if not was_unlocked and sm.is_theme_unlocked("light"):
			# Notificación: se auto-activa vía SettingsManager.unlock_theme -> menu_theme
			print("[MatchStats] ¡Tema LIGHT desbloqueado! Tema auto-activado.")

func _on_reset_room_pressed() -> void:
	MatchCoordinator.host_return_to_lobby_reconfigured()
