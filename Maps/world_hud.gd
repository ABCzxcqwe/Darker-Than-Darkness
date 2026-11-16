# res://Network/session/world_hud.gd
class_name WorldHud
extends Node
## Crea y administra HUD/scoreboard del World, sin mezclar carga de mapa ni
## lógica de red.

const TAG := "WorldHud"
const USE_MOCK_HUD := true

var _world: Node
var _hud: CanvasLayer = null
var _scoreboard: Node = null


func setup(world: Node) -> void:
	_world = world


func get_hud() -> CanvasLayer:
	return _hud


func get_scoreboard() -> Node:
	return _scoreboard


func setup_for_mode(mode: String) -> void:
	if mode != "play":
		return
	setup_scoreboard()
	await setup_hud()


func setup_scoreboard() -> void:
	var ds := _world.get_node_or_null("/root/DedicatedServer")
	if ds and ds.is_dedicated:
		return
	var packed := load(NetScenes.SCOREBOARD) as PackedScene
	if packed == null:
		NetLog.warn(TAG, "No se pudo cargar el Scoreboard.")
		return
	_scoreboard = packed.instantiate()
	_world.add_child(_scoreboard)


func setup_hud() -> void:
	var my_peer_id: int = _world.multiplayer.get_unique_id()
	var player_characters: Dictionary = _world.get_meta("player_characters", {})
	var is_spectator := LobbyManager.is_spectator(my_peer_id) or not player_characters.has(my_peer_id)

	if is_spectator:
		_world.view.activate_spectator()
		NetLog.info(TAG, "Espectador local listo.")
		return

	var my_player: Node = null
	var timeout := 2.0
	var elapsed := 0.0
	while not my_player and elapsed < timeout:
		await _world.get_tree().process_frame
		elapsed += _world.get_process_delta_time()
		my_player = PlayerLifecycleManager.get_player(my_peer_id)

	if not my_player:
		NetLog.warn(TAG, "No se encontró el nodo del jugador local tras esperar.")
		return

	var cd_elapsed := 0.0
	while (not "character_data" in my_player or my_player.character_data == null) and cd_elapsed < 1.0:
		await _world.get_tree().process_frame
		cd_elapsed += _world.get_process_delta_time()

	if not "character_data" in my_player or my_player.character_data == null:
		NetLog.warn(TAG, "character_data nunca llegó al jugador local.")
		return

	var hud_scene: PackedScene
	if USE_MOCK_HUD and ResourceLoader.exists(NetScenes.GAME_HUD_MOCK):
		hud_scene = load(NetScenes.GAME_HUD_MOCK) as PackedScene
	else:
		hud_scene = load(NetScenes.GAME_HUD_UID) as PackedScene
	if hud_scene == null:
		NetLog.error(TAG, "No se pudo cargar el HUD.")
		return

	_hud = hud_scene.instantiate()
	_world.add_child(_hud)
	_hud.setup(my_player)
	_world.view.set_local_player_camera(true)

	# Menú Dev in-game: solo host local con jugador y DevMode activo.
	if DevMode.is_enabled() and _world.multiplayer.is_server():
		var ds := _world.get_node_or_null("/root/DedicatedServer")
		if not (ds and ds.is_dedicated):
			var dev_scene := load(NetScenes.DEV_MENU) as PackedScene
			if dev_scene:
				var dev_menu := dev_scene.instantiate()
				_hud.add_child(dev_menu)
				dev_menu.setup(my_player)


func set_hud_mode(mode: String) -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	match mode:
		"play":
			_hud.process_mode = Node.PROCESS_MODE_INHERIT
			_hud.visible = true
			if _hud.has_method("set_spectator_ui_active"):
				_hud.set_spectator_ui_active(false)
		"spectate":
			_hud.process_mode = Node.PROCESS_MODE_INHERIT
			_hud.visible = true
			if _hud.has_method("set_spectator_ui_active"):
				_hud.set_spectator_ui_active(true)
		"hub":
			_hud.visible = false
			_hud.process_mode = Node.PROCESS_MODE_DISABLED
