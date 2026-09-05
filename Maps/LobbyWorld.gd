# res://Maps/LobbyWorld.gd
# Mundo fisico del lobby - solo mapa y corazon, sin interfaz
extends Node2D

@onready var map_container: Node2D = $MapContainer
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner

const HEART_SCENE := preload("res://core/player/LobbyHeart.tscn")
var current_map_node: BaseMap = null
var _exiting := false

func _ready() -> void:
	add_to_group("lobby_world")
	await _load_lobby_map()
	# Spawn local para entrada individual (cada peer entra cuando quiere)
	# Cada peer spawnea corazones para todos los jugadores en LobbyManager
	for pid in LobbyManager.players:
		_spawn_heart_local(pid)
	LobbyManager.player_joined.connect(_on_player_joined)
	LobbyManager.player_left.connect(_on_player_left)
	LobbyManager.lobby_updated.connect(_on_lobby_updated)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_add_exit_button()

func _load_lobby_map() -> void:
	var map_data: MapData = MapRegistry.get_map("Lobby")
	if not map_data:
		push_error("[LobbyWorld] MapData Lobby no encontrado")
		return
	var inst = map_data.map_scene.instantiate()
	map_container.add_child(inst)
	current_map_node = inst as BaseMap
	if not inst.is_node_ready():
		await inst.ready
	print("[LobbyWorld] Mapa Lobby cargado")


func _get_deterministic_spawn(peer_id: int) -> Vector2:
	if current_map_node and current_map_node.survivor_spawns and current_map_node.survivor_spawns.get_child_count() > 0:
		var count := current_map_node.survivor_spawns.get_child_count()
		# Deterministico: mismo peer_id -> mismo spawn en todos los peers
		var idx := absi(peer_id) % count
		var node := current_map_node.survivor_spawns.get_child(idx) as Marker2D
		if node:
			return node.global_position
	elif current_map_node:
		return current_map_node.global_position
	return Vector2.ZERO


func _spawn_heart_local(peer_id: int) -> void:
	var existing := get_node_or_null(str(peer_id))
	if existing:
		return
	var heart := HEART_SCENE.instantiate()
	heart.name = str(peer_id)
	heart.set_multiplayer_authority(peer_id)
	add_child(heart, true)
	heart.global_position = _get_deterministic_spawn(peer_id)


func _position_hearts() -> void:
	if not current_map_node:
		return
	for pid in LobbyManager.players:
		var node := get_node_or_null(str(pid)) as Node2D
		if node and node.has_method("get"):
			if current_map_node.has_method("get_random_survivor_spawn"):
				node.global_position = current_map_node.get_random_survivor_spawn()


func _on_player_joined(peer_id: int, _info: Dictionary) -> void:
	_spawn_heart_local(peer_id)


func _on_player_left(peer_id: int) -> void:
	var n := get_node_or_null(str(peer_id))
	if n:
		n.queue_free()


func _on_lobby_updated() -> void:
	# Actualizar color si cambio
	for pid in LobbyManager.players:
		var n := get_node_or_null(str(pid))
		if n and n.has_method("_apply_color"):
			n._apply_color()


func _on_peer_disconnected(peer_id: int) -> void:
	var n := get_node_or_null(str(peer_id))
	if n:
		n.queue_free()


func _add_exit_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	var btn := Button.new()
	btn.text = "SALIR [X]"
	btn.custom_minimum_size = Vector2(170, 40)
	btn.position = Vector2(20, 20)
	btn.focus_mode = Control.FOCUS_NONE
	var font := preload("res://Fonts/deltarune font.ttf")
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 18)
	# Estilo simple
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.6)
	box.border_color = Color(0, 1, 0, 1)
	box.border_width_left = 2
	box.border_width_top = 2
	box.border_width_right = 2
	box.border_width_bottom = 2
	box.corner_radius_top_left = 6
	box.corner_radius_top_right = 6
	box.corner_radius_bottom_left = 6
	box.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", box)
	btn.add_theme_color_override("font_color", Color(0, 1, 0, 1))
	btn.pressed.connect(_on_exit_pressed)
	layer.add_child(btn)
	add_child(layer)
	print("[LobbyWorld] Boton SALIR agregado")


func _on_exit_pressed() -> void:
	if _exiting:
		return
	_exiting = true
	if not is_inside_tree():
		return
	set_process_unhandled_input(false)
	# Liberar corazones antes de cambiar escena para que Synchronizer no busque nodos nulos
	for h in get_tree().get_nodes_in_group("lobby_hearts"):
		if is_instance_valid(h):
			h.queue_free()
	get_tree().call_deferred("change_scene_to_file", "res://ui/MainMenu/scenes/Lobby.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if _exiting:
		return
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null:
		return
	if event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		_on_exit_pressed()
		vp.set_input_as_handled()


func _exit_tree() -> void:
	if LobbyManager.player_joined.is_connected(_on_player_joined):
		LobbyManager.player_joined.disconnect(_on_player_joined)
	if LobbyManager.player_left.is_connected(_on_player_left):
		LobbyManager.player_left.disconnect(_on_player_left)
	if LobbyManager.lobby_updated.is_connected(_on_lobby_updated):
		LobbyManager.lobby_updated.disconnect(_on_lobby_updated)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
