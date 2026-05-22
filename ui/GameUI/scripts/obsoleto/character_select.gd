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
	
	# 1. Determinar nuestro bando local (Fuente de verdad unificada)
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
## Escanea el CharacterRegistry central en lugar de buscar carpetas en el disco
func _build_character_options() -> void:
	# Limpiar botones de prueba si existen
	for child in options_container.get_children():
		child.queue_free()
		
	available_char_ids.clear()
	
	print("[CharacterSelect] Cargando opciones desde CharacterRegistry para el rol: ", local_role)
	
	# Recorremos los IDs (0 a 3) preguntándole directamente a tu base de datos central
	for char_id in range(4):
		var data: CharacterData = null
		
		# Opción A: Si CharacterRegistry es un Autoload (Singleton) con un método get_character o similar
		if typeof(CharacterRegistry) == TYPE_OBJECT and CharacterRegistry.has_method("get_character_data"):
			data = CharacterRegistry.get_character_data(char_id) as CharacterData
		# Opción B: Si se accede a través de tu diccionario/array interno de personajes
		elif typeof(CharacterRegistry) == TYPE_OBJECT and "characters" in CharacterRegistry:
			if CharacterRegistry.characters.has(char_id):
				data = CharacterRegistry.characters[char_id] as CharacterData
		# Opción C: Si usas tu ServiceLocator (como con HealthService o GameStateService)
		else:
			var registry_svc = GameServiceLocator.get_service("CharacterRegistry")
			if registry_svc and registry_svc.has_method("get_character_data"):
				data = registry_svc.get_character_data(char_id) as CharacterData
		
		# Si logramos extraer la información del personaje desde la base de datos única:
		if data:
			# Tolerancia para el bando (team o assigned_role)
			var char_team: String = ""
			if "assigned_role" in data:
				char_team = data.assigned_role
			elif "team" in data:
				char_team = data.team
				
			# Comparamos contra el rol asignado en el lobby
			if char_team.to_lower().strip_edges() == local_role.to_lower().strip_edges():
				print("[CharacterSelect] Personaje viable detectado: ID %d (%s)" % [char_id, data.display_name])
				available_char_ids.append(char_id)
				_create_character_button(char_id, data)
		else:
			push_error("[CharacterSelect] No se pudo obtener la data para el ID %d desde el CharacterRegistry." % char_id)

	print("[CharacterSelect] Inicialización de botones completa. Total: ", available_char_ids.size())


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
			
		# Corregido de forma segura para usar p.assigned_role directamente
		var display_role = p.get("assigned_role", "survivor").to_upper()
		text += " -> " + char_name + " [" + display_role + "]"
		selections_list.add_item(text)


## Temporizador asíncrono controlado de 10 segundos (puedes subirlo a 30 si gustas)
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
	
	# BLOQUEO AFK: Si el jugador no elegió nada, forzamos uno al azar de su lista filtrada
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
			# Fallback seguro ajustado a tu roster: Jevil (3) para killer, Kris (0) para survivor
			NetworkManager.players[pid]["character_id"] = 3 if role == "killer" else 0


func _get_char_name_by_id(id: int) -> String:
	match id:
		0: return "Kris"
		1: return "Susie"
		2: return "Ralsei"
		3: return "Jevil"
		_: return "Desconocido"
