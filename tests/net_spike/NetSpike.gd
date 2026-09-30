# res://tests/net_spike/NetSpike.gd
#
# FASE 0/1 - Spike de validacion aislado (temporal).
#
# Valida:
#  1) Late-join nativo: un cliente que se conecta DESPUES de que el servidor ya
#     creo el nodo recibe el delta continuo si recrea el nodo localmente.
#  2) Desacople de autoridad: el nodo padre conserva la autoridad del dueno
#     (identidad) mientras la posicion se replica desde el servidor.
#  3) DOS Synchronizer en el mismo nodo con autoridades distintas:
#       - SynchronizerPos  (authority=1/servidor) -> position
#       - SynchronizerAnim (authority=dueno)      -> z_index  (proxy de anim)
#     Esto permite que posicion sea server-authoritative y que la animacion/
#     apuntado sigan calculandose en el cliente.
#
# Uso:
#   server: -- --spike-server --parent-authority=local
#   client: -- --spike-client --parent-authority=local

extends Node2D

const PORT := 4243
const SYNC_NODE_NAME := "SyncTarget"
const SERVER_RUN_SECONDS := 16.0
const CLIENT_RUN_SECONDS := 8.0
const SAMPLE_INTERVAL := 0.5

var _is_server := false
var _is_client := false
var _parent_authority := 1
var _sync_node: Node2D = null
var _sync_pos: MultiplayerSynchronizer = null
var _sync_anim: MultiplayerSynchronizer = null
var _elapsed := 0.0
var _server_time := 0.0
var _log_accum := 0.0
var _peer_connected := false
var _samples_x: Array = []
var _client_anim := 0
var _last_server_anim := -9999
var _anim_samples := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_is_server = "--spike-server" in args
	_is_client = "--spike-client" in args
	_parent_authority = _arg_int(args, "--parent-authority", 1)
	if _is_server:
		_start_server()
	elif _is_client:
		_start_client()
	else:
		print("[SPIKE] Usar: -- --spike-server  |  -- --spike-client")
		get_tree().quit()


func _arg_int(args: PackedStringArray, key: String, default_value: int) -> int:
	for a in args:
		if a.begins_with(key + "="):
			var raw := a.substr(key.length() + 1)
			if raw == "local":
				return -1
			return int(raw)
	return default_value


func _owner_authority() -> int:
	if _parent_authority == -1:
		return multiplayer.get_unique_id()
	return _parent_authority


func _start_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 4)
	if err != OK:
		print("[SPIKE-SERVER] Error create_server: ", err)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	print("[SPIKE-SERVER] Escuchando en ", PORT)

	_sync_node = _make_sync_node(_owner_authority())
	_sync_node.name = SYNC_NODE_NAME
	_sync_node.global_position = Vector2(100, 100)
	add_child(_sync_node)
	print("[SPIKE-SERVER] Nodo creado. parent=", _sync_node.get_multiplayer_authority(),
		" pos_auth=", _sync_pos.get_multiplayer_authority(),
		" anim_auth=", _sync_anim.get_multiplayer_authority())


func _start_client() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client("127.0.0.1", PORT)
	if err != OK:
		print("[SPIKE-CLIENT] Error create_client: ", err)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	print("[SPIKE-CLIENT] Conectando a 127.0.0.1:", PORT, "...")


func _on_connection_failed() -> void:
	print("[SPIKE-CLIENT] Fallo la conexion.")
	get_tree().quit(1)


func _on_connected() -> void:
	print("[SPIKE-CLIENT] Conectado. my_id=", multiplayer.get_unique_id())
	_sync_node = _make_sync_node(_owner_authority())
	_sync_node.name = SYNC_NODE_NAME
	add_child(_sync_node)
	print("[SPIKE-CLIENT] Proxy creado. parent=", _sync_node.get_multiplayer_authority(),
		" pos_auth=", _sync_pos.get_multiplayer_authority(),
		" anim_auth=", _sync_anim.get_multiplayer_authority(),
		" is_authority=", _sync_node.is_multiplayer_authority())


func _make_sync_node(owner_authority: int) -> Node2D:
	var body := CharacterBody2D.new()
	body.set_multiplayer_authority(owner_authority)

	# Posicion: autoridad del servidor.
	_sync_pos = MultiplayerSynchronizer.new()
	_sync_pos.name = "SynchronizerPos"
	_sync_pos.set_multiplayer_authority(1)
	var cfg_pos := SceneReplicationConfig.new()
	var p_pos := NodePath(".:position")
	cfg_pos.add_property(p_pos)
	cfg_pos.property_set_spawn(p_pos, true)
	cfg_pos.property_set_sync(p_pos, true)
	cfg_pos.property_set_replication_mode(p_pos, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	_sync_pos.replication_config = cfg_pos
	_sync_pos.public_visibility = false
	body.add_child(_sync_pos)

	# Animacion: autoridad del dueno (el cliente la calcula y la envia).
	_sync_anim = MultiplayerSynchronizer.new()
	_sync_anim.name = "SynchronizerAnim"
	_sync_anim.set_multiplayer_authority(owner_authority)
	var cfg_anim := SceneReplicationConfig.new()
	var p_anim := NodePath(".:z_index")
	cfg_anim.add_property(p_anim)
	cfg_anim.property_set_spawn(p_anim, true)
	cfg_anim.property_set_sync(p_anim, true)
	cfg_anim.property_set_replication_mode(p_anim, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	_sync_anim.replication_config = cfg_anim
	_sync_anim.public_visibility = true
	body.add_child(_sync_anim)

	return body


func _on_peer_connected(id: int) -> void:
	_peer_connected = true
	print("[SPIKE-SERVER] Peer conectado: ", id)
	# El dueno de la animacion de ESTE nodo es el peer que se conecta.
	_sync_anim.set_multiplayer_authority(id)
	print("[SPIKE-SERVER] anim_auth cambiado a ", id, ". Otorgando visibilidad de posicion en 0.5s...")
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(_sync_pos):
		_sync_pos.set_visibility_for(id, true)
		_sync_pos.update_visibility(id)
		print("[SPIKE-SERVER] visibilidad de posicion otorgada a ", id)


func _physics_process(delta: float) -> void:
	if _is_server and _sync_node:
		_server_time += delta
		_sync_node.global_position = Vector2(100, 100) \
			+ Vector2(cos(_server_time), sin(_server_time)) * 100.0
		# Observar si llega la animacion desde el cliente (z_index).
		if _sync_node.z_index != _last_server_anim:
			_last_server_anim = _sync_node.z_index
			_anim_samples += 1
			print("[SPIKE-SERVER] anim recibida z_index=", _last_server_anim, " (muestra ", _anim_samples, ")")

	if _is_client and _sync_node:
		# El dueno calcula "animacion" (aca un int) y la envia via SynchronizerAnim.
		if int(_elapsed * 2.0) != _client_anim:
			_client_anim = int(_elapsed * 2.0)
			_sync_node.z_index = _client_anim

	_elapsed += delta

	if _is_client and _sync_node:
		_log_accum += delta
		if _log_accum >= SAMPLE_INTERVAL:
			_log_accum = 0.0
			var p := _sync_node.global_position
			_samples_x.append(p.x)
			print("[SPIKE-CLIENT] t=%.1f pos=%s" % [_elapsed, str(p)])

	var run_seconds := SERVER_RUN_SECONDS if _is_server else CLIENT_RUN_SECONDS
	if _elapsed >= run_seconds:
		_report_and_quit()


func _report_and_quit() -> void:
	if _is_client:
		var distinct := {}
		for x in _samples_x:
			distinct[snappedf(x, 0.5)] = true
		var moved := distinct.size() > 1
		print("[SPIKE-CLIENT] RESULTADO pos samples=", _samples_x.size(),
			" distintos=", distinct.size(), " => ",
			"POS SYNC OK" if moved else "POS SIN SYNC")
	if _is_server:
		print("[SPIKE-SERVER] RESULTADO anim muestras_recibidas=", _anim_samples,
			" => ", "ANIM SYNC OK" if _anim_samples > 1 else "ANIM SIN SYNC")
	get_tree().quit()
