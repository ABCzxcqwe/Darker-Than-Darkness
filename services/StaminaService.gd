extends Node

signal stamina_changed(peer_id: int, current_stamina: float, max_stamina: float)

const EXHAUST_DURATION: float = 2.0

var _stamina: Dictionary = {}
var _character_data: Dictionary = {}
var _sprinting: Dictionary = {}
var _exhausted: Dictionary = {}
var _tick_timer: Timer


func _ready() -> void:
	if multiplayer.is_server():
		_tick_timer = Timer.new()
		_tick_timer.wait_time = 0.1
		_tick_timer.autostart = true
		_tick_timer.timeout.connect(_on_tick)
		add_child(_tick_timer)


func register_player(peer_id: int, data: Resource) -> void:
	_stamina[peer_id] = data.stamina_max
	_character_data[peer_id] = data
	_sprinting[peer_id] = false
	_exhausted[peer_id] = -1.0
	stamina_changed.emit(peer_id, data.stamina_max, data.stamina_max)
	sync_stamina_to_client.rpc(peer_id, data.stamina_max, data.stamina_max)


func unregister_player(peer_id: int) -> void:
	_stamina.erase(peer_id)
	_character_data.erase(peer_id)
	_sprinting.erase(peer_id)
	_exhausted.erase(peer_id)


@rpc("any_peer", "reliable")
func sync_stamina_to_client(peer_id: int, current: float, max_s: float) -> void:
	_stamina[peer_id] = current
	stamina_changed.emit(peer_id, current, max_s)


func get_stamina(peer_id: int) -> float:
	return _stamina.get(peer_id, 0.0)


func has_stamina(peer_id: int) -> bool:
	return _stamina.get(peer_id, 0.0) > 0.0


## Llamado por el cliente vía RPC para informar si está corriendo.
@rpc("any_peer", "reliable")
func set_sprinting(peer_id: int, sprinting: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != peer_id and sender != 1:
		return
	_sprinting[peer_id] = sprinting


func _on_tick() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for pid in _stamina.keys():
		var data = _character_data.get(pid)
		if not data:
			continue

		var current = _stamina[pid]
		var new_val: float

		if _sprinting.get(pid, false):
			var drain = data.stamina_sprint_drain * 0.1
			new_val = clamp(current - drain, 0.0, data.stamina_max)
			if new_val <= 0.0 and current > 0.0 and _exhausted.get(pid, -1.0) < 0.0:
				_exhausted[pid] = now
		else:
			var exhausted_at = _exhausted.get(pid, -1.0)
			if exhausted_at >= 0.0:
				if now - exhausted_at >= EXHAUST_DURATION:
					_exhausted.erase(pid)
					var regen = data.stamina_regen_rate * 0.1
					new_val = clamp(current + regen, 0.0, data.stamina_max)
				else:
					new_val = 0.0
			else:
				var regen = data.stamina_regen_rate * 0.1
				new_val = clamp(current + regen, 0.0, data.stamina_max)

		if not is_equal_approx(new_val, current):
			_stamina[pid] = new_val
			stamina_changed.emit(pid, new_val, data.stamina_max)
			sync_stamina_to_client.rpc(pid, new_val, data.stamina_max)


func reset() -> void:
	_stamina.clear()
	_character_data.clear()
	_sprinting.clear()
	_exhausted.clear()
	if _tick_timer:
		_tick_timer.stop()
