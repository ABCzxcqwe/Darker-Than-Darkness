# res://services/EvolutionService.gd
# Servicio de evolución de habilidades — se registra en GameServices.tres.
# Controla qué habilidades están potenciadas y sincroniza los cambios con el cliente.
#
# REGLA DE CONSUMO VINCULADA:
#   Slots 1 y 3 están unidos. Al consumir uno, AMBOS se limpian automáticamente.
#   Slots 0, 2 y 4 son completamente independientes.
extends Node

# Emitida en el servidor cuando un slot cambia de estado (útil para otros servicios lógicos)
signal slot_evolved(peer_id: int, slot_index: int)
signal slot_devolved(peer_id: int, slot_index: int)

# { peer_id: Array[bool] } — Cada jugador tiene un arreglo de 5 posiciones (slots 0 a 4)
var _evolved_slots: Dictionary = {}


# =======================================================================
# REGISTRO DE JUGADORES (SOLO SERVIDOR)
# =======================================================================

func register_player(peer_id: int, _data: Resource = null) -> void:
	if not multiplayer.is_server():
		return
	_evolved_slots[peer_id] = [false, false, false, false, false]
	print("[EvolutionService] Jugador ", peer_id, " registrado en el sistema de evolución.")


func unregister_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _evolved_slots.has(peer_id):
		_evolved_slots.erase(peer_id)
		print("[EvolutionService] Datos de evolución eliminados para peer: ", peer_id)


# =======================================================================
# API PÚBLICA (LLAMADA DESDE EL SERVIDOR)
# =======================================================================

## Fuerza la evolución de un slot específico (por costo de TP o buff de aliado).
func evolve_slot(peer_id: int, slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	if not _evolved_slots.has(peer_id):
		return
	if slot_index < 0 or slot_index >= 5:
		return
		
	if _evolved_slots[peer_id][slot_index]:
		return # Ya está evolucionado, no hacemos nada
		
	_evolved_slots[peer_id][slot_index] = true
	slot_evolved.emit(peer_id, slot_index)
	print("[EvolutionService] ¡Slot ", slot_index, " EVOLUCIONADO! -> Peer: ", peer_id)
	
	# Sincronizar visual en el cliente dueño del personaje
	# Buscamos el Player node directamente para enviarle el RPC
	_sync_visual_to_client(peer_id, slot_index, true)


## Devuelve true si el slot está actualmente evolucionado en el servidor.
func is_evolved(peer_id: int, slot_index: int) -> bool:
	if not _evolved_slots.has(peer_id):
		return false
	if slot_index < 0 or slot_index >= 5:
		return false
	return _evolved_slots[peer_id][slot_index]


## Llamado por AbilityRouter inmediatamente después de ejecutar con éxito una habilidad evolucionada.
func consume_evolution(peer_id: int, slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	if not _evolved_slots.has(peer_id):
		return

	# APLICACIÓN DE LA REGLA VINCULADA: Slots 1 y 3
	if slot_index == 1 or slot_index == 3:
		print("[EvolutionService] Vínculo detectado (Slot ", slot_index, "). Limpiando Slots 1 y 3 para peer: ", peer_id)
		_clear_and_sync_slot(peer_id, 1)
		_clear_and_sync_slot(peer_id, 3)
	else:
		# Slots independientes (0, 2, 4)
		_clear_and_sync_slot(peer_id, slot_index)


## Limpia todas las evoluciones (al terminar la ronda, morir permanentemente, etc.)
func clear_all(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not _evolved_slots.has(peer_id):
		return
		
	for i in 5:
		_clear_and_sync_slot(peer_id, i)
	print("[EvolutionService] Todas las evoluciones reseteadas para peer: ", peer_id)


# =======================================================================
# MÉTODOS INTERNOS DE CONTROL
# =======================================================================

func _clear_and_sync_slot(peer_id: int, slot_index: int) -> void:
	if _evolved_slots[peer_id][slot_index]:
		_evolved_slots[peer_id][slot_index] = false
		slot_devolved.emit(peer_id, slot_index)
		
		_sync_visual_to_client(peer_id, slot_index, false)


# =======================================================================
# SINCRONIZACIÓN VISUAL AL CLIENTE (mismo patrón que CooldownService)
# =======================================================================

## Busca el Player node del peer y le envía un RPC para actualizar el
## visual de evolución en su HUD local.
func _sync_visual_to_client(peer_id: int, slot_index: int, evolved: bool) -> void:
	rpc_id(peer_id, "_rpc_evolve_slot", slot_index, evolved)


## Recibido en el cliente dueño del slot. Actualiza el HUD local.
@rpc("authority", "call_local", "reliable")
func _rpc_evolve_slot(slot_index: int, evolved: bool) -> void:
	var huds = get_tree().get_nodes_in_group("game_hud")
	if huds.is_empty():
		push_warning("[EvolutionService] RPC recibido en cliente, pero no se encontró el HUD local.")
		return
	var hud = huds[0]
	if evolved:
		if hud.has_method("visual_evolve_slot"):
			hud.visual_evolve_slot(slot_index)
	else:
		if hud.has_method("visual_devolve_slot"):
			hud.visual_devolve_slot(slot_index)
