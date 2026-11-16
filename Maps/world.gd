# res://Session/world.gd
extends Node2D
## Orquestador del World de partida: carga de mapa, spawns, visibilidad de
## RollbackSynchronizer (netfox) y transición a PLAYING.
##
## HUD/scoreboard viven en WorldHud; el modo de vista local en WorldView.

const TAG := "World"

@export var services_config: GameServicesConfig = null

@onready var map_container: Node2D = $MapContainer

var hud: WorldHud
var view: WorldView
var current_map_node: BaseMap = null
var _player_scene: PackedScene = null


func _ready() -> void:
	if not services_config:
		NetLog.error(TAG, "No hay services_config asignado.")
		return

	_player_scene = load(NetScenes.PLAYER_UID) as PackedScene

	hud = WorldHud.new()
	hud.name = "WorldHud"
	add_child(hud)
	hud.setup(self)

	view = WorldView.new()
	view.name = "WorldView"
	add_child(view)
	view.setup(self)
	view.set_initial_mode(String(get_meta("local_view_mode", "play")))

	GameServiceLocator.register_all(services_config)
	await _load_map()
	_apply_camera_bounds()
	view.collect_canvas_modulates()

	var coordinator = GameServiceLocator.map_event_coordinator
	if coordinator and coordinator.has_method("setup") and current_map_node:
		coordinator.setup(current_map_node)

	# Spawn determinista local: cada peer crea los nodos de jugador desde el
	# roster. Sin MultiplayerSpawner, netfox sincroniza por ruta de nodo.
	var player_characters: Dictionary = get_meta("player_characters", {})
	var spawned := _spawn_players_locally(player_characters)

	if multiplayer.is_server():
		await get_tree().process_frame
		_position_players_in_spawns()
	else:
		# Avisamos al servidor que nuestros nodos ya existen para que habilite la
		# visibilidad de los RollbackSynchronizer hacia nosotros. Le pasamos la
		# lista exacta de nodos que este peer tiene, para no enviarle RPC a rutas
		# inexistentes.
		rpc_id(LobbyManager.server_peer_id, "_peer_world_ready", spawned)

	await get_tree().process_frame
	await get_tree().process_frame
	await hud.setup_for_mode(view.get_mode())
	view.mark_ready()
	view.apply()

	if multiplayer.is_server():
		var tp = GameServiceLocator.tp
		if tp:
			tp.start_passive_gain()
		else:
			NetLog.warn(TAG, "TPService no disponible — ganancia pasiva no iniciada.")

	NetLog.info(TAG, "Mapa cargado e inicializado correctamente.")

	var game_state = GameServiceLocator.game_state
	if game_state:
		game_state.transition_to_playing()


func _apply_camera_bounds() -> void:
	if current_map_node == null:
		return
	if not current_map_node.has_method("get_camera_bounds"):
		return
	var rig := CameraRig.get_active()
	if rig == null:
		return
	var bounds: Variant = current_map_node.get_camera_bounds()
	if bounds is Rect2:
		rig.set_map_bounds(bounds)


func _load_map() -> void:
	var map_id: String = SessionState.active_map_id
	if map_id == "":
		map_id = LobbyManager.selected_map
	if map_id == "":
		NetLog.warn(TAG, "active_map_id vacío — no se cargará ningún mapa.")
		return

	var map_data: MapData = MapRegistry.get_map(map_id)
	if not map_data:
		NetLog.error(TAG, "No se encontró MapData para id '%s'." % map_id)
		return
	if not map_data.map_scene:
		NetLog.error(TAG, "MapData '%s' no tiene map_scene asignada." % map_id)
		return

	var map_instance := map_data.map_scene.instantiate()
	map_container.add_child(map_instance)
	current_map_node = map_instance as BaseMap

	if not map_instance.is_node_ready():
		await map_instance.ready

	NetLog.info(TAG, "Mapa '%s' cargado e inicializado correctamente." % map_data.display_name)


## Instancia todos los jugadores del roster localmente en este peer.
## Devuelve los peer_id de los nodos que realmente quedaron creados.
func _spawn_players_locally(player_characters: Dictionary) -> Array:
	var spawned: Array = []
	var peer_ids: Array = player_characters.keys()
	peer_ids.sort()

	# Reparto determinista: mismo orden de peers y de marcadores en todos los
	# peers, así cada jugador aparece en su spawn designado aunque todavía no
	# haya llegado el estado del servidor.
	var killer_spawns := _map_spawn_positions("killer")
	var survivor_spawns := _map_spawn_positions("survivor")
	var killer_index := 0
	var survivor_index := 0

	for peer_id in peer_ids:
		var pid := int(peer_id)
		if not _spawn_player_node(pid, int(player_characters[peer_id])):
			continue
		spawned.append(pid)

		var player_node := get_node_or_null(str(pid))
		if player_node == null:
			continue
		var team := "survivor"
		if player_node.character_data != null:
			team = String(player_node.character_data.team)

		var spawn_position: Vector2
		if team == "killer":
			spawn_position = _pick_spawn(
				killer_spawns, killer_index, _map_fallback_position(), Vector2(0.0, -96.0)
			)
			killer_index += 1
		else:
			spawn_position = _pick_spawn(
				survivor_spawns, survivor_index, _map_fallback_position(), Vector2(96.0, 0.0)
			)
			survivor_index += 1

		player_node.set_meta("spawn_position", spawn_position)
		_apply_spawn_position(player_node, spawn_position)
	return spawned


func _map_spawn_positions(team: String) -> Array[Vector2]:
	if current_map_node == null:
		return []
	if team == "killer":
		if current_map_node.has_method("get_killer_spawn_positions"):
			return current_map_node.get_killer_spawn_positions()
	elif current_map_node.has_method("get_survivor_spawn_positions"):
		return current_map_node.get_survivor_spawn_positions()
	return []


func _map_fallback_position() -> Vector2:
	if current_map_node != null:
		return current_map_node.global_position
	return global_position


func _apply_spawn_position(player_node: Node, spawn_position: Vector2) -> void:
	if player_node == null or not is_instance_valid(player_node):
		return
	if player_node.has_method("set_spawn_position"):
		player_node.set_spawn_position(spawn_position)
		return
	player_node.global_position = spawn_position


func _spawn_player_node(peer_id: int, char_id: int) -> bool:
	var node_name := str(peer_id)
	if has_node(node_name):
		return true

	if _player_scene == null:
		NetLog.error(TAG, "No se pudo cargar la escena de jugador (%s)." % NetScenes.PLAYER_UID)
		return false

	var role := PlayerInfo.ROLE_SURVIVOR
	if LobbyManager.players.has(peer_id):
		role = String(LobbyManager.players[peer_id].get("assigned_role", role))

	var resolved_id := char_id
	if char_id <= 0 or not CharacterRegistry.has_character(char_id):
		var fallback := CharacterRegistry.get_fallback(role)
		if fallback == null:
			NetLog.error(TAG, "Peer %d sin personaje (id %d) y sin fallback para rol '%s'." % [peer_id, char_id, role])
			return false
		resolved_id = fallback.id
		NetLog.warn(TAG, "Peer %d: ID %d no resuelto; usando fallback '%s' (id %d)." % [
			peer_id, char_id, fallback.display_name, fallback.id
		])

	var player := _player_scene.instantiate()
	player.name = node_name
	# netfox: el Player es autoridad del servidor y el dueño real va en owner_peer_id.
	player.owner_peer_id = peer_id
	player.set_multiplayer_authority(1)
	player.set_character(resolved_id)
	if player.character_data == null:
		NetLog.error(TAG, "Peer %d quedó sin character_data tras set_character(%d)." % [peer_id, resolved_id])
		player.free()
		return false
	add_child(player)
	NetLog.debug(TAG, "Jugador spawneado: peer %d (char %d)." % [peer_id, resolved_id])
	return true


## Un peer avisa que ya creó sus nodos de jugador. El servidor habilita la
## visibilidad del RollbackSynchronizer y fuerza el estado inicial de posición.
@rpc("any_peer", "reliable")
func _peer_world_ready(spawned_peers: Array) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return

	PlayerLifecycleManager.mark_peer_world_ready(sender)

	var local_ids := {}
	for pid in spawned_peers:
		local_ids[int(pid)] = true

	var granted := 0
	for player_node in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if not is_instance_valid(player_node):
			continue
		var owner_id := PlayerLifecycleManager.get_owner_peer_id(player_node)
		if not local_ids.has(owner_id):
			NetLog.warn(TAG, "Peer %d no tiene el nodo de %d; se omite visibilidad." % [sender, owner_id])
			continue
		PlayerLifecycleManager.grant_player_visibility_to_peer(player_node, sender)
		player_node.rpc_id(sender, "_sync_server_position", player_node.global_position)
		# La vida/estado quedan fuera del rollback: mandamos un snapshot al peer
		# que recién entra (p. ej. espectador tardío).
		if player_node.has_method("_sync_state"):
			player_node.rpc_id(sender, "_sync_state", player_node.health_state, player_node.health)
		granted += 1

	# Late-join: si es espectador, mandarle el estado de audio completo.
	var player_characters: Dictionary = get_meta("player_characters", {})
	if not player_characters.has(sender):
		var data: Dictionary = AudioManager.get_priority_sync_data()
		var relay := GameServiceLocator.get_client_relay()
		if relay:
			relay.rpc_id(sender, "_rpc_sync_spectator_audio", SessionState.active_map_id,
				data["priority"], data["position"], data["lms_peer"])

	NetLog.debug(TAG, "Peer %d confirmó World listo; visibilidad para %d jugador(es)." % [sender, granted])


func _position_players_in_spawns() -> void:
	if not current_map_node and map_container and map_container.get_child_count() > 0:
		current_map_node = map_container.get_child(0) as BaseMap
	if not current_map_node:
		NetLog.error(TAG, "Imposible posicionar jugadores: no hay mapa cargado.")
		return

	for player_node in get_tree().get_nodes_in_group(GroupNames.PLAYERS):
		if not is_instance_valid(player_node):
			continue
		var spawn_position: Vector2 = player_node.get_meta("spawn_position", Vector2.ZERO)
		_apply_spawn_position(player_node, spawn_position)
		player_node.rpc("_sync_server_position", spawn_position)
		var team := "survivor"
		if player_node.character_data != null:
			team = String(player_node.character_data.team)
		NetLog.debug(TAG, "Spawn %s (%s) -> %s" % [player_node.name, team, spawn_position])


func _pick_spawn(spawns: Array[Vector2], index: int, fallback: Vector2, team_shift: Vector2) -> Vector2:
	if spawns.is_empty():
		return fallback + team_shift + Vector2(64.0 * index, 0.0)
	if index < spawns.size():
		return spawns[index]
	var base := spawns[index % spawns.size()]
	var cycle := int(floor(float(index) / float(spawns.size()))) + 1
	var angle := TAU * float(index) / float(spawns.size())
	return base + Vector2(cos(angle), sin(angle)) * (72.0 * cycle)


func set_local_view_mode(mode: String) -> void:
	if view:
		view.set_local_view_mode(mode)


func get_spectator_controller() -> Node:
	var ctrl := get_node_or_null("SpectatorController")
	if ctrl:
		return ctrl
	return get_tree().get_first_node_in_group(GroupNames.SPECTATOR)


func _exit_tree() -> void:
	GameServiceLocator.clear()
