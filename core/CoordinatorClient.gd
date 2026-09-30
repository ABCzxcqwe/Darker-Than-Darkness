# res://core/CoordinatorClient.gd (Autoload)
# Cliente REST del coordinador de salas. La URL sale de SettingsManager.coordinator_url.
extends Node

var base_url: String = ""


func _ready() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm:
		base_url = String(sm.coordinator_url)
		if sm.has_signal("setting_changed") and not sm.setting_changed.is_connected(_on_setting_changed):
			sm.setting_changed.connect(_on_setting_changed)


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "coordinator_url":
		base_url = String(value)


func is_available() -> bool:
	return base_url.strip_edges() != ""


func create_room(room_name: String, map_id: String, mode: String, max_players: int, host_name: String = "") -> Dictionary:
	var payload := {
		"name": room_name,
		"host": host_name,
		"map": map_id,
		"mode": mode,
		"max": max_players,
	}
	var res = await _request(HTTPClient.METHOD_POST, "/api/rooms", JSON.stringify(payload))
	if res is Dictionary:
		return res
	return {}


func list_rooms(timeout: float = 20.0) -> Array:
	return await list_rooms_from(base_url, timeout)


func list_rooms_from(base: String, timeout: float = 20.0) -> Array:
	if base.strip_edges() == "":
		return []
	var res = await _request_base(base, HTTPClient.METHOD_GET, "/api/rooms", "", "", timeout)
	if res is Array:
		return res
	return []


func delete_room(room_id: String, token: String = "") -> bool:
	if room_id == "":
		return false
	var res = await _request(HTTPClient.METHOD_DELETE, "/api/rooms/" + room_id, "", token)
	return res != null


func _request(method: int, path: String, body: String, token: String = ""):
	return await _request_base(base_url, method, path, body, token)


func _request_base(base: String, method: int, path: String, body: String, token: String = "", timeout: float = 20.0):
	var b := base.strip_edges().rstrip("/")
	if b == "":
		push_warning("[CoordinatorClient] base vacia")
		return null
	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token.strip_edges() != "":
		headers.append("Authorization: Bearer " + token.strip_edges())
	var err := http.request(b + path, headers, method, body)
	if err != OK:
		push_warning("[CoordinatorClient] request error %d (%s)" % [err, path])
		http.queue_free()
		return null
	var res: Array = await http.request_completed
	http.queue_free()
	var response_code: int = int(res[1])
	var raw: PackedByteArray = res[3]
	if response_code < 200 or response_code >= 300:
		push_warning("[CoordinatorClient] HTTP %d en %s: %s" % [response_code, path, raw.get_string_from_utf8()])
		return null
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	return parsed
