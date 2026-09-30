# Prueba temporal de integracion (Opcion A): World real + spawn local + late-join.
# - Servidor: carga World con roster {host, bot}; mueve al bot via net_move_input.
# - Cliente: conecta TARDE, carga World con el mismo roster (simula char_map) y
#   debe recibir el delta continuo del Synchronizer sin MultiplayerSpawner.
extends Node

const PORT := 4251
const HOST_PEER := 1
const BOT_PEER := 7777
const CHAR_HOST := 1
const CHAR_BOT := 4

var _is_server := false
var _is_client := false
var _world: Node = null
var _elapsed := 0.0
var _t := 0.0
var _log_accum := 0.0
var _samples: Array = []
var _move_states: Dictionary = {}
var _seen_facing_right := false
var _seen_facing_left := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_is_server = "--spike-server" in args
	_is_client = "--spike-client" in args
	GameData.selected_map = "1"
	if _is_server:
		_start_server()
	elif _is_client:
		_start_client()
	else:
		print("[WL] usar -- --spike-server | --spike-client")
		get_tree().quit()


func _start_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 4) != OK:
		print("[WL-SERVER] create_server fallo"); get_tree().quit(1); return
	multiplayer.multiplayer_peer = peer
	LobbyManager.players = {
		HOST_PEER: {"name": "Host", "is_host": true, "character_id": CHAR_HOST, "assigned_role": "survivor"},
		BOT_PEER: {"name": "Bot", "is_host": false, "character_id": CHAR_BOT, "assigned_role": "survivor"},
	}
	print("[WL-SERVER] escuchando ", PORT)
	_load_world({HOST_PEER: CHAR_HOST, BOT_PEER: CHAR_BOT})


func _start_client() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client("127.0.0.1", PORT) != OK:
		print("[WL-CLIENT] create_client fallo"); get_tree().quit(1); return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)


func _on_connected() -> void:
	print("[WL-CLIENT] conectado my_id=", multiplayer.get_unique_id())
	_load_world({HOST_PEER: CHAR_HOST, BOT_PEER: CHAR_BOT})


func _load_world(roster: Dictionary) -> void:
	_world = load("res://Maps/World.tscn").instantiate()
	_world.set_meta("player_characters", roster)
	add_child(_world)
	print("[WL] World cargado")


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _is_server and _world and _world.has_node(str(BOT_PEER)):
		_t += delta
		var bot: Node = _world.get_node(str(BOT_PEER))
		bot.net_move_input = Vector2(cos(_t), sin(_t)).normalized()
		bot.net_sprint = false
		bot.facing_right = (int(_t * 0.5) % 2 == 0)
	if _is_client and _world and _world.has_node(str(BOT_PEER)):
		_log_accum += delta
		if _log_accum >= 0.5:
			_log_accum = 0.0
			var bot: Node = _world.get_node(str(BOT_PEER))
			var p: Vector2 = bot.global_position
			_samples.append(p.x)
			_move_states[bot.move_state] = true
			if bot.facing_right:
				_seen_facing_right = true
			else:
				_seen_facing_left = true
			print("[WL-CLIENT] t=%.1f pos=%s move_state=%d facing=%s" % [
				_elapsed, str(p), bot.move_state, str(bot.facing_right)])
	var run := 16.0 if _is_server else 9.0
	if _elapsed >= run:
		if _is_client:
			var distinct := {}
			for x in _samples:
				distinct[snappedf(x, 1.0)] = true
			print("[WL-CLIENT] RESULTADO samples=", _samples.size(), " distintos=", distinct.size(),
				" => ", "LATE SYNC OK" if distinct.size() > 1 else "LATE SIN SYNC")
			print("[WL-CLIENT] move_states=", _move_states.keys(),
				" facing_right=", _seen_facing_right, " facing_left=", _seen_facing_left)
		else:
			print("[WL-SERVER] fin")
		get_tree().quit()
