# AbilityBase.gd
# Clase base que toda habilidad debe extender.
# Extiende RefCounted — sin nodos, sin add_child/queue_free.
# Si la habilidad necesita instanciar una escena (proyectil, VFX, área),
# lo hace dentro de activate() usando data.ability_scene y el árbol del player.
extends RefCounted
class_name AbilityBase

## Método principal — cada habilidad sobreescribe esto.
## player_node : el CharacterBody2D del jugador que usó la habilidad
## data        : AbilityData del slot usado (puede ser la versión evolucionada)
## direction   : Vector2 normalizado hacia donde apunta el jugador
## slot_index  : índice del slot en ability_slots (útil para animaciones y cooldowns)
func activate(_player_node: Node, _data: AbilityData, _direction: Vector2, _slot_index: int = -1) -> void:
	push_warning("[AbilityBase] activate() no implementado en ", get_script().resource_path)

## Sobreescribir en habilidades que ignoran el stun
func can_use_while_stunned() -> bool:
	return false

## Sobreescribir en habilidades que se pueden usar estando caído/muerto
func can_use_while_dead() -> bool:
	return false
