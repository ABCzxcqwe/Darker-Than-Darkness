extends Node

# _cooldowns = { peer_id: { slot_index: { "lock": bool, "expiry": int } } }
# lock = true  → cooldown indefinido (la habilidad está ejecutándose)
# lock = false → expiry timestamp (0 = listo, >0 = esperando)
var _cooldowns: Dictionary = {}


func _ensure(peer_id: int, slot_index: int) -> void:
	if not _cooldowns.has(peer_id):
		_cooldowns[peer_id] = {}
	if not _cooldowns[peer_id].has(slot_index):
		_cooldowns[peer_id][slot_index] = { "lock": false, "expiry": 0 }


## Lock indefinido — la habilidad está ejecutándose.
## El slot queda bloqueado hasta que la habilidad llame release_lock() o start().
func start_lock(peer_id: int, slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	_ensure(peer_id, slot_index)
	_cooldowns[peer_id][slot_index]["lock"] = true
	_cooldowns[peer_id][slot_index]["expiry"] = 0
	print("[CooldownService] Lock activado -> Peer: ", peer_id, " | Slot: ", slot_index)
	rpc_id(peer_id, "_rpc_cooldown_state", slot_index, -1.0)


## Libera el lock sin iniciar cooldown. El slot queda listo inmediatamente.
func release_lock(peer_id: int, slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	_ensure(peer_id, slot_index)
	_cooldowns[peer_id][slot_index]["lock"] = false
	_cooldowns[peer_id][slot_index]["expiry"] = 0
	print("[CooldownService] Lock liberado -> Peer: ", peer_id, " | Slot: ", slot_index)
	rpc_id(peer_id, "_rpc_cooldown_state", slot_index, 0.0)


## Inicia cooldown normal. Libera el lock si estaba activo.
func start(peer_id: int, slot_index: int, duration: float) -> void:
	if not multiplayer.is_server():
		return
	_ensure(peer_id, slot_index)
	_cooldowns[peer_id][slot_index]["lock"] = false
	_cooldowns[peer_id][slot_index]["expiry"] = Time.get_ticks_msec() + int(duration * 1000)
	print("[CooldownService] Cooldown iniciado -> Peer: ", peer_id, " | Slot: ", slot_index, " | Duración: ", duration, "s")
	rpc_id(peer_id, "_rpc_cooldown_state", slot_index, duration)


## True si el slot está listo (sin lock y sin cooldown pendiente).
func is_ready(peer_id: int, slot_index: int) -> bool:
	if not _cooldowns.has(peer_id):
		return true
	if not _cooldowns[peer_id].has(slot_index):
		return true
	var state = _cooldowns[peer_id][slot_index]
	if state["lock"]:
		return false
	if state["expiry"] == 0:
		return true
	return Time.get_ticks_msec() >= state["expiry"]


## Tiempo restante en segundos. Devuelve -1.0 si está en lock.
func get_remaining(peer_id: int, slot_index: int) -> float:
	if not _cooldowns.has(peer_id) or not _cooldowns[peer_id].has(slot_index):
		return 0.0
	var state = _cooldowns[peer_id][slot_index]
	if state["lock"]:
		return -1.0
	if state["expiry"] == 0:
		return 0.0
	var remaining_ms = state["expiry"] - Time.get_ticks_msec()
	return maxf(remaining_ms / 1000.0, 0.0)


## Limpia todos los cooldowns de un jugador.
func clear_player(peer_id: int) -> void:
	if _cooldowns.has(peer_id):
		_cooldowns.erase(peer_id)
		for slot in range(5):
			rpc_id(peer_id, "_rpc_cooldown_state", slot, 0.0)
		print("[CooldownService] Cooldowns limpiados para peer: ", peer_id)


func _exit_tree() -> void:
	_cooldowns.clear()


# ── RPC AL CLIENTE ──────────────────────────────────────────────────────────
# duration > 0  → cooldown normal con timer
# duration = 0  → listo (sin cooldown)
# duration < 0  → lock activo (indefinido, sin timer visible)

@rpc("authority", "call_local", "reliable")
func _rpc_cooldown_state(slot_index: int, duration: float) -> void:
	var huds = get_tree().get_nodes_in_group("game_hud")
	if huds.is_empty():
		for i in range(3):
			await get_tree().process_frame
			huds = get_tree().get_nodes_in_group("game_hud")
			if not huds.is_empty():
				break
	if huds.is_empty():
		push_warning("[CooldownService] HUD no encontrado para actualizar cooldown.")
		return
	var hud = huds[0]
	if not hud.has_method("on_cooldown_state_changed"):
		return
	hud.on_cooldown_state_changed(slot_index, duration)
