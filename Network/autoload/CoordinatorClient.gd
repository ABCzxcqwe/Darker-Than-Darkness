# res://Network/autoload/CoordinatorClient.gd
extends Node
## Cliente REST del coordinador de salas.
##
## La URL sale de `NetworkSettings` (que a su vez persiste en SettingsManager).
## También expone `heartbeat()` para que el servidor dedicado no duplique HTTP.

const TAG := "CoordinatorClient"

var base_url: String = ""


func _ready() -> void:
	_refresh_base_url()
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and sm.has_signal("setting_changed") and not sm.setting_changed.is_connected(_on_setting_changed):
		sm.setting_changed.connect(_on_setting_changed)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "coordinator_url":
		_refresh_base_url()


func _refresh_base_url() -> void:
	base_url = NetworkSettings.get_coordinator_url()


func is_available() -> bool:
	return base_url.strip_edges() != ""


func create_room(
	room_name: String,
	map_id: String,
	mode: String,
	max_players: int,
	host_name: String = ""
) -> Dictionary:
	var payload := {
		"name": room_name,
		"host": host_name,
		"map": map_id,
		"mode": mode,
		"max": max_players,
	}
	var res = await _request(HTTPClient.METHOD_POST, "/api/rooms", JSON.stringify(payload))
	return res if res is Dictionary else {}


func list_rooms(timeout: float = 20.0) -> Array:
	return await list_rooms_from(base_url, timeout)


func list_rooms_from(base: String, timeout: float = 20.0) -> Array:
	var res = await _request_base(base, HTTPClient.METHOD_GET, "/api/rooms", "", "", timeout)
	return res if res is Array else []


func delete_room(room_id: String, token: String = "") -> bool:
	if room_id.strip_edges() == "":
		return false
	return await request_ok("", HTTPClient.METHOD_DELETE, "/api/rooms/" + room_id, "", token)


func heartbeat(
	room_id: String,
	token: String,
	payload: Dictionary,
	base: String = "",
	timeout: float = NetConfig.HEARTBEAT_TIMEOUT
) -> bool:
	if room_id.strip_edges() == "":
		return false
	return await request_ok(
		base,
		HTTPClient.METHOD_POST,
		"/api/rooms/" + room_id + "/heartbeat",
		JSON.stringify(payload),
		token,
		timeout
	)


## Devuelve true si el HTTP quedó 2xx. Útil para heartbeats o DELETE.
func request_ok(
	base: String,
	method: int,
	path: String,
	body: String,
	token: String = "",
	timeout: float = 20.0
) -> bool:
	var raw := await _request_raw(base, method, path, body, token, timeout)
	return bool(raw.get("ok", false))


func _request(method: int, path: String, body: String, token: String = ""):
	return await _request_base(base_url, method, path, body, token)


func _request_base(
	base: String,
	method: int,
	path: String,
	body: String,
	token: String = "",
	timeout: float = 20.0
):
	var raw := await _request_raw(base, method, path, body, token, timeout)
	if not raw.get("ok", false):
		return null
	var text := String(raw.get("body", "")).strip_edges()
	if text == "":
		return {}
	return JSON.parse_string(text)


func _request_raw(
	base: String,
	method: int,
	path: String,
	body: String,
	token: String = "",
	timeout: float = 20.0
) -> Dictionary:
	var resolved_base := NetworkSettings.normalize_url(base if base.strip_edges() != "" else base_url)
	if resolved_base == "":
		NetLog.warn(TAG, "URL del coordinador vacía.")
		return {"ok": false, "code": -1, "body": ""}

	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)

	var headers := PackedStringArray(["Content-Type: application/json"])
	if token.strip_edges() != "":
		headers.append("Authorization: Bearer " + token.strip_edges())

	var err: int = http.request(resolved_base + path, headers, method, body)
	if err != OK:
		NetLog.warn(TAG, "request error %d (%s)" % [err, path])
		http.queue_free()
		return {"ok": false, "code": -1, "body": ""}

	var res: Array = await http.request_completed
	http.queue_free()

	var code := int(res[1])
	var raw: PackedByteArray = res[3]
	var text := raw.get_string_from_utf8()
	if code < 200 or code >= 300:
		NetLog.warn(TAG, "HTTP %d en %s: %s" % [code, path, text])
		return {"ok": false, "code": code, "body": text}
	return {"ok": true, "code": code, "body": text}
