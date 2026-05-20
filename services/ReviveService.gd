# res://services/ReviveService.gd
# Gestiona las sesiones de rescate entre survivors en el servidor.
# Cancela el progreso si se alejan, si reciben daño o si son aturdidos.
extends Node

# { rescuer_peer_id: { "target": Node, "timer": float, "duration": float } }
var _sessions: Dictionary = {}


func _ready() -> void:
	if multiplayer.is_server():
		# Conectamos con diferido para garantizar que los otros servicios ya existan en el Locator
		call_deferred("_connect_to_services")


func _connect_to_services() -> void:
	var health_svc = GameServiceLocator.get_service("HealthService")
	if health_svc:
		# Si tu HealthService no tiene esta señal, podemos interceptar vía el método take_damage o herencia.
		# Por ahora, escucharemos si el estado del jugador cambia a downed/dead para cancelar.
		print("[ReviveService] Conectado de forma segura a los servicios de control.")


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	# ────────────────────────────
	
	if not multiplayer.is_server():
		return

	for rescuer_id in _sessions.keys():
		var session: Dictionary = _sessions[rescuer_id]
		var rescuer_node: Node  = _get_player(rescuer_id)
		var target_node: Node   = session["target"]

		# 1. Validar que ambos nodos sigan siendo válidos en el árbol
		if not is_instance_valid(rescuer_node) or not is_instance_valid(target_node):
			_cancel(rescuer_id, true)
			continue

		# 2. VALIDACIÓN DE INTERRUPCIÓN POR ESTADOS (Stun, Root, Silenciado, Downed)
		if _is_player_interrupted(rescuer_id):
			print("[ReviveService] Rescate interrumpido por estado alterado/daño en peer: ", rescuer_id)
			_cancel(rescuer_id, true)
			continue

		# 3. Verificar distancia — cancela si se alejan demasiado
		var _range: float = target_node.character_data.revive_range if target_node.character_data else 80.0
		var dist: float = rescuer_node.global_position.distance_to(target_node.global_position)
		if dist > _range:
			print("[ReviveService] ", rescuer_id, " se alejó demasiado. Cancelando rescate.")
			_cancel(rescuer_id, true)
			continue

		# 4. Avanzar temporizador si todo está en orden
		session["timer"] -= delta
		if session["timer"] <= 0.0:
			_complete_revive(rescuer_id, target_node)


# ── API PÚBLICA (SOLO SERVIDOR) ────────────────────────────────────────

## Inicia una sesión de reanimación entre dos sobrevivientes
func start_revive(rescuer_id: int, target_node: Node) -> void:
	if not multiplayer.is_server():
		return
		
	if not is_instance_valid(target_node):
		return
		
	var target_id = target_node.get_multiplayer_authority()
	
	# Si el rescatador ya está reanimando a alguien, cancelamos la anterior
	if _sessions.has(rescuer_id):
		_cancel(rescuer_id, false)

	# Si el rescatador está aturdido o caído, no puede empezar a revivir
	if _is_player_interrupted(rescuer_id):
		return

	var duration: float = target_node.character_data.revive_time if target_node.character_data else 3.0
	
	_sessions[rescuer_id] = {
		"target": target_node,
		"timer": duration,
		"duration": duration
	}
	
	print("[ReviveService] Rescate iniciado -> Rescatador: ", rescuer_id, " | Objetivo: ", target_id)
	
	# Notificar de forma fiable a los clientes para activar la UI
	rpc("_notify_revive_started", rescuer_id, target_id, duration)


## Fuerza la cancelación externa (por ejemplo, llamada desde un hit de habilidad directo)
func force_cancel_by_hit(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Si el peer_id es un rescatador activo, lo cancelamos
	if _sessions.has(peer_id):
		print("[ReviveService] Cancelación forzada por impacto directo al peer: ", peer_id)
		_cancel(peer_id, true)


# ── LOGICA INTERNA DE CONTROL ─────────────────────────────────────────

func _complete_revive(rescuer_id: int, target_node: Node) -> void:
	var target_id = target_node.get_multiplayer_authority()
	_sessions.erase(rescuer_id)

	var health_svc = GameServiceLocator.get_service("HealthService")
	if health_svc:
		# Aquí puedes usar tu lógica de HealthService para revivir al jugador herido
		if health_svc.has_method("revive"):
			health_svc.revive(target_node)
		else:
			# Fallback directo si manejas el cambio de estado por sincronización
			if target_node.has_method("_sync_state"):
				var rev_hp = target_node.character_data.revive_health if target_node.character_data else 60
				target_node.rpc("_sync_state", "alive", rev_hp)

	print("[ReviveService] ¡Rescate completado! ", rescuer_id, " levantó a ", target_id)
	rpc("_notify_revive_completed", rescuer_id, target_id)


func _cancel(rescuer_id: int, notify: bool) -> void:
	if not _sessions.has(rescuer_id):
		return
		
	_sessions.erase(rescuer_id)
	print("[ReviveService] Rescate cancelado para el peer: ", rescuer_id)
	
	if notify:
		rpc("_notify_revive_cancelled", rescuer_id)


## Helper para comprobar si el jugador está incapacitado en otros servicios
func _is_player_interrupted(peer_id: int) -> bool:
	# 1. Verificar si fue derribado (Downed) o muerto según HealthService
	var health_svc = GameServiceLocator.get_service("HealthService")
	if health_svc:
		if health_svc.is_downed(peer_id) or health_svc.is_dead(peer_id):
			return true

	# 2. Verificar si está bajo efectos de control (Stun o Root)
	var status_svc = GameServiceLocator.get_service("StatusEffectService")
	if status_svc:
		if status_svc.has_method("is_stunned") and status_svc.is_stunned(peer_id):
			return true
		if status_svc.has_method("has_effect") and status_svc.has_effect(peer_id, "stun"):
			return true
			
	return false


func _get_player(peer_id: int) -> Node:
	return get_tree().root.find_child(str(peer_id), true, false)


# ── RPCs DE SINCRONIZACIÓN VISUAL (EJECUTADOS EN CLIENTES) ─────────────

@rpc("authority", "call_local", "reliable")
func _notify_revive_started(rescuer_id: int, target_id: int, _duration: float) -> void:
	print("[ReviveService] RPC: Rescate iniciado | Rescatador: ", rescuer_id, " -> Objetivo: ", target_id)
	# TODO: Aquí tu UI/HUD local puede escuchar esto para pintar una barra de casteo sobre el jugador
	# Ejemplo: CustomHUD.show_revive_bar(rescuer_id, duration)


@rpc("authority", "call_local", "reliable")
func _notify_revive_cancelled(rescuer_id: int) -> void:
	print("[ReviveService] RPC: Rescate cancelado | Rescatador: ", rescuer_id)
	# TODO: Ocultar barra de progreso en los clientes de inmediato
	# Ejemplo: CustomHUD.hide_revive_bar(rescuer_id)


@rpc("authority", "call_local", "reliable")
func _notify_revive_completed(rescuer_id: int, target_id: int) -> void:
	print("[ReviveService] RPC: Rescate exitoso | ", rescuer_id, " salvó a ", target_id)
	# TODO: Limpiar UI y lanzar efectos visuales o partículas de éxito

func cancel_revive(peer_id: int) -> void:
	# Redirige el llamado antiguo a nuestra nueva lógica de interrupción por impacto
	force_cancel_by_hit(peer_id)
