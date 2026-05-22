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
	# 1. Buscamos el HUD en el grupo oficial
	var huds = get_tree().get_nodes_in_group("game_hud")
	
	# ─── AQUÍ ESTÁ LA SOLUCIÓN ASÍNCRONA ───
	# Si el HUD no está en el grupo, esperamos un par de frames a que aparezca
	if huds.is_empty():
		# Intentamos esperar hasta 3 frames de manera segura
		for i in range(3):
			await get_tree().process_frame
			huds = get_tree().get_nodes_in_group("game_hud")
			if not huds.is_empty():
				break # ¡Súper! El HUD apareció
				
	# Si después de esperar sigue sin aparecer, tiramos el warning original
	if huds.is_empty():
		push_warning("[CooldownService] RPC recibido en cliente, pero no se encontró el HUD local tras esperar.")
		return
	# ───────────────────────────────────────

	# 2. Si lo encuentra (ya sea de inmediato o tras esperar), despachamos el cooldown
	var hud = huds[0]
	if hud.has_method("on_cooldown_started"):
		hud.on_cooldown_started(ability_name, slot_index, duration)


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
