extends Node

const MAX_PLAYERS := 4
const PORT := 4242

signal connection_succeeded()
signal connection_failed()
signal server_disconnected()
signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int)
signal player_ready_changed(peer_id: int, is_ready: bool)
signal lobby_updated()

var current_game_manager: Node = null
var peer: ENetMultiplayerPeer
var players: Dictionary = {}       # peer_id -> { name, is_host, character_id }
var local_player_name: String = ""
var selected_map: String = ""
var is_host: bool = false

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connect_fail)
	multiplayer.server_disconnected.connect(_on_internal_server_disconnected) 

func _on_internal_server_disconnected():
	print("Servidor interno desconectado, llamando a reset_to_menu")
	reset_to_menu()
	
func create_server(player_name: String, map_name: String) -> bool:
	local_player_name = player_name
	selected_map = map_name
	is_host = true

	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		print("Error al crear servidor: ", err)
		return false
	multiplayer.multiplayer_peer = peer

	# Agregar al propio servidor en la lista
	var my_id = multiplayer.get_unique_id()
	players[my_id] = {
		"name": player_name,
		"is_host": true,
		"character_id": 0
	}
	emit_signal("player_joined", my_id, players[my_id])
	emit_signal("connection_succeeded")
	return true

func join_server(player_name: String, ip: String = "127.0.0.1") -> bool:
	local_player_name = player_name
	is_host = false

	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, PORT)
	if err != OK:
		print("Error al conectar: ", err)
		return false
	multiplayer.multiplayer_peer = peer
	return true

func _cleanup_game_manager():
	if current_game_manager:
		# Forzar eliminación inmediata del mundo y sus hijos
		if current_game_manager.has_method("cleanup"):
			current_game_manager.cleanup()
		current_game_manager.queue_free()
		current_game_manager = null
		# Procesar varios frames para que Godot libere referencias
		await get_tree().process_frame
		await get_tree().process_frame

func get_player_list() -> Array:
	var list = []
	for id in players:
		var info = players[id].duplicate()
		info.id = id
		list.append(info)
	return list

func get_local_character() -> int:
	var my_id = multiplayer.get_unique_id()
	if players.has(my_id):
		return players[my_id].character_id
	return 0

func set_my_character(char_id: int):
	var my_id = multiplayer.get_unique_id()
	if players.has(my_id):
		players[my_id].character_id = char_id
		# Notificar al servidor para que propague a todos
		if is_host:
			# El servidor ya tiene el dato, solo actualiza lobby
			emit_signal("lobby_updated")
		else:
			rpc_id(1, "_update_character", char_id)

@rpc("any_peer", "call_local")
func _update_character(char_id: int):
	var sender = multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		if players.has(sender):
			players[sender].character_id = char_id
			emit_signal("lobby_updated")
			# Opcional: replicar a todos los clientes
			rpc("_sync_character", sender, char_id)

@rpc("authority", "reliable")
func _sync_character(peer_id: int, char_id: int):
	if not multiplayer.is_server():
		if players.has(peer_id):
			players[peer_id].character_id = char_id
			emit_signal("lobby_updated")

func start_game():
	if not is_host:
		return
	var char_map = {}
	for id in players:
		char_map[id] = players[id].character_id
	rpc("_begin_game", char_map, selected_map)

@rpc("authority", "call_local", "reliable")
func _begin_game(char_map: Dictionary, map_id: String):
	print("Comenzando juego con personajes: ", char_map, " | mapa: ", map_id)

	# Sincronizar mapa a GameData — así world.gd puede leerlo en todos los peers
	GameData.selected_map = map_id

	# Eliminar lobby
	for lobby in get_tree().get_nodes_in_group("lobby"):
		lobby.queue_free()

	# Crear nuevo gestor de juego
	current_game_manager = preload("res://Main.tscn").instantiate()
	add_child(current_game_manager)
	current_game_manager.start_game(char_map, map_id)

# Señales internas
func _on_peer_connected(peer_id: int):
	if not multiplayer.is_server():
		return
	# El servidor pide el nombre del nuevo cliente
	rpc_id(peer_id, "_request_player_info")

@rpc("any_peer", "call_local")
func _request_player_info():
	var sender = multiplayer.get_remote_sender_id()
	rpc_id(sender, "_send_player_info", local_player_name)

@rpc("any_peer", "call_local")
func _send_player_info(player_name: String):
	var sender = multiplayer.get_remote_sender_id()
	if multiplayer.is_server():
		players[sender] = {
			"name": player_name,
			"is_host": false,
			"character_id": 0
		}
		emit_signal("player_joined", sender, players[sender])
		# Enviar a todos los clientes la lista actualizada
	for pid in players:
		if pid != multiplayer.get_unique_id():
			rpc_id(pid, "_sync_player_list", players)

@rpc("authority", "reliable")
func _sync_player_list(all_players: Dictionary):
	players = all_players
	emit_signal("lobby_updated")

func _on_peer_disconnected(peer_id: int):
	if multiplayer.is_server():
		players.erase(peer_id)
		emit_signal("player_left", peer_id)   # 👈 debe estar
		var self_id = multiplayer.get_unique_id()
		for pid in players:
			if pid != self_id:
				rpc_id(pid, "_sync_player_list", players)

func _on_connected_ok():
	emit_signal("connection_succeeded")

func _on_connect_fail():
	emit_signal("connection_failed")

func disconnect_from_server():
	await _cleanup_game_manager()   # esperar a que termine
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	emit_signal("server_disconnected")

#func _exit_tree():
#	if NetworkManager:
#		NetworkManager.disconnect_from_server()

func reset_to_menu():
	print("[NetworkManager] reset_to_menu - iniciando")
	
	# Cerrar peer inmediatamente
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	
	# Eliminar el gestor de juego si existe
	if current_game_manager:
		if current_game_manager.has_method("cleanup"):
			current_game_manager.cleanup()
		current_game_manager.queue_free()
		current_game_manager = null
	
	# Limpiar datos
	players.clear()
	local_player_name = ""
	selected_map = ""
	is_host = false
	
	# No usamos await aquí para no bloquear; cambio de escena diferido
	call_deferred("_do_change_to_menu")

func _do_change_to_menu():
	if is_inside_tree():
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")
