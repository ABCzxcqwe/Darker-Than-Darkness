# World.gd
# Script del nodo raíz de la partida.
# Inicializa servicios, carga el mapa seleccionado e instancia el HUD.
extends Node2D

const GAME_HUD_SCENE := preload("res://ui/GameUI/Scenes/GameHUD.tscn")

@export var services_config: GameServicesConfig = null

# Nodo vacío donde se instancia la escena del mapa — crearlo en World.tscn
@onready var map_container: Node2D = $MapContainer

var _hud: CanvasLayer = null

func _ready() -> void:
	if not services_config:
		push_error("[World] No hay services_config asignado.")
		return

	GameServiceLocator.register_all(services_config)
	_load_map()

	await get_tree().process_frame
	await get_tree().process_frame
	_setup_hud()

	# Iniciar ganancia pasiva de TP una vez que todos los jugadores
	# ya corrieron set_character() (gracias al call_deferred en el Spawner)
	if multiplayer.is_server():
		var tp := GameServiceLocator.get_service("TPService")
		if tp:
			tp.start_passive_gain()
		else:
			push_warning("[World] TPService no disponible — ganancia pasiva no iniciada.")


func _load_map() -> void:
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
	print("[World] Mapa '", map_data.display_name, "' cargado correctamente.")


func _setup_hud() -> void:
	var my_peer_id := multiplayer.get_unique_id()
	var my_player  := get_tree().root.find_child(str(my_peer_id), true, false)

	if not my_player:
		# En clientes el spawn puede tardar un poco más — esperar hasta 1s
		var timeout := 1.0
		var elapsed := 0.0
		while not my_player and elapsed < timeout:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
			my_player = get_tree().root.find_child(str(my_peer_id), true, false)

	if not my_player:
		push_warning("[World] No se encontró el nodo del jugador local tras esperar.")
		return

	_hud = GAME_HUD_SCENE.instantiate()
	add_child(_hud)
	_hud.setup(my_player)


func _exit_tree() -> void:
	GameServiceLocator.clear()
