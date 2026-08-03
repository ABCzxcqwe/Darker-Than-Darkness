# res://Maps/world.gd
extends Node2D

const GAME_HUD_SCENE := preload("uid://cvjakwoxx54w4")
const PLAYER_SCENE := preload("uid://csh822kwn5s2e")

@export var services_config: GameServicesConfig = null

@onready var map_container: Node2D = $MapContainer

var _hud: CanvasLayer = null
var current_map_node: BaseMap = null

func _ready() -> void:
	if not services_config:
		push_error("[World] No hay services_config asignado.")
		return

	GameServiceLocator.register_all(services_config)

	if multiplayer.is_server():
		LobbyManager.player_joined.connect(_on_spectator_joined)

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
		_start_spectator_snapshot_poll()
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


func _on_spectator_joined(peer_id: int, player_info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if not player_info.get("is_spectator", false):
		return
	_exclude_peer_from_synchronizers(peer_id)


## El espectador que entra tarde no recibe los nodos spawneados vía MultiplayerSpawner,
## así que los deltas de los MultiplayerSynchronizer le llegan con rutas irresolubles
## y generan el error "Ignoring delta for non-authority or invalid synchronizer".
## Los ocultamos de ese peer en el servidor; su vista se alimenta del snapshot manual.
func _exclude_peer_from_synchronizers(peer_id: int) -> void:
	for sync in get_tree().root.find_children("*", "MultiplayerSynchronizer", true, false):
		if sync.has_method("set_visibility_for"):
			sync.set_visibility_for(peer_id, false)


func _start_spectator_snapshot_poll() -> void:
	if multiplayer.is_server() or not is_inside_tree():
		return
	var timer := Timer.new()
	timer.name = "SpectatorSnapshotPoll"
	timer.wait_time = 0.15
	timer.autostart = true
	timer.timeout.connect(_do_request_spectator_snapshot)
	add_child(timer)


func _do_request_spectator_snapshot() -> void:
	if multiplayer.is_server() or not is_inside_tree():
		return
	rpc_id(1, "_request_spectator_snapshot")


## El servidor responde con un snapshot de los jugadores vivos no-espectadores.
## Necesario porque el MultiplayerSynchronizer no replica a peers que se unen tarde
## (no recibieron el nodo vía el MultiplayerSpawner en el momento del spawn).
@rpc("any_peer", "reliable")
func _request_spectator_snapshot() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_exclude_peer_from_synchronizers(sender)
	var snap := {}
	for p in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if not is_instance_valid(p):
			continue
		var pid := p.get_multiplayer_authority()
		if LobbyManager.is_spectator(pid):
			continue
		if "health_state" in p and p.health_state != "alive":
			continue
		var char_id: int = LobbyManager.players.get(pid, {}).get("character_id", -1)
		if char_id == -1 and "character_data" in p and p.character_data:
			char_id = p.character_data.id
		var entry := {
			"char_id": char_id,
			"pos": p.global_position,
			"health": p.health,
			"health_state": p.health_state,
		}
		if "animated_sprite" in p and p.animated_sprite:
			entry["flip_h"] = p.animated_sprite.flip_h
			entry["animation"] = String(p.animated_sprite.animation)
			entry["frame"] = p.animated_sprite.frame
		snap[pid] = entry
	rpc_id(sender, "_apply_spectator_snapshot", snap)


@rpc("authority", "reliable")
func _apply_spectator_snapshot(snap: Dictionary) -> void:
	if multiplayer.is_server() or not is_inside_tree():
		return
	var alive_pids := {}
	for pid in snap:
		alive_pids[int(pid)] = true
		var entry: Dictionary = snap[pid]
		var player := _ensure_spectator_player(int(pid), int(entry.get("char_id", -1)))
		if not player:
			continue
		if not player.get_meta("_spectator_manual_spawn", false):
			continue
		player.global_position = entry.get("pos", Vector2.ZERO)
		if "health" in entry:
			player.health = int(entry.health)
		if "health_state" in entry:
			player.health_state = entry.health_state
		if "animated_sprite" in player and player.animated_sprite:
			var sprite = player.animated_sprite
			if "flip_h" in entry:
				sprite.flip_h = bool(entry.flip_h)
			if "animation" in entry:
				var frames = sprite.sprite_frames
				if frames and frames.has_animation(entry.animation):
					sprite.animation = entry.animation
					var frame := int(entry.get("frame", 0))
					sprite.frame = mini(frame, maxi(0, frames.get_frame_count(entry.animation) - 1))

	for node in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if node.get_meta("_spectator_manual_spawn", false) \
				and not alive_pids.has(node.get_multiplayer_authority()):
			node.queue_free()


func _ensure_spectator_player(pid: int, char_id: int) -> Node:
	var peer_str := str(pid)
	if has_node(peer_str):
		return get_node(peer_str)
	if char_id == -1:
		return null
	var player := PLAYER_SCENE.instantiate()
	player.name = peer_str
	player.set_multiplayer_authority(pid)
	player.set_character(char_id)
	player.set_meta("_spectator_manual_spawn", true)
	add_child(player)
	return player


func _exit_tree() -> void:
	GameServiceLocator.clear()
