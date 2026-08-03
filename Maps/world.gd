# res://Maps/world.gd
extends Node2D

const GAME_HUD_SCENE := preload("uid://cvjakwoxx54w4")
const PLAYER_SCENE := preload("uid://djw510qiudh6e")

@export var services_config: GameServicesConfig = null

@onready var map_container: Node2D = $MapContainer

var _hud: CanvasLayer = null
var current_map_node: BaseMap = null

# Peers espectadores que se unieron tarde. Solo se usa server-side.
# El host (dueño=servidor) no logra que el Synchronizer nativo le llegue el
# delta continuo a estos peers (la llamada local a set_visibility_for nunca
# "cruza la red", así que el motor nunca registra a ese peer como receptor
# válido de este nodo específico). Se le empuja la posición a mano, explícito.
var _late_spectator_peers: Array[int] = []
var _host_push_timer: Timer = null

func _ready() -> void:
	if not services_config:
		push_error("[World] No hay services_config asignado.")
		return

	GameServiceLocator.register_all(services_config)

	if multiplayer.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_disconnected_cleanup_spectator)
		_host_push_timer = Timer.new()
		_host_push_timer.name = "HostStatePushToSpectatorsTimer"
		_host_push_timer.wait_time = 0.1
		_host_push_timer.autostart = true
		_host_push_timer.timeout.connect(_push_host_state_to_late_spectators)
		add_child(_host_push_timer)

	await _load_map()

	# Inicializar eventos del mapa (coordinador)
	var coordinator = GameServiceLocator.map_event_coordinator
	if coordinator and coordinator.has_method("setup") and current_map_node:
		coordinator.setup(current_map_node)

	# Spawnear jugadores AHORA que el mapa ya está cargado
	if multiplayer.is_server():
		var player_characters = get_meta("player_characters", {})
		var spawner = $MultiplayerSpawner
		if spawner:
			for peer_id in player_characters:
				var char_id = player_characters[peer_id]
				spawner.spawn([peer_id, char_id])
		else:
			push_error("[World] No se encontró MultiplayerSpawner")

		await get_tree().process_frame
		_position_players_in_spawns()

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


func _setup_hud() -> void:
	var my_peer_id := multiplayer.get_unique_id()

	var player_characters: Dictionary = get_meta("player_characters", {})
	var is_spectator := LobbyManager.is_spectator(my_peer_id) \
			or not player_characters.has(my_peer_id)

	if is_spectator:
		var ctrl := get_tree().get_first_node_in_group(GroupNames.SPECTATOR)
		if ctrl and ctrl.has_method("activate"):
			ctrl.activate()
		if not multiplayer.is_server():
			print("[World] Espectador local listo, solicitando catch-up al servidor.")
			rpc_id(1, "_request_late_join_catchup")
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

	_hud = GAME_HUD_SCENE.instantiate()
	add_child(_hud)
	_hud.setup(my_player)


## ── Catch-up para espectadores que se unen con la partida en curso ─────────
##
## El handshake interno de confirmación entre MultiplayerSpawner y su Synchronizer
## solo se establece con los peers conectados AL MOMENTO del spawn() original.
## Un peer que se conecta después nunca queda "confirmado" para el motor, así que
## togglear set_visibility_for/update_visibility después no alcanza para el delta
## continuo. Por eso el fantasma se recrea a mano para este peer específico:
##
##   1) El espectador, ya con su World listo, pide catch-up: _request_late_join_catchup
##   2) El servidor le manda la lista de jugadores activos: _apply_late_join_catchup_spawn
##   3) El cliente los recrea localmente (mismo nombre que usa el spawner real)
##      y confirma: _confirm_late_join_catchup_ready
##   4) El servidor otorga visibilidad de cada jugador hacia este peer — el empujón
##      inicial (update_visibility) llega bien; el delta continuo del host es lo
##      que sigue sin resolverse (ver PlayerMovementComponent para el próximo fix).

@rpc("any_peer", "reliable")
func _request_late_join_catchup() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return

	var players_data: Array = []
	for player_node in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if not is_instance_valid(player_node):
			continue
		var owner_peer_id: int = player_node.get_multiplayer_authority()
		if owner_peer_id == sender:
			continue
		var char_id: int = -1
		if "character_data" in player_node and player_node.character_data:
			char_id = player_node.character_data.id
		if char_id == -1:
			char_id = LobbyManager.players.get(owner_peer_id, {}).get("character_id", -1)
		if char_id == -1:
			continue
		players_data.append({"peer_id": owner_peer_id, "char_id": char_id})

	print("[World] Catch-up solicitado por peer tardío ", sender, " | jugadores a recrear: ", players_data)
	rpc_id(sender, "_apply_late_join_catchup_spawn", players_data)


@rpc("authority", "reliable")
func _apply_late_join_catchup_spawn(players_data: Array) -> void:
	for entry in players_data:
		var peer_id: int = entry.get("peer_id", -1)
		var char_id: int = entry.get("char_id", -1)
		if peer_id == -1 or char_id == -1:
			continue
		var node_name := str(peer_id)
		if has_node(node_name):
			continue
		var player := PLAYER_SCENE.instantiate()
		player.name = node_name
		player.set_multiplayer_authority(peer_id)
		player.set_character(char_id)
		add_child(player)
		print("[World] Catch-up: recreado localmente el jugador ", peer_id, " (char: ", char_id, ")")

	rpc_id(1, "_confirm_late_join_catchup_ready")


@rpc("any_peer", "reliable")
func _confirm_late_join_catchup_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return

	var granted := 0
	for player_node in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if not is_instance_valid(player_node):
			continue
		if player_node.get_multiplayer_authority() == sender:
			continue
		PlayerLifecycleManager.grant_player_visibility_to_peer(player_node, sender)
		granted += 1

	if sender not in _late_spectator_peers:
		_late_spectator_peers.append(sender)

	print("[World] Catch-up confirmado por peer ", sender, " — visibilidad otorgada para ", granted,
		  " jugador(es). Push explícito de host activado para este peer.")


## Empuja explícitamente, vía RPC dirigido, la posición/animación de cada nodo
## cuyo dueño es el propio servidor (el host) hacia los espectadores tardíos.
## Se hace por fuera del Synchronizer nativo porque la llamada local a
## set_visibility_for jamás cruza la red, y el motor nunca "confirma" a estos
## peers como receptores válidos de ESTE nodo en particular (sí funciona bien
## para los nodos de clientes, porque ahí el otorgamiento SÍ viaja por RPC).
func _push_host_state_to_late_spectators() -> void:
	if _late_spectator_peers.is_empty():
		return

	for player_node in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if not is_instance_valid(player_node):
			continue
		if player_node.get_multiplayer_authority() != multiplayer.get_unique_id():
			continue  # solo nos interesan los nodos dueños del servidor (host)

		var anim := ""
		var flip_h := false
		if "animated_sprite" in player_node and player_node.animated_sprite:
			anim = String(player_node.animated_sprite.animation)
			flip_h = player_node.animated_sprite.flip_h

		for spectator_peer_id in _late_spectator_peers:
			rpc_id(spectator_peer_id, "_rpc_apply_host_state_for_spectator",
				player_node.get_multiplayer_authority(), player_node.global_position, anim, flip_h)


## Recibido por el cliente espectador. Aplica el estado directo sobre el
## fantasma correspondiente (sin pasar por MultiplayerSynchronizer).
@rpc("authority", "unreliable")
func _rpc_apply_host_state_for_spectator(host_peer_id: int, pos: Vector2, anim: String, flip_h: bool) -> void:
	var ghost := get_node_or_null(str(host_peer_id))
	if not ghost:
		return
		
	ghost.global_position = pos
	
	# Usamos 'as AnimatedSprite2D' para convertir la propiedad de forma segura.
	# Si 'animated_sprite' no existe o es null, la variable 'sprite' será null.
	var sprite := ghost.get("animated_sprite") as AnimatedSprite2D
	
	if is_instance_valid(sprite):
		if anim != "" and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
			if sprite.animation != anim:
				sprite.play(anim)
				
		sprite.flip_h = flip_h


func _on_peer_disconnected_cleanup_spectator(peer_id: int) -> void:
	_late_spectator_peers.erase(peer_id)


func _exit_tree() -> void:
	GameServiceLocator.clear()
