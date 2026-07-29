# res://Maps/world.gd
extends Node2D

const GAME_HUD_SCENE := preload("uid://cvjakwoxx54w4")
const SPECTATOR_PANEL_SCENE := preload("uid://t2j32htjrq7r")

@export var services_config: GameServicesConfig = null

@onready var map_container: Node2D = $MapContainer

var _hud: CanvasLayer = null
var current_map_node: BaseMap = null

var _is_spectator := false
var _spectator_camera: Camera2D = null
var _spectator_panel: PanelContainer = null
var _spec_follow_target: Node = null
var _spec_freecam_offset: Vector2 = Vector2.ZERO
var _spec_freecam_speed: float = 400.0
var _spec_is_freecam := false

const SPECTATOR_ZOOM := 0.7

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

	if LobbyManager.is_spectator(my_peer_id):
		_setup_spectator_mode()
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


func _setup_spectator_mode() -> void:
	print("[World] Modo espectador activado para peer local")
	_is_spectator = true

	_spectator_camera = Camera2D.new()
	_spectator_camera.name = "SpectatorCamera"
	_spectator_camera.enabled = true
	_spectator_camera.zoom = Vector2(SPECTATOR_ZOOM, SPECTATOR_ZOOM)
	_spectator_camera.position_smoothing_enabled = true
	_spectator_camera.position_smoothing_speed = 10.0
	add_child(_spectator_camera)

	_spectator_panel = SPECTATOR_PANEL_SCENE.instantiate()
	_spectator_panel.prev_requested.connect(_on_spectator_prev)
	_spectator_panel.next_requested.connect(_on_spectator_next)
	add_child(_spectator_panel)

	_cycle_spectator_target(1)

	set_process(true)


func _process(delta: float) -> void:
	if not _is_spectator:
		return

	_update_spectator_input(delta)
	_update_spectator_camera(delta)


func _update_spectator_input(delta: float) -> void:
	if Input.is_action_just_pressed("spec_toggle"):
		_spec_is_freecam = not _spec_is_freecam
		if _spec_is_freecam:
			_spectator_camera.position_smoothing_enabled = false
		else:
			_spectator_camera.position_smoothing_enabled = true

	var next_dir := 0
	if Input.is_action_just_pressed("spec_next"):
		next_dir = 1
	elif Input.is_action_just_pressed("spec_prev"):
		next_dir = -1
	if next_dir != 0:
		_cycle_spectator_target(next_dir)

	if _spec_is_freecam:
		var move := Input.get_vector("spec_left", "spec_right", "spec_up", "spec_down")
		_spec_freecam_offset += move * _spec_freecam_speed * delta


func _update_spectator_camera(delta: float) -> void:
	if not _spectator_camera:
		return

	if _spec_is_freecam:
		_spectator_camera.position = _spec_freecam_offset
	elif _spec_follow_target and is_instance_valid(_spec_follow_target):
		_spectator_camera.global_position = _spec_follow_target.global_position


func _cycle_spectator_target(direction: int) -> void:
	var players_in_group := get_tree().get_nodes_in_group(GroupNames.PLAYERS)
	if players_in_group.is_empty():
		return

	var current_idx := -1
	if _spec_follow_target and is_instance_valid(_spec_follow_target):
		current_idx = players_in_group.find(_spec_follow_target)

	var new_idx := current_idx + direction
	while new_idx < 0:
		new_idx += players_in_group.size()
	new_idx = new_idx % players_in_group.size()

	_spec_follow_target = players_in_group[new_idx]
	_update_spectator_panel()


func _on_spectator_prev() -> void:
	_cycle_spectator_target(-1)


func _on_spectator_next() -> void:
	_cycle_spectator_target(1)


func _update_spectator_panel() -> void:
	if not _spectator_panel or not _spec_follow_target or not is_instance_valid(_spec_follow_target):
		return
	var pid := _spec_follow_target.get_multiplayer_authority()
	var pdata := LobbyManager.players.get(pid, {})
	var char_id := pdata.get("character_id", -1)

	var display_name := "?"
	var icon: Texture2D = null
	if char_id != -1:
		var cdata: CharacterData = CharacterRegistry.get_character(char_id)
		if cdata:
			display_name = cdata.display_name
			icon = cdata.icon

	var player_name := pdata.get("name", "")
	_spectator_panel.set_target(pid, display_name, player_name, icon)

	var hp := 0
	var max_hp := 100
	var health_svc = GameServiceLocator.health
	if health_svc:
		var pstate := health_svc.get_player_state(pid)
		if pstate == "dead":
			_spectator_panel.set_hp(0, 100)
		else:
			var player_node = PlayerRegistry.get_player(pid)
			if player_node and "health" in player_node and "character_data" in player_node and player_node.character_data:
				hp = player_node.health
				max_hp = player_node.character_data.max_health
			_spectator_panel.set_hp(hp, max_hp)
	else:
		_spectator_panel.set_hp(0, 100)


func _exit_tree() -> void:
	GameServiceLocator.clear()
