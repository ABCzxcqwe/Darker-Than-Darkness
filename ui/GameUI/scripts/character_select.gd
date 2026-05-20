# res://scenes/CharacterSelect.gd
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

func _ready() -> void:
	# CORRECCIÓN 1: Forzamos la asignación del grupo por código 
	# para asegurar que NetworkManager la encuentre y la borre
	add_to_group("character_select_screen")
	
	# Escuchar actualizaciones de red cuando otros elijan personaje
	NetworkManager.lobby_updated.connect(_on_lobby_updated)
	
	# 1. Determinar nuestro bando local
	var my_id := multiplayer.get_unique_id()
	if NetworkManager.players.has(my_id):
		local_role = NetworkManager.players[my_id]["assigned_role"]
	
	# Estilizar etiqueta de rol al estilo Deltarune (Cian / Asesino)
	if local_role == "killer":
		role_label.text = "ROL: KILLER (CAZADOR)"
		role_label.modulate = Color.MAGENTA
	else:
		role_label.text = "ROL: SURVIVOR (EQUIPO)"
		role_label.modulate = Color.CYAN

	# 2. Escanear y filtrar qué personajes corresponden a nuestro bando
	_build_character_options()
	
	# 3. Dibujar la lista inicial de elecciones en tiempo real
	_on_lobby_updated()
	
	# 4. Iniciar el bucle del temporizador de 30 segundos
	_start_countdown()


## Escanea las carpetas numéricas para saber qué personajes pertenecen a tu bando
func _build_character_options() -> void:
	# Limpiar botones de prueba si existen
	for child in options_container.get_children():
		child.queue_free()
		
	available_char_ids.clear()
	
	# Recorremos los IDs conocidos de tus personajes (0 a 3 por ahora)
	for char_id in range(4):
		var path := "res://Characters/%d/data.tres" % char_id
		if ResourceLoader.exists(path):
			var data := load(path) as CharacterData
			if data and data.team == local_role:
				available_char_ids.append(char_id)
				_create_character_button(char_id, data)


## Instancia un botón interactivo para cada personaje filtrado
func _create_character_button(char_id: int, data: CharacterData) -> void:
	var btn := Button.new()
	btn.text = data.display_name
	btn.custom_minimum_size = Vector2(120, 50)
	
	# Si el recurso tiene un ícono visual asignado en su data.tres, lo aplicamos
	if data.icon:
		btn.icon = data.icon
		btn.expand_icon = true
		
	# Conexión por código al pulsar el botón
	btn.pressed.connect(func(): _on_character_clicked(char_id))
	options_container.add_child(btn)


## Registra la intención de voto o selección del personaje en la red
func _on_character_clicked(char_id: int) -> void:
	if not timer_active: return
	selected_char_id = char_id
	
	# Enviamos la selección corregida a la red
	NetworkManager.select_character_in_screen(char_id)
	
	# FEEDBACK VISUAL: Deshabilitar visualmente los botones para reflejar que ya elegiste
	# o marcar cuál está seleccionado.
	for child in options_container.get_children():
		if child is Button:
			# Si quieres que solo sepa cuál presionó, puedes modular su color:
			if child.get_index() == available_char_ids.find(char_id):
				child.modulate = Color.GREEN # Se vuelve verde al seleccionarlo
			else:
				child.modulate = Color.WHITE


## Se dispara cada vez que un peer cambia su personaje
func _on_lobby_updated() -> void:
	selections_list.clear()
	
	for p in NetworkManager.get_player_list():
		var text = p.name
		if p.id == multiplayer.get_unique_id():
			text += " (Tú)"
			
		# Traducir ID a nombre legible en pantalla
		var char_name = "Eligiendo..."
		if p.character_id != -1:
			char_name = _get_char_name_by_id(p.character_id)
			
		text += " -> " + char_name + " [" + p.assigned_role.to_upper() + "]"
		selections_list.add_item(text)


## Temporizador asíncrono controlado de 30 segundos
func _start_countdown() -> void:
	while time_left > 0 and timer_active:
		timer_label.text = "Tiempo restante: %d" % time_left
		await get_tree().create_timer(1.0).timeout
		time_left -= 1
		
	if timer_active:
		_on_timeout_expired()


## Ejecutado automáticamente cuando el contador toca cero
func _on_timeout_expired() -> void:
	timer_active = false
	timer_label.text = "¡Tiempo Terminado!"
	
	# BLOQUEO AFK: Si el jugador no eligió nada, forzamos uno al azar de su lista filtrada
	if selected_char_id == -1 and available_char_ids.size() > 0:
		var random_id = available_char_ids[randi() % available_char_ids.size()]
		selected_char_id = random_id
		NetworkManager.select_character_in_screen(random_id)
		print("[CharacterSelect] Jugador AFK. Auto-seleccionado ID: ", random_id)

	# Esperamos un pequeño frame de holgura para que todos los RPCs impacten en el Servidor
	await get_tree().create_timer(1.5).timeout
	
	# El Host es el único encargado de recolectar el dict definitivo y lanzar las escenas de combate
	if NetworkManager.is_host:
		# Si algún jugador por lag extremo se quedó en -1 en el servidor, el host le asigna un azar de emergencia
		_host_resolve_missing_selections()
		NetworkManager.host_launch_game()


## Verificación final de seguridad del Host antes de instanciar el mapa
func _host_resolve_missing_selections() -> void:
	for pid in NetworkManager.players:
		if NetworkManager.players[pid]["character_id"] == -1:
			var role = NetworkManager.players[pid]["assigned_role"]
			# Fallback rápido: 0 (Kris) para survivor, 3 (Jevil) para killer
			NetworkManager.players[pid]["character_id"] = 3 if role == "killer" else 0


func _get_char_name_by_id(id: int) -> String:
	match id:
		0: return "Kris"
		1: return "Susie"
		2: return "Ralsei"
		3: return "Jevil"
		_: return "Desconocido"
