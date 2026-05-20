# res://services/CooldownService.gd
# Gestiona cooldowns por jugador y por nombre de habilidad.
# La lógica de control corre SOLO en el servidor. Al iniciar un cooldown,
# notifica automáticamente al cliente vía RPC para que su HUD local lo refleje.
extends Node

# { peer_id: { ability_name: expiry_timestamp_ms } }
var _cooldowns: Dictionary = {}


# ── API PÚBLICA (SOLO SERVIDOR) ────────────────────────────────────────

## Inicia el cooldown de una habilidad para un jugador.
## duration en segundos — puede ser cualquier valor, lo decide la habilidad.
## slot_index es necesario para que el HUD sepa qué botón actualizar.
func start(peer_id: int, ability_name: String, duration: float, slot_index: int = -1) -> void:
	if not multiplayer.is_server():
		return
		
	if not _cooldowns.has(peer_id):
		_cooldowns[peer_id] = {}
		
	var expiry := Time.get_ticks_msec() + int(duration * 1000)
	_cooldowns[peer_id][ability_name] = expiry

	print("[CooldownService] Cooldown iniciado -> Peer: ", peer_id, " | Habilidad: ", ability_name, " | Slot: ", slot_index, " | Duración: ", duration, "s")
	
	# Enviamos la señal visual de forma segura únicamente al cliente que le corresponde
	rpc_id(peer_id, "_rpc_cooldown_started", ability_name, slot_index, duration)


## Devuelve true si la habilidad está lista para usarse (el cooldown expiró o no existe).
func is_ready(peer_id: int, ability_name: String) -> bool:
	if not _cooldowns.has(peer_id):
		return true
	if not _cooldowns[peer_id].has(ability_name):
		return true
	return Time.get_ticks_msec() >= _cooldowns[peer_id][ability_name]


## Tiempo restante en segundos. Devuelve 0.0 si está listo.
func get_remaining(peer_id: int, ability_name: String) -> float:
	if is_ready(peer_id, ability_name):
		return 0.0
	var remaining_ms: int = _cooldowns[peer_id][ability_name] - Time.get_ticks_msec()
	return maxf(remaining_ms / 1000.0, 0.0)


## Limpia todos los cooldowns de un jugador (útil al desconectarse o morir).
func clear_player(peer_id: int) -> void:
	if _cooldowns.has(peer_id):
		_cooldowns.erase(peer_id)
		print("[CooldownService] Cooldowns limpiados en el servidor para peer: ", peer_id)


## Limpia todo al destruirse el servicio.
func _exit_tree() -> void:
	_cooldowns.clear()
	print("[CooldownService] Destruido y memoria liberada.")


# ── RPC AL CLIENTE (PROTEGIDO CONTRA HEADLESS) ──────────────────────────

## Recibido en el CLIENTE correspondiente. Le dice a su HUD que inicie la animación.
@rpc("authority", "call_local", "reliable")
func _rpc_cooldown_started(ability_name: String, slot_index: int, duration: float) -> void:
	# COMPUERTA CRÍTICA: Si este código se intenta ejecutar en un servidor dedicado sin UI, abortamos.
	if multiplayer.is_server() and DisplayServer.get_name() == "headless":
		return

	# Buscar el HUD activo en la escena local de este cliente
	var hud := _find_local_hud()
	if hud:
		if hud.has_method("start_cooldown"):
			hud.start_cooldown(ability_name, slot_index, duration)
		else:
			# Fallback por si tus botones de habilidad escuchan directamente de forma individual
			var btn = hud.find_child("AbilityButton_" + str(slot_index), true, false)
			if btn and btn.has_method("start_cooldown"):
				btn.start_cooldown(duration)
	else:
		push_warning("[CooldownService] RPC recibido en cliente, pero no se encontró el HUD local en el árbol.")


## Helper para localizar la interfaz sin generar dependencias duras en el servidor
func _find_local_hud() -> Node:
	# Buscamos en el árbol de manera dinámica (solo clientes llegarán aquí)
	var current_scene = get_tree().current_scene
	if not current_scene:
		return null
		
	# Opción A: Buscar por grupo (la más recomendada y óptima)
	var huds = get_tree().get_nodes_in_group("hud")
	if huds.size() > 0:
		return huds[0]
		
	# Opción B: Fallback por nombre directo en la raíz de la escena actual
	var hud_node = current_scene.find_child("UI", true, false)
	if not hud_node:
		hud_node = current_scene.find_child("HUD", true, false)
		
	return hud_node
