# res://tests/net_spike/RealInput.gd
# Prueba temporal: cliente DUEÑO real.
# - Servidor: crea el Player del peer que se conecta (autoridad = peer).
# - Dueño: crea su propio Player, mantiene "move_right" y predice localmente.
# Valida: _submit_input(seq,...) llega al servidor + la prediccion del dueño mueve.
extends Node2D

const PORT := 4247
const CHAR_ID := 1
const SERVER_RUN_SECONDS := 16.0
const OWNER_RUN_SECONDS := 8.0
const SAMPLE_INTERVAL := 0.5

var _is_server := false
var _is_owner := false
var _elapsed := 0.0
var _log_accum := 0.0
var _samples: Array = []
var _player: Node = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_is_server = "--spike-server" in args
	_is_owner = "--spike-owner" in args
	if _is_server:
		var peer := ENetMultiplayerPeer.new()
		if peer.create_server(PORT, 4) != OK:
			print("[RIN-SERVER] create_server fallo"); get_tree().quit(1); return
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_on_peer)
		print("[RIN-SERVER] escuchando ", PORT)
	elif _is_owner:
		var peer := ENetMultiplayerPeer.new()
		if peer.create_client("127.0.0.1", PORT) != OK:
			print("[RIN-OWNER] create_client fallo"); get_tree().quit(1); return
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(_on_connected)
	else:
		print("[RIN] Usar: -- --spike-server | --spike-owner"); get_tree().quit()


func _on_peer(id: int) -> void:
	print("[RIN-SERVER] peer conectado ", id)
	_spawn(id)


func _on_connected() -> void:
	var my_id := multiplayer.get_unique_id()
	print("[RIN-OWNER] conectado my_id=", my_id)
	_spawn(my_id)
	Input.action_press("move_right")


func _spawn(id: int) -> void:
	var ps := load("res://core/player/player.tscn") as PackedScene
	_player = ps.instantiate()
	_player.name = str(id)
	_player.set_multiplayer_authority(id)
	_player.set_character(CHAR_ID)
	add_child(_player)
	print("[RIN] player id=", id, " authority=", _player.get_multiplayer_authority(),
		" is_auth=", _player.is_multiplayer_authority())


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _is_owner and _player:
		# A los 3s cambia de direccion para forzar mas reconciliacion.
		if _elapsed > 3.0 and not Input.is_action_pressed("move_down"):
			Input.action_press("move_down")
		_log_accum += delta
		if _log_accum >= SAMPLE_INTERVAL:
			_log_accum = 0.0
			var p: Vector2 = _player.global_position
			_samples.append(p)
			print("[RIN-OWNER] t=%.1f pos=%s seq_local=%d" % [_elapsed, str(p), _player.movement_component._client_input_seq])
	elif _is_server and _player:
		_log_accum += delta
		if _log_accum >= SAMPLE_INTERVAL:
			_log_accum = 0.0
			print("[RIN-SERVER] t=%.1f pos=%s last_seq=%d" % [_elapsed, str(_player.global_position), _player.net_last_input_seq])

	var run := SERVER_RUN_SECONDS if _is_server else OWNER_RUN_SECONDS
	if _elapsed >= run:
		if _is_owner:
			var distinct := {}
			for pnt in _samples:
				distinct[snappedf(pnt.x, 1.0)] = true
			print("[RIN-OWNER] RESULTADO samples=", _samples.size(), " distintos_x=", distinct.size())
		else:
			print("[RIN-SERVER] RESULTADO last_seq=", _player.net_last_input_seq if _player else -1,
				" pos=", str(_player.global_position) if _player else "?")
		get_tree().quit()
