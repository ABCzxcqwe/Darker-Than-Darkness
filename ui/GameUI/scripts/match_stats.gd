# res://scenes/MatchStats.gd
extends Control

@onready var result_label: Label = $ResultLabel
@onready var host_status_label: Label = $HostStatusLabel
@onready var reset_room_button: Button = $ResetRoomButton

func _ready() -> void:
	var results = NetworkManager.last_match_results
	if not results.is_empty():
		if results["reason"] == "killer_disconnected":
			result_label.text = "¡LOS SURVIVORS GANAN!\nEl Killer abandonó la partida."
			result_label.modulate = Color.CYAN
		elif results["winner"] == "killer":
			result_label.text = "¡VICTORIA DEL KILLER!\nTodos los supervivientes fueron eliminados."
			result_label.modulate = Color.MAGENTA
		else:
			result_label.text = "¡LOS SURVIVORS ESCAPARON!\nSe terminó el tiempo de caza."
			result_label.modulate = Color.CYAN
	else:
		result_label.text = "Partida concluida."

	# 2. Configuración asimétrica de la UI de cierre
	if NetworkManager.is_host:
		host_status_label.text = "Eres el Host. Reconfigura la sala cuando estés listo."
		reset_room_button.visible = true
		reset_room_button.text = "Crear nueva sala (Volver al Lobby)"
		reset_room_button.pressed.connect(_on_reset_room_pressed)
	else:
		host_status_label.text = "Esperando a que el host cree una nueva sala..."
		reset_room_button.visible = false


func _on_reset_room_pressed() -> void:
	# El host da la orden en red de reiniciar el ciclo del lobby
	NetworkManager.host_return_to_lobby_reconfigured()
