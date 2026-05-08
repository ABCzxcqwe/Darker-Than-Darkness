# CooldownService.gd
# Gestiona cooldowns por jugador y por nombre de habilidad.
# Corre SOLO en el servidor. Al iniciar un cooldown notifica
# automáticamente al cliente via RPC para que el HUD lo refleje.
#
# Uso (desde un script de habilidad):
#   var cd := GameServiceLocator.get_service("CooldownService")
#   cd.start(peer_id, "SlashAbility", 15.0)          # cooldown fijo
#   cd.start(peer_id, "SlashAbility", duracion_var)   # cooldown variable
#
# El cliente NO necesita llamar a start() — recibe _rpc_cooldown_started()
# automáticamente y AbilityButton lo toma desde ahí.
extends Node

# { peer_id: { ability_name: expiry_timestamp_ms } }
var _cooldowns: Dictionary = {}


# ── API pública ────────────────────────────────────────────────────────

## Inicia el cooldown de una habilidad para un jugador.
## duration en segundos — puede ser cualquier valor, lo decide la habilidad.
## slot_index es necesario para que el HUD sepa qué botón actualizar.
func start(peer_id: int, ability_name: String, duration: float, slot_index: int = -1) -> void:
	if not _cooldowns.has(peer_id):
		_cooldowns[peer_id] = {}
	var expiry := Time.get_ticks_msec() + int(duration * 1000)
	_cooldowns[peer_id][ability_name] = expiry

	print("[CooldownService] ", peer_id, " | ", ability_name,
		  " | slot: ", slot_index, " | cooldown: ", duration, "s")

	# Notificar al cliente para que el HUD muestre el cooldown
	if multiplayer.is_server() and peer_id != 1:
		rpc_id(peer_id, "_rpc_cooldown_started", ability_name, slot_index, duration)
	elif multiplayer.is_server() and peer_id == 1:
		# El servidor es también cliente local (peer 1 = host)
		_rpc_cooldown_started(ability_name, slot_index, duration)


## Devuelve true si la habilidad está lista (sin cooldown activo).
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
	return remaining_ms / 1000.0


## Limpia todos los cooldowns de un jugador (útil al morir o salir).
func clear_player(peer_id: int) -> void:
	_cooldowns.erase(peer_id)
	print("[CooldownService] Cooldowns limpiados para peer ", peer_id)


## Limpia todo al destruirse el World.
func _exit_tree() -> void:
	_cooldowns.clear()
	print("[CooldownService] Limpiado.")


# ── RPC al cliente ─────────────────────────────────────────────────────

## Recibido en el CLIENTE. Le dice al HUD que inicie el cooldown visual.
## ability_name y slot_index identifican el botón. duration es la duración real.
@rpc("authority", "reliable")
func _rpc_cooldown_started(ability_name: String, slot_index: int, duration: float) -> void:
	# Buscar el HUD activo en la escena local
	var hud := _find_local_hud()
	if hud and hud.has_method("on_cooldown_started"):
		hud.on_cooldown_started(ability_name, slot_index, duration)


func _find_local_hud() -> Node:
	# El HUD se llama "GameHud" y está en el árbol principal
	var results := get_tree().get_nodes_in_group("game_hud")
	if results.size() > 0:
		return results[0]
	return null
