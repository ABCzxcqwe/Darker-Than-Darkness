# res://Maps/world.gd
extends Node2D

const GAME_HUD_SCENE := preload("uid://cvjakwoxx54w4")

@export var services_config: GameServicesConfig = null

@onready var map_container: Node2D = $MapContainer

var _hud: CanvasLayer = null
var current_map_node: BaseMap = null

func _ready() -> void:
	if not services_config:
		push_error("[World] No hay services_config asignado.")
		return

	# 1. Registrar todos los servicios en el localizador
	GameServiceLocator.register_all(services_config)
	
	# ─── AQUÍ ESTÁ LA CORRECCIÓN CRÍTICA ───
	# Le avisamos al GameStateService que la partida está activa en este instante
	# para evitar que AbilityRouter bloquee y desconecte el juego.
	var game_state = GameServiceLocator.get_service("GameStateService")
	if game_state:
		game_state.is_match_active = true 
		print("[World] GameStateService configurado: Partida marcada como ACTIVA.")
	else:
		push_warning("[World] GameStateService no disponible en el inicializador.")
	# ───────────────────────────────────────
	
	# Cambiamos esto: hacemos un await aquí para que NO continúe 
	# hasta que el mapa esté completamente cargado y listo.
	await _load_map()

	# Si somos el servidor, posicionamos a los personajes en sus respectivos spawns
	if multiplayer.is_server():
		# Esperamos un frame adicional para dar tiempo a que los nodos del Spawner se estabilicen
		await get_tree().process_frame
		_position_players_in_spawns()

	await get_tree().process_frame
	await get_tree().process_frame
	_setup_hud()

	if multiplayer.is_server():
		var tp := GameServiceLocator.get_service("TPService")
		if tp:
			tp.start_passive_gain()
		else:
			push_warning("[World] TPService no disponible — ganancia pasiva no iniciada.")
	
	print("[World] Mapa 'Test Map' cargado e inicializado correctamente.")
	# REGLA DE ORO MULTIPLAYER: Solo el servidor despacha la orden global
	if multiplayer.is_server():
		rpc("_sync_start_match_audio", GameData.selected_map)

func _load_map():
	var map_id: String = GameData.selected_map
	if map_id == "":
		push_warning("[World] GameData.selected_map está vacío — no se cargará ningún mapa.")
		return

	var map_data: MapData = MapRegistry.get_map(map_id)
	if not map_data:
		push_error("[World] No se encontró MapData para id '", map_id, "'")
		return

	if not map_data.map_scene:
		push_error("[World] MapData '", map_id, "' no tiene map_scene asignada.")
		return

	var map_instance := map_data.map_scene.instantiate()
	map_container.add_child(map_instance)
	
	# Guardamos la referencia
	current_map_node = map_instance as BaseMap
	
	# ¡LA CLAVE!: Si el mapa aún no está listo en el árbol, esperamos a que su señal 'ready' se emita.
	# Esto garantiza que todos sus @onready e hijos internos existan antes de que _ready() en World continúe.
	if not map_instance.is_node_ready():
		await map_instance.ready

	print("[World] Mapa '", map_data.display_name, "' cargado e inicializado correctamente.")


## NUEVA FUNCIÓN: Distribuye los personajes según el bando de su CharacterData
func _position_players_in_spawns() -> void:
	if not current_map_node:
		push_error("[World] Imposible posicionar jugadores: No hay un mapa válido cargado.")
		return

	# Buscamos a todos los nodos de jugador que el Spawner ya colgó en la escena
	# Nota: Ajusta la ruta si tus jugadores se spawnean bajo un contenedor específico (ej. $Players)
	for player_node in get_tree().get_nodes_in_group("players"):
		# Esperamos a que la lógica diferida de 'set_character' termine para asegurar que 'character_data' exista
		if player_node.has_method("get_character_data") or "character_data" in player_node:
			# Si el personaje aún no se asignó en este frame, esperamos al siguiente
			if player_node.character_data == null:
				await get_tree().process_frame
			
			var data: CharacterData = player_node.character_data
			if data:
				var target_position := Vector2.ZERO
				
				# Separación asimétrica en base al bando definido en el recurso data.tres del personaje
				if data.team == "killer":
					target_position = current_map_node.get_random_killer_spawn()
					print("[World] Posicionando Killer (Peer: ", player_node.name, ") en: ", target_position)
				else:
					target_position = current_map_node.get_random_survivor_spawn()
					print("[World] Posicionando Survivor (Peer: ", player_node.name, ") en: ", target_position)
				
				# Asignamos la posición en el servidor; MultiplayerSynchronizer se encargará de replicarlo a los clientes
				player_node.global_position = target_position


func _setup_hud() -> void:
	var my_peer_id := multiplayer.get_unique_id()
	var my_player: Node = null

	# Esperar hasta 2s a que el nodo del jugador local aparezca en el árbol
	var timeout := 2.0
	var elapsed := 0.0
	while not my_player and elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		my_player = get_tree().root.find_child(str(my_peer_id), true, false)

	if not my_player:
		push_warning("[World] No se encontró el nodo del jugador local tras esperar.")
		return

	# Esperar a que character_data esté asignado — en clientes puede llegar
	# uno o dos frames después de que el nodo aparece en el árbol
	var cd_elapsed := 0.0
	while (not "character_data" in my_player or my_player.character_data == null) \
			and cd_elapsed < 1.0:
		await get_tree().process_frame
		cd_elapsed += get_process_delta_time()

	if not "character_data" in my_player or my_player.character_data == null:
		push_warning("[World] character_data nunca llegó al jugador local.")
		return

	_hud = GAME_HUD_SCENE.instantiate()
	add_child(_hud)
	_hud.setup(my_player)


func _exit_tree() -> void:
	GameServiceLocator.clear()

@rpc("authority", "call_local", "reliable") 
func _sync_start_match_audio(map_id: String) -> void: 
	# 1. El AudioManager local configura la pista ambiental del mapa base 
	AudioManager.setup_map_audio(map_id) 
	# 2. Buscamos los roles de los peers usando el grupo global de jugadores
	var killer_node: Node2D = null 
	var any_survivor_node: Node2D = null 
	for p in get_tree().get_nodes_in_group("players"):
		if "character_data" in p and p.character_data:
			if p.character_data.team == "killer": 
				killer_node = p 
			elif any_survivor_node == null: 
				any_survivor_node = p
	# 3. Extraemos los streams directamente y los pasamos al AudioManager 
	var terror_stream: AudioStream = killer_node.character_data.terror_music if killer_node else null 
	var chase_stream: AudioStream  = killer_node.character_data.chase_music  if killer_node else null
	var lms_stream: AudioStream    = any_survivor_node.character_data.lms_music if any_survivor_node else null
	AudioManager.register_match_character_music(terror_stream, chase_stream, lms_stream)
