# res://Maps/world.gd
extends Node2D

const GAME_HUD_SCENE := preload("uid://cvjakwoxx54w4")
const GAME_HUD_MOCK_SCENE := preload("res://ui/GameUI/Mock/GameHUDMock.tscn")
const PLAYER_SCENE := preload("uid://djw510qiudh6e")
const USE_MOCK_HUD := true

@export var services_config: GameServicesConfig = null

@onready var map_container: Node2D = $MapContainer

var _hud: CanvasLayer = null
var current_map_node: BaseMap = null

func _ready() -> void:
	if not services_config:
		push_error("[World] No hay services_config asignado.")
		return

	GameServiceLocator.register_all(services_config)

	await _load_map()

	# Inicializar eventos del mapa (coordinador)
	var coordinator = GameServiceLocator.map_event_coordinator
	if coordinator and coordinator.has_method("setup") and current_map_node:
		coordinator.setup(current_map_node)

	# Spawn determinista local: cada peer crea los nodos de jugador desde el
	# roster. Sin MultiplayerSpawner el Synchronizer sincroniza por ruta.
	var player_characters: Dictionary = get_meta("player_characters", {})
	_spawn_players_locally(player_characters)

	if multiplayer.is_server():
		await get_tree().process_frame
		_position_players_in_spawns()
		# El servidor otorga visibilidad (incluidos sus propios nodos) recién
		# cuando ya existen y están posicionados.
		_grant_all_visibility_to(multiplayer.get_unique_id())
	else:
		# Avisamos al servidor que nuestros nodos ya existen para que habilite la
		# visibilidad de los Synchronizer hacia nosotros (evita mandar antes de
		# que el nodo exista y perder el estado inicial).
		rpc_id(1, "_peer_world_ready")

	await get_tree().process_frame
	await get_tree().process_frame
	_setup_hud()

	if multiplayer.is_server():
		var tp = GameServiceLocator.tp
		if tp:
			tp.start_passive_gain()
		else:
			push_warning("[World] TPService no disponible — ganancia pasiva no iniciada.")
	
	print("[World] Mapa cargado e inicializado correctamente.")

	var game_state = GameServiceLocator.game_state
	if game_state:
		game_state.transition_to_playing()

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


## Instancia todos los jugadores del roster localmente en este peer.
## Sin MultiplayerSpawner, el Synchronizer sincroniza por ruta, así que los
## peers que entran tarde también reciben el delta continuo.
func _spawn_players_locally(player_characters: Dictionary) -> void:
	for peer_id in player_characters:
		_spawn_player_node(int(peer_id), int(player_characters[peer_id]))


func _spawn_player_node(peer_id: int, char_id: int) -> void:
	var node_name := str(peer_id)
	if has_node(node_name):
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = node_name
	player.set_multiplayer_authority(peer_id)
	player.set_character(char_id)
	add_child(player)
	print("[World] Jugador spawneado localmente: peer ", peer_id, " (char: ", char_id, ")")


## Un peer avisa que ya creó sus nodos de jugador. En ese momento el servidor
## habilita la visibilidad del Synchronizer (autoridad del servidor) hacia ese
## peer, forzando el estado inicial y habilitando el delta continuo.
@rpc("any_peer", "reliable")
func _peer_world_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_grant_all_visibility_to(sender)
	# Late-join: si es espectador, mandarle el estado de audio completo
	# (mapa + personajes + track prioritario/LMS con su posicion actual).
	var player_characters: Dictionary = get_meta("player_characters", {})
	if not player_characters.has(sender):
		var data: Dictionary = AudioManager.get_priority_sync_data()
		var relay := GameServiceLocator.get_client_relay()
		if relay:
			relay.rpc_id(sender, "_rpc_sync_spectator_audio", GameData.selected_map,
				data["priority"], data["position"], data["lms_peer"])
	print("[World] Peer ", sender, " confirmó World listo; visibilidad de Synchronizer habilitada.")


func _grant_all_visibility_to(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for player_node in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if not is_instance_valid(player_node):
			continue
		PlayerLifecycleManager.grant_player_visibility_to_peer(player_node, peer_id)


## NUEVA FUNCIÓN: Distribuye los personajes según el bando de su CharacterData
func _position_players_in_spawns() -> void:
	if not current_map_node:
		push_error("[World] Imposible posicionar jugadores: No hay un mapa válido cargado.")
		return

	# Buscamos a todos los nodos de jugador que el Spawner ya colgó en la escena
	# Nota: Ajusta la ruta si tus jugadores se spawnean bajo un contenedor específico (ej. $Players)
	for player_node in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if player_node.has_method("get_character_data") or "character_data" in player_node:
			if player_node.character_data == null:
				await get_tree().process_frame
			
			var data: CharacterData = player_node.character_data
			if data:
				var target_position := Vector2.ZERO
				
				if data.team == "killer":
					target_position = current_map_node.get_random_killer_spawn()
					print("[World] Posicionando Killer (Peer: ", player_node.name, ") en: ", target_position)
				else:
					target_position = current_map_node.get_random_survivor_spawn()
					print("[World] Posicionando Survivor (Peer: ", player_node.name, ") en: ", target_position)
				
				# Asignamos la posición en el servidor; MultiplayerSynchronizer se encargará de replicarlo a los clientes
				player_node.global_position = target_position
				player_node.net_position = target_position


func _setup_hud() -> void:
	var my_peer_id := multiplayer.get_unique_id()

	var player_characters: Dictionary = get_meta("player_characters", {})
	var is_spectator := LobbyManager.is_spectator(my_peer_id) \
			or not player_characters.has(my_peer_id)

	if is_spectator:
		var ctrl := get_tree().get_first_node_in_group(GroupNames.SPECTATOR)
		if ctrl and ctrl.has_method("activate"):
			ctrl.activate()
		print("[World] Espectador local listo (nodos del roster ya creados localmente).")
		return

	var my_player: Node = null

	var timeout := 2.0
	var elapsed := 0.0
	while not my_player and elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		my_player = PlayerRegistry.get_player(my_peer_id)

	if not my_player:
		push_warning("[World] No se encontró el nodo del jugador local tras esperar.")
		return

	var cd_elapsed := 0.0
	while (not "character_data" in my_player or my_player.character_data == null) \
			and cd_elapsed < 1.0:
		await get_tree().process_frame
		cd_elapsed += get_process_delta_time()

	if not "character_data" in my_player or my_player.character_data == null:
		push_warning("[World] character_data nunca llegó al jugador local.")
		return

	if USE_MOCK_HUD and ResourceLoader.exists("res://ui/GameUI/Mock/GameHUDMock.tscn"):
		_hud = GAME_HUD_MOCK_SCENE.instantiate()
		print("[World] Usando GameHUDMock (TpBarCustom paralelogramo inline)")
	else:
		_hud = GAME_HUD_SCENE.instantiate()
	add_child(_hud)
	_hud.setup(my_player)


func _exit_tree() -> void:
	GameServiceLocator.clear()
