# res://scenes/MatchStats.gd
extends Control

@onready var result_label: Label = $ResultLabel
@onready var host_status_label: Label = $HostStatusLabel
@onready var reset_room_button: Button = $ResetRoomButton

func _ready() -> void:
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
		result_label.text = "¡VICTORIA DEL KILLER!\nTodos los supervivientes fueron eliminados."
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
	if NetworkManager.is_host:
		host_status_label.text = "Eres el Host. Reconfigura la sala cuando estés listo."
		reset_room_button.visible = true
		reset_room_button.text = "Crear nueva sala (Volver al Lobby)"
		if not reset_room_button.pressed.is_connected(_on_reset_room_pressed):
			reset_room_button.pressed.connect(_on_reset_room_pressed)
	else:
		host_status_label.text = "Esperando a que el host cree una nueva sala..."
		reset_room_button.visible = false


func _on_reset_room_pressed() -> void:
	MatchCoordinator.host_return_to_lobby_reconfigured()
