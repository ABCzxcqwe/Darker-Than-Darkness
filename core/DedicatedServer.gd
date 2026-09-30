# res://core/DedicatedServer.gd
#
# Arranque del servidor dedicado (headless).
#
# Detecta la bandera --server en la linea de comandos y levanta un servidor
# ENet autoritativo SIN registrar un jugador local ni mostrar UI.
#
# Uso pensado (una vez cableado como autoload):
#   godot --headless -- --server --port=4300 --max=10 --map=<id> --mode=Escape --name="Mi Server"
#
# Este script es autocontenido a proposito: no depende de metodos nuevos en
# otros archivos. El cableado (autoload, NetworkManager, supresion de UI) se
# hace en un paso posterior.
extends Node

const DEFAULT_PORT := 4242
const DEFAULT_MAX_PLAYERS := 10
const MIN_PLAYERS := 2
const MAX_PLAYERS := 10
const DEFAULT_MODE := "Escape"
const HEARTBEAT_FAIL_LIMIT := 6

## True si este proceso corre como servidor dedicado.
var is_dedicated: bool = false

## Configuracion resuelta desde la linea de comandos.
var config: Dictionary = {}

## Identificador de sala, token secreto y URL del coordinador (opcionales, para heartbeats).
var room_id: String = ""
var room_token: String = ""
var coordinator_url: String = ""
var _heartbeat_http: HTTPRequest = null
var _heartbeat_timer: Timer = null
var _heartbeat_failures := 0


func _ready() -> void:
	is_dedicated = _detect_server_flag()
	if not is_dedicated:
		return
	config = _parse_config()
	call_deferred("_boot_dedicated")


## Detecta --server tanto en args del motor como en user args (tras "--").
func _detect_server_flag() -> bool:
	if "--server" in OS.get_cmdline_args():
		return true
	if "--server" in OS.get_cmdline_user_args():
		return true
	return false


## Parsea flags tipo --clave=valor. Los args del usuario pisan a los del motor.
func _parse_config() -> Dictionary:
	var cfg := {
		"port": DEFAULT_PORT,
		"max_players": DEFAULT_MAX_PLAYERS,
		"map": "",
		"mode": DEFAULT_MODE,
		"name": "Servidor Dedicado",
		"room_id": "",
		"room_token": "",
		"coordinator": "",
	}
	var merged: Array = []
	merged.append_array(OS.get_cmdline_args())
	merged.append_array(OS.get_cmdline_user_args())
	for arg in merged:
		if not arg.begins_with("--"):
			continue
		var eq: int = arg.find("=")
		if eq <= 2:
			continue
		var key: String = arg.substr(2, eq - 2)
		var value: String = arg.substr(eq + 1)
		match key:
			"port":
				cfg["port"] = int(value)
			"max", "max_players":
				cfg["max_players"] = clampi(int(value), MIN_PLAYERS, MAX_PLAYERS)
			"map":
				cfg["map"] = value
			"mode":
				cfg["mode"] = value
			"name":
				cfg["name"] = value
			"room-id":
				cfg["room_id"] = value
			"room-token":
				cfg["room_token"] = value
			"coordinator":
				cfg["coordinator"] = value
	return cfg


func _boot_dedicated() -> void:
	var port: int = int(config["port"])
	var max_players: int = int(config["max_players"])
	print("[DedicatedServer] Boot headless | puerto=%d max=%d mapa='%s' modo='%s' sala='%s'" % [
		port, max_players, config["map"], config["mode"], config["name"]
	])

	var nm := get_node_or_null("/root/NetworkManager")
	if nm == null:
		push_error("[DedicatedServer] NetworkManager no disponible; abortando boot dedicado.")
		get_tree().quit(1)
		return

	var ok: bool = false
	if nm.has_method("start_dedicated_server"):
		ok = nm.start_dedicated_server(
			String(config["name"]),
			String(config["map"]),
			String(config["mode"]),
			max_players,
			port
		)
	else:
		push_error("[DedicatedServer] NetworkManager no implementa start_dedicated_server().")
	if not ok:
		push_error("[DedicatedServer] No se pudo iniciar el servidor dedicado. Abortando proceso.")
		get_tree().quit(1)
		return

	room_id = String(config["room_id"])
	room_token = String(config["room_token"])
	coordinator_url = String(config["coordinator"])
	if room_id != "" and coordinator_url != "":
		_start_heartbeat()

	print("[DedicatedServer] Servidor dedicado listo.")


func _start_heartbeat() -> void:
	_heartbeat_http = HTTPRequest.new()
	_heartbeat_http.timeout = 4.0
	_heartbeat_http.request_completed.connect(_on_heartbeat_result)
	add_child(_heartbeat_http)
	_heartbeat_timer = Timer.new()
	_heartbeat_timer.wait_time = 5.0
	_heartbeat_timer.autostart = true
	_heartbeat_timer.timeout.connect(_send_heartbeat)
	add_child(_heartbeat_timer)
	_send_heartbeat()


func _send_heartbeat() -> void:
	if room_id == "" or coordinator_url == "" or _heartbeat_http == null:
		return
	var lm := get_node_or_null("/root/LobbyManager")
	var players := 0
	var phase := 0
	if lm:
		players = lm.players.size()
		phase = lm.current_phase
	var payload := {
		"status": "ready",
		"players": players,
		"phase": str(phase),
	}
	var body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if room_token != "":
		headers.append("Authorization: Bearer " + room_token)
	var url := coordinator_url.rstrip("/") + "/api/rooms/" + room_id + "/heartbeat"
	var err := _heartbeat_http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err == ERR_BUSY:
		return
	if err != OK:
		_on_heartbeat_failed()


func _on_heartbeat_result(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if response_code >= 200 and response_code < 300:
		_heartbeat_failures = 0
	else:
		_on_heartbeat_failed()


func _on_heartbeat_failed() -> void:
	_heartbeat_failures += 1
	if _heartbeat_failures >= HEARTBEAT_FAIL_LIMIT:
		push_error("[DedicatedServer] Coordinador inalcanzable; cerrando instancia.")
		get_tree().quit(1)
