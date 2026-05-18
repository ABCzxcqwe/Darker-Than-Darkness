# res://services/ReviveService.gd
# Gestiona las sesiones de rescate entre survivors.
# Solo el servidor ejecuta la lógica.
# Se accede via: GameServiceLocator.get_service("ReviveService")
extends Node

# { rescuer_peer_id: { "target": Node, "timer": float, "duration": float } }
var _sessions: Dictionary = {}


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	for rescuer_id in _sessions.keys():
		var session: Dictionary = _sessions[rescuer_id]
		var rescuer_node: Node  = _get_player(rescuer_id)
		var target_node: Node   = session["target"]

		# Validar que ambos nodos sigan existiendo
		if not is_instance_valid(rescuer_node) or not is_instance_valid(target_node):
			_cancel(rescuer_id, false)
			continue

		# Verificar distancia — cancela si se alejan demasiado
		var _range: float = target_node.character_data.revive_range \
			if target_node.character_data else 80.0
		var dist: float = rescuer_node.global_position.distance_to(target_node.global_position)
		if dist > _range:
			print("[ReviveService] ", rescuer_id, " se alejó demasiado. Cancelando.")
			_cancel(rescuer_id, true)
			continue

		# Avanzar temporizador
		session["timer"] -= delta
		if session["timer"] <= 0.0:
			_complete(rescuer_id, target_node)


# ── API pública ────────────────────────────────────────────────────────

## Inicia una sesión de rescate.
## Llamado desde Player via RPC al servidor.
func request_revive(rescuer_node: Node, target_node: Node) -> void:
	if not multiplayer.is_server():
		return

	var rescuer_id: int = rescuer_node.get_multiplayer_authority()
	var target_id:  int = target_node.get_multiplayer_authority()

	# Validaciones
	var health_svc := GameServiceLocator.get_service("HealthService")
	if not health_svc:
		return

	if not health_svc.is_alive(rescuer_id):
		print("[ReviveService] Rescatador ", rescuer_id, " no está vivo.")
		return

	if not health_svc.is_downed(target_id):
		print("[ReviveService] Target ", target_id, " no está caído.")
		return

	if _sessions.has(rescuer_id):
		print("[ReviveService] ", rescuer_id, " ya está rescatando.")
		return

	# Verificar rango inicial
	var _range: float = target_node.character_data.revive_range \
		if target_node.character_data else 80.0
	var dist: float = rescuer_node.global_position.distance_to(target_node.global_position)
	if dist > _range:
		print("[ReviveService] ", rescuer_id, " demasiado lejos para rescatar.")
		return

	# Iniciar sesión
	var duration: float = target_node.character_data.revive_time \
		if target_node.character_data else 3.0

	_sessions[rescuer_id] = {
		"target"  : target_node,
		"timer"   : duration,
		"duration": duration,
	}

	print("[ReviveService] ", rescuer_id, " rescatando a ", target_id,
		  " | duración: ", duration, "s")

	# Notificar a todos los clientes (para UI futura)
	rpc("_notify_revive_started", rescuer_id, target_id, duration)


## Cancela una sesión de rescate activa.
## Llamado cuando el rescatador suelta la tecla o recibe daño.
func cancel_revive(rescuer_id: int) -> void:
	if not _sessions.has(rescuer_id):
		return
	_cancel(rescuer_id, true)


## Devuelve true si el jugador está rescatando activamente.
func is_reviving(rescuer_id: int) -> bool:
	return _sessions.has(rescuer_id)


# ── Internos ───────────────────────────────────────────────────────────

func _complete(rescuer_id: int, target_node: Node) -> void:
	var target_id: int = target_node.get_multiplayer_authority()
	_sessions.erase(rescuer_id)

	var health_svc := GameServiceLocator.get_service("HealthService")
	if health_svc:
		health_svc.revive(target_node)

	print("[ReviveService] ¡Rescate completado! ", rescuer_id, " levantó a ", target_id)
	rpc("_notify_revive_completed", rescuer_id, target_id)


func _cancel(rescuer_id: int, notify: bool) -> void:
	_sessions.erase(rescuer_id)
	print("[ReviveService] Rescate cancelado para ", rescuer_id)
	if notify:
		rpc("_notify_revive_cancelled", rescuer_id)


func _get_player(peer_id: int) -> Node:
	return get_tree().root.find_child(str(peer_id), true, false)


# ── RPCs de notificación (para UI futura) ─────────────────────────────

@rpc("authority", "call_local", "reliable")
func _notify_revive_started(rescuer_id: int, target_id: int, duration: float) -> void:
	print("[ReviveService] Rescate iniciado | rescatador:", rescuer_id,
		  " | target:", target_id, " | duración:", duration)
	# TODO: mostrar barra de progreso sobre el target


@rpc("authority", "call_local", "reliable")
func _notify_revive_cancelled(rescuer_id: int) -> void:
	print("[ReviveService] Rescate cancelado | rescatador:", rescuer_id)
	# TODO: ocultar barra de progreso


@rpc("authority", "call_local", "reliable")
func _notify_revive_completed(rescuer_id: int, target_id: int) -> void:
	print("[ReviveService] Rescate completado | rescatador:", rescuer_id,
		  " | target:", target_id)
	# TODO: efecto visual de levantarse


func _exit_tree() -> void:
	_sessions.clear()
	print("[ReviveService] Limpiado.")
