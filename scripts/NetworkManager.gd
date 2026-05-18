# res://scripts/NetworkManager.gd
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
var players: Dictionary = {}        # peer_id -> { name, is_host, character_id, killer_points, assigned_role }
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

	# CORRECCIÓN: Inicializar al Host de forma estructurada en su ID correspondiente (1)
	var my_id = multiplayer.get_unique_id()
	players[my_id] = {
		"name": player_name,
		"is_host": true,
		"character_id": -1,       # Obliga a elegir personaje en la nueva pantalla
		"killer_points": 0,       # Puntos de sesión para sorteo de Killer
		"assigned_role": "survivor"
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
		if current_game_manager.has_method("cleanup"):
			current_game_manager.cleanup()
		current_game_manager.queue_free()
		current_game_manager = null
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
	return -1

func set_my_character(char_id: int):
	var my_id = multiplayer.get_unique_id()
	if players.has(my_id):
		players[my_id].character_id = char_id
		if is_host:
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
			rpc("_sync_character", sender, char_id)

@rpc("authority", "reliable")
func _sync_character(peer_id: int, char_id: int):
	if not multiplayer.is_server():
		if players.has(peer_id):
			players[peer_id].character_id = char_id
			emit_signal("lobby_updated")

# ── SECCIÓN DE SELECCIÓN DE PERSONAJES Y FLUJO ASIMÉTRICO ──

## El botón "Iniciar" del Lobby ahora debe llamar a ESTA función en lugar de start_game
func host_start_character_selection():
	if not is_host: return
	
	if players.size() < 2:
		print("[NetworkManager] Se necesitan al menos 2 jugadores.")
		return

	# Sorteo por puntos acumulados
	var highest_points: int = -1
	var candidates: Array[int] = []
	
	for pid in players:
		var p_data = players[pid]
		if p_data.killer_points > highest_points:
			highest_points = p_data.killer_points
			candidates = [pid]
		elif p_data.killer_points == highest_points:
			candidates.append(pid)
	
	var killer_peer_id: int = candidates[randi() % candidates.size()]
	
	# Configurar roles iniciales e indicar que nadie ha elegido personaje (-1)
	for pid in players:
		players[pid]["character_id"] = -1
		if pid == killer_peer_id:
			players[pid]["assigned_role"] = "killer"
		else:
			players[pid]["assigned_role"] = "survivor"
			
	rpc("_go_to_character_selection", players)

@rpc("authority", "call_local", "reliable")
func _go_to_character_selection(assigned_players: Dictionary):
	players = assigned_players
	# Borrar la UI del Lobby viejo si se encuentra activa
	for lobby in get_tree().get_nodes_in_group("lobby"):
		lobby.queue_free()
	get_tree().change_scene_to_file("res://ui/GameUI/Scenes/CharacterSelect.tscn")

## Llamado por cada jugador desde la pantalla de selección para asegurar su personaje
@rpc("any_peer", "call_local", "reliable")
func select_character_in_screen(char_id: int):
	var sender_id = multiplayer.get_remote_sender_id()
	
	# Si es 0, la llamada se originó en esta misma computadora
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	# REGLA DE RED: Solo el servidor procesa y distribuye el estado oficial
	if multiplayer.is_server():
		if players.has(sender_id):
			players[sender_id]["character_id"] = char_id
			print("[Server] Peer %d seleccionó personaje ID: %d" % [sender_id, char_id])
			
			# El servidor actualiza su propia interfaz
			emit_signal("lobby_updated")
			
			# El servidor le grita a TODOS los clientes la actualización del bando
			rpc("_sync_screen_selection", sender_id, char_id)
	else:
		# Si un cliente pulsó el botón, le envía un reporte directo y exclusivo al Servidor (ID 1)
		rpc_id(1, "select_character_in_screen", char_id)
		
## RPC de apoyo: Los clientes reciben la verdad absoluta desde el Servidor
@rpc("authority", "reliable")
func _sync_screen_selection(peer_id: int, char_id: int):
	# Evitamos que el servidor lo procese doble, esto es solo para los clientes
	if not multiplayer.is_server():
		if players.has(peer_id):
			players[peer_id]["character_id"] = char_id
			print("[Cliente] Sincronizado: Peer %d ahora es personaje %d" % [peer_id, char_id])
			emit_signal("lobby_updated")

## Llamado cuando el temporizador de la pantalla de selección expira para iniciar el mapa real
func host_launch_game():
	if not is_host: return
	
	var char_map = {}
	for id in players:
		char_map[id] = players[id].character_id
		
	rpc("_begin_game", char_map, selected_map)
	

@rpc("authority", "call_local", "reliable")
func _begin_game(char_map: Dictionary, map_id: String):
	print("Comenzando partida con el mapa: ", map_id)
	GameData.selected_map = map_id

	# Cerramos la pantalla de selección de personajes
	for node in get_tree().get_nodes_in_group("character_select_screen"):
		node.queue_free()

	current_game_manager = preload("res://Main.tscn").instantiate()
	add_child(current_game_manager)
	current_game_manager.start_game(char_map, map_id)

# ── SEÑALES INTERNAS DE PEERS Y RED ──

func _on_peer_connected(peer_id: int):
	if not multiplayer.is_server():
		return
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
			"character_id": -1,
			"killer_points": 0,
			"assigned_role": "survivor"
		}
		emit_signal("player_joined", sender, players[sender])
		
		var self_id = multiplayer.get_unique_id()
		for pid in players:
			if pid != self_id:
				rpc_id(pid, "_sync_lobby_state", players, selected_map)

@rpc("authority", "reliable")
func _sync_lobby_state(all_players: Dictionary, map_id: String):
	players = all_players
	selected_map = map_id 
	emit_signal("lobby_updated")

func _on_peer_disconnected(peer_id: int):
	if multiplayer.is_server():
		players.erase(peer_id)
		emit_signal("player_left", peer_id)
		var self_id = multiplayer.get_unique_id()
		for pid in players:
			if pid != self_id:
				rpc_id(pid, "_sync_lobby_state", players, selected_map)

func _on_connected_ok():
	emit_signal("connection_succeeded")

func _on_connect_fail():
	emit_signal("connection_failed")

func disconnect_from_server():
	await _cleanup_game_manager()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	is_host = false
	emit_signal("server_disconnected")

func reset_to_menu():
	print("[NetworkManager] reset_to_menu - iniciando")
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	
	if current_game_manager:
		if current_game_manager.has_method("cleanup"):
			current_game_manager.cleanup()
		current_game_manager.queue_free()
		current_game_manager = null
	
	players.clear()
	local_player_name = ""
	selected_map = ""
	is_host = false
	call_deferred("_do_change_to_menu")

func _do_change_to_menu():
	if is_inside_tree():
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")
