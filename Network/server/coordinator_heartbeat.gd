class_name CoordinatorHeartbeat
extends Node
## Heartbeat periódico del servidor dedicado al coordinador de salas.
##
## Separado de DedicatedServer para que el bootstrap no mezcle CLI, red y HTTP.
## Usa CoordinatorClient para no duplicar el manejo de HTTPRequest.

const TAG := "CoordinatorHeartbeat"

var _room_id := ""
var _room_token := ""
var _base_url := ""
var _fail_limit := NetConfig.HEARTBEAT_FAIL_LIMIT
var _timer: Timer = null
var _failures := 0
var _busy := false


func setup(
	room_id: String,
	room_token: String,
	base_url: String,
	interval: float = NetConfig.HEARTBEAT_INTERVAL,
	fail_limit: int = NetConfig.HEARTBEAT_FAIL_LIMIT
) -> void:
	_room_id = room_id.strip_edges()
	_room_token = room_token.strip_edges()
	_base_url = NetworkSettings.normalize_url(base_url)
	_fail_limit = maxi(1, fail_limit)
	if _room_id == "" or _base_url == "":
		return

	_timer = Timer.new()
	_timer.wait_time = maxf(1.0, interval)
	_timer.autostart = false
	_timer.timeout.connect(_send)
	add_child(_timer)
	_timer.start()
	_send()


func stop() -> void:
	if _timer:
		_timer.stop()
	set_process(false)


func _send() -> void:
	if _busy or _room_id == "" or _base_url == "":
		return

	var lobby := get_node_or_null("/root/LobbyManager")
	var players := 0
	var phase := 0
	if lobby:
		players = lobby.players.size()
		phase = int(lobby.current_phase)

	var payload := {
		"status": "ready",
		"players": players,
		"phase": str(phase),
	}
	var client := get_node_or_null("/root/CoordinatorClient")
	if client == null or not client.has_method("heartbeat"):
		_on_failure()
		return

	_busy = true
	var ok: bool = await client.heartbeat(_room_id, _room_token, payload, _base_url)
	_busy = false
	if ok:
		_failures = 0
	else:
		_on_failure()


func _on_failure() -> void:
	_failures += 1
	NetLog.warn(TAG, "Heartbeat falló (%d/%d)." % [_failures, _fail_limit])
	if _failures >= _fail_limit:
		NetLog.error(TAG, "Coordinador inalcanzable; cerrando instancia.")
		get_tree().quit(1)


func _exit_tree() -> void:
	stop()
