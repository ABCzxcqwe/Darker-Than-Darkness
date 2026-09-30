# res://tests/net_spike/RealSync.gd
# Prueba de integracion temporal con la escena REAL del jugador.
# - Servidor: crea un Player para un peer ficticio y mueve su net_move_input.
#   PlayerMovementComponent._server_process debe simular y el Synchronizer
#   (autoridad 1) debe replicar la posicion.
# - Cliente tardio: recrea el proxy y observa la posicion (debe moverse).
extends Node2D

const PORT := 4246
const FAKE_OWNER := 7777
const CHAR_ID := 1
const SERVER_RUN_SECONDS := 16.0
const CLIENT_RUN_SECONDS := 8.0
const SAMPLE_INTERVAL := 0.5

var _is_server := false
var _is_client := false
var _elapsed := 0.0
var _t := 0.0
var _log_accum := 0.0
var _samples: Array = []
var _player: Node = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_is_server = "--spike-server" in args
	_is_client = "--spike-client" in args
	if _is_server:
		_start_server()
	elif _is_client:
		_start_client()
	else:
		print("[REAL] Usar: -- --spike-server | --spike-client")
		get_tree().quit()


func _start_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 4) != OK:
		print("[REAL-SERVER] create_server fallo")
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	print("[REAL-SERVER] escuchando ", PORT)
	_spawn_player(FAKE_OWNER)


func _start_client() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client("127.0.0.1", PORT) != OK:
		print("[REAL-CLIENT] create_client fallo")
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)


func _on_connected() -> void:
	print("[REAL-CLIENT] conectado my_id=", multiplayer.get_unique_id())
	_spawn_player(FAKE_OWNER)
	rpc_id(1, "_client_ready")


@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not _player:
		return
	PlayerLifecycleManager.grant_player_visibility_to_peer(_player, sender)
	print("[REAL-SERVER] visibilidad habilitada para ", sender)


func _spawn_player(owner_id: int) -> void:
	var ps := load("res://core/player/player.tscn") as PackedScene
	if ps == null:
		print("[REAL] FAIL: no carga player.tscn")
		get_tree().quit(1)
		return
	_player = ps.instantiate()
	_player.name = str(owner_id)
	_player.set_multiplayer_authority(owner_id)
	_player.set_character(CHAR_ID)
	add_child(_player)
	var sync := _player.get_node("Synchronizer") as MultiplayerSynchronizer
	var anim := _player.get_node("SynchronizerAnim") as MultiplayerSynchronizer
	print("[REAL] player creado id=", owner_id,
		" | sync_auth=", sync.get_multiplayer_authority(),
		" anim_auth=", anim.get_multiplayer_authority())


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _is_server and _player:
		_t += delta
		_player.net_move_input = Vector2(cos(_t), sin(_t)).normalized()
		_player.net_sprint = false

	if _is_client and _player:
		_log_accum += delta
		if _log_accum >= SAMPLE_INTERVAL:
			_log_accum = 0.0
			var p: Vector2 = _player.global_position
			_samples.append(p.x)
			print("[REAL-CLIENT] t=%.1f pos=%s" % [_elapsed, str(p)])

	var run := SERVER_RUN_SECONDS if _is_server else CLIENT_RUN_SECONDS
	if _elapsed >= run:
		if _is_client:
			var distinct := {}
			for x in _samples:
				distinct[snappedf(x, 0.5)] = true
			print("[REAL-CLIENT] RESULTADO samples=", _samples.size(),
				" distintos=", distinct.size(), " => ",
				"POS SYNC OK" if distinct.size() > 1 else "POS SIN SYNC")
		else:
			print("[REAL-SERVER] fin")
		get_tree().quit()
