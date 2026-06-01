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
