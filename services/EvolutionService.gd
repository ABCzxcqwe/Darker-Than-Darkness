# EvolutionService.gd
# Servicio de evolución de habilidades — se registra en GameServices.tres como ServiceEntry.
# Se accede via: GameServiceLocator.get_service("EvolutionService")
#
# Dos caminos para evolucionar un slot:
#   1. TPService lo llama cuando el TP acumulado alcanza el tp_cost del slot
#   2. La habilidad de un aliado llama a evolve_slot() directamente
#
# Regla de limpieza al usar un slot evolucionado:
#   Slots 1 y 3 están vinculados — al usar cualquiera de los dos, ambos se limpian
#   Slots 0, 2 y 4 se limpian solos al usarse
extends Node

# { peer_id: Array[bool] } — 5 elementos, índice = slot (0=M1, 1-4=habilidades)
var _evolved_slots: Dictionary = {}

# Emitida cuando un slot evoluciona — el HUD puede escuchar esto para actualizar íconos
signal slot_evolved(peer_id: int, slot_index: int)

# Emitida cuando un slot vuelve a la normalidad
signal slot_devolved(peer_id: int, slot_index: int)

# =========================================================
# REGISTRO DE JUGADORES
# =========================================================

func register_player(peer_id: int) -> void:
	_evolved_slots[peer_id] = [false, false, false, false, false]

func unregister_player(peer_id: int) -> void:
	_evolved_slots.erase(peer_id)

# =========================================================
# API PÚBLICA
# =========================================================

## Evoluciona un slot. Llamado por TPService o por una habilidad aliada.
func evolve_slot(peer_id: int, slot_index: int) -> void:
	if not _evolved_slots.has(peer_id):
		push_warning("[EvolutionService] peer_id ", peer_id, " no registrado.")
		return
	if slot_index < 0 or slot_index > 4:
		push_warning("[EvolutionService] slot_index fuera de rango: ", slot_index)
		return
	if _evolved_slots[peer_id][slot_index]:
		return  # ya está evolucionado, no hacer nada
	_evolved_slots[peer_id][slot_index] = true
	slot_evolved.emit(peer_id, slot_index)
	print("[EvolutionService] Slot ", slot_index, " evolucionado para peer ", peer_id)

## Devuelve true si el slot está actualmente evolucionado
func is_evolved(peer_id: int, slot_index: int) -> bool:
	if not _evolved_slots.has(peer_id):
		return false
	return _evolved_slots[peer_id][slot_index]

## Llamado por AbilityRouter justo después de activar una habilidad evolucionada
func consume_evolution(peer_id: int, slot_index: int) -> void:
	if not _evolved_slots.has(peer_id):
		return
	if not _evolved_slots[peer_id][slot_index]:
		return

	# Slots 1 y 3 están vinculados — limpiar ambos
	if slot_index == 1 or slot_index == 3:
		_clear_slot(peer_id, 1)
		_clear_slot(peer_id, 3)
	else:
		_clear_slot(peer_id, slot_index)

## Limpia todas las evoluciones de un jugador (fin de ronda, muerte, etc.)
func clear_all(peer_id: int) -> void:
	if not _evolved_slots.has(peer_id):
		return
	for i in 5:
		if _evolved_slots[peer_id][i]:
			_clear_slot(peer_id, i)

# =========================================================
# HELPERS
# =========================================================
func _clear_slot(peer_id: int, slot_index: int) -> void:
	if not _evolved_slots[peer_id][slot_index]:
		return
	_evolved_slots[peer_id][slot_index] = false
	slot_devolved.emit(peer_id, slot_index)
	print("[EvolutionService] Slot ", slot_index, " devuelto a normal para peer ", peer_id)
