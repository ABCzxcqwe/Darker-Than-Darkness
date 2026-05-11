extends Control

@onready var player_name_input = $MarginContainer/VBoxContainer/PlayerNameInput
@onready var ip_input = $MarginContainer/VBoxContainer/IPInput
@onready var join_btn = $MarginContainer/VBoxContainer/JoinButton
@onready var back_btn = $MarginContainer/VBoxContainer/BackButton
@onready var status_label = $MarginContainer/VBoxContainer/StatusLabel

func _ready():
	# Conectar señales de red (solo una vez)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	
	ip_input.text = "127.0.0.1"
	status_label.text = ""

func _on_join_pressed():
	var _name = player_name_input.text.strip_edges()
	var ip = ip_input.text.strip_edges()
	if NetworkManager.join_server(_name, ip):
		# Ya no conectamos _goto_lobby aquí; la señal ya está conectada
		status_label.text = "Conectando..."
		join_btn.disabled = true
	else:
		status_label.text = "Error de conexión"

func _on_connection_succeeded():
	print("Conexión exitosa, cambiando a lobby...")
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/Lobby.tscn")

func _on_connection_failed():
	status_label.text = "Error: No se pudo conectar al servidor"
	join_btn.disabled = false
	back_btn.disabled = false

func _on_server_disconnected():
	status_label.text = "El servidor se desconectó"
	join_btn.disabled = false
	back_btn.disabled = false

func _on_back_pressed():
	NetworkManager.disconnect_from_server()
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")

func _exit_tree():
	# Limpiar conexiones
	if NetworkManager.connection_succeeded.is_connected(_on_connection_succeeded):
		NetworkManager.connection_succeeded.disconnect(_on_connection_succeeded)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	if NetworkManager.server_disconnected.is_connected(_on_server_disconnected):
		NetworkManager.server_disconnected.disconnect(_on_server_disconnected)
