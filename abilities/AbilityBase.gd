extends RefCounted
class_name AbilityBase

## El Router asigna esto ANTES de llamar activate() si viene de un menú contextual.
## -1 = sin target pendiente (activación directa o vía dirección).
## >0 = peer_id del objetivo seleccionado en el menú contextual.
var pending_target_peer: int = -1

func activate(_player_node: Node, _data: AbilityData, _direction: Vector2, _slot_index: int = -1) -> void:
	push_warning("[AbilityBase] activate() no implementado en ", get_script().resource_path)

func can_use_while_stunned() -> bool:
	return false

func can_use_while_dead() -> bool:
	return false

## Virtuales para cancelación de habilidades canalizadas (ej: Lanza).
## Default: no cancelable / cancel inmediato. Override en habilidades que necesitan grace period.
func can_cancel_now() -> bool:
	return true

func cancel_early() -> void:
	push_warning("[AbilityBase] cancel_early() no implementado en ", get_script().resource_path)

# ── Registro central de instancias activas (genérico, evita hardcode LanzaAbility en Router) ──
static var _active_registry: Dictionary = {} # "peer_slot" -> WeakRef

static func _registry_key(peer_id: int, slot_index: int) -> String:
	return "%d_%d" % [peer_id, slot_index]

static func register_active(peer_id: int, slot_index: int, instance: AbilityBase) -> void:
	_active_registry[_registry_key(peer_id, slot_index)] = weakref(instance)

static func unregister_active(peer_id: int, slot_index: int) -> void:
	_active_registry.erase(_registry_key(peer_id, slot_index))

static func find_active_for(player_node: Node, slot_index: int) -> AbilityBase:
	if not is_instance_valid(player_node):
		return null
	var peer_id: int = player_node.get_multiplayer_authority()
	var key: String = _registry_key(peer_id, slot_index)
	if not _active_registry.has(key):
		return null
	var ref = _active_registry[key]
	var inst = ref.get_ref() if ref else null
	if not is_instance_valid(inst):
		_active_registry.erase(key)
		return null
	return inst

static func find_active_for_peer(peer_id: int, slot_index: int) -> AbilityBase:
	var key: String = _registry_key(peer_id, slot_index)
	if not _active_registry.has(key):
		return null
	var ref = _active_registry[key]
	var inst = ref.get_ref() if ref else null
	if not is_instance_valid(inst):
		_active_registry.erase(key)
		return null
	return inst
