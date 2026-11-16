class_name AbilityContext
extends RefCounted
## Cancelación, menú contextual y filtros de animación de una habilidad.

const TAG := "AbilityContext"

var _router: Node
var _fase2: AbilityFase2


func _init(router: Node, fase2: AbilityFase2) -> void:
	_router = router
	_fase2 = fase2


## Cancelación de habilidad activa (toggle del mismo botón).
func maybe_cancel_active_ability(peer_id: int, player_node: Node, slot_index: int, base_data: AbilityData) -> bool:
	if not base_data.can_cancel:
		return false
	if player_node.state != 2 or player_node.active_ability_slot != slot_index:
		return false

	var ability: AbilityBase = AbilityBase.find_active_for(player_node, slot_index)
	if not ability:
		# Fallback legacy para instancias que aún no registran en AbilityBase.
		ability = LanzaAbility.find_active_for(player_node, slot_index) if LanzaAbility else null
	if not ability:
		return false

	if ability.has_method("can_cancel_now") and not ability.can_cancel_now():
		NetLog.debug(TAG, "Cancel bloqueado por grace period | peer: %d | slot: %d" % [peer_id, slot_index])
		return true

	ability.cancel_early()
	NetLog.debug(TAG, "Habilidad activa cancelada con la misma tecla | peer: %d | slot: %d" % [peer_id, slot_index])
	return true


func handle_animation_state(
	peer_id: int,
	player_node: Node,
	slot_index: int,
	base_data: AbilityData,
	cd: Node
) -> bool:
	var anim_state: int = player_node.state

	# Fase 2: la entrada no deja al jugador en estado ABILITY/PREPARE bloqueante.
	if _fase2.get_active_fase2_slot(peer_id) == slot_index:
		return false

	if anim_state == 1:  # PREPARE
		cancel_ability(peer_id, player_node, slot_index, base_data, cd)
		return true

	if anim_state == 2:  # ABILITY
		if slot_index == player_node.active_ability_slot and base_data.can_cancel:
			var ability: AbilityBase = AbilityBase.find_active_for(player_node, slot_index)
			if not ability:
				ability = LanzaAbility.find_active_for(player_node, slot_index) if LanzaAbility else null
			if ability and ability.has_method("can_cancel_now") and not ability.can_cancel_now():
				NetLog.debug(TAG, "Cancel via animación bloqueado por grace | peer: %d" % peer_id)
				return true
			cancel_ability(peer_id, player_node, slot_index, base_data, cd)
		else:
			NetLog.debug(TAG, "Habilidad en curso no cancelable o slot diferente.")
		return true

	return false


func handle_context_menu(
	peer_id: int,
	player_node: Node,
	slot_index: int,
	ability_data: AbilityData,
	pending_target: int
) -> bool:
	if ability_data.requires_selection and pending_target == -1:
		open_context_menu(peer_id, player_node, slot_index, ability_data)
		return true
	return false


func open_context_menu(peer_id: int, player_node: Node, slot_index: int, ability_data: AbilityData) -> void:
	player_node.rpc_id(
		peer_id,
		"_open_ability_selection",
		slot_index,
		ability_data.display_name,
		ability_data.selection_type
	)
	NetLog.debug(TAG, "Menú contextual abierto | peer: %d | slot: %d | tipo: %s" % [
		peer_id, slot_index, ability_data.selection_type
	])


func cancel_ability(
	peer_id: int,
	player_node: Node,
	slot_index: int,
	ability_data: AbilityData,
	cd: Node
) -> void:
	var combat = GameServiceLocator.combat_mediator
	if combat:
		combat.remove_root(player_node)

	if cd and cd.has_method("release_lock"):
		cd.release_lock(peer_id, slot_index)

	if cd and cd.has_method("start") and ability_data.cooldown_cancel > 0.0:
		cd.start(peer_id, slot_index, ability_data.cooldown_cancel)

	if ability_data.requires_selection and player_node.state == 2:
		var huds = player_node.get_tree().get_nodes_in_group(GroupNames.GAME_HUD)
		if not huds.is_empty() and huds[0].has_method("cancel_selection"):
			huds[0].cancel_selection()

	player_node.rpc("_sync_cancel_ability")
	NetLog.debug(TAG, "Habilidad cancelada | peer: %d | slot: %d | nombre: %s" % [
		peer_id, slot_index, ability_data.display_name
	])
