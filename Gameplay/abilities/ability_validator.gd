class_name AbilityValidator
extends RefCounted
## Validaciones server-side de una petición de habilidad.

const TAG := "AbilityValidator"

var _router: Node
var _tp: AbilityTp


func _init(router: Node, tp: AbilityTp) -> void:
	_router = router
	_tp = tp


func validate_game_active() -> bool:
	var state = GameServiceLocator.game_state
	return state != null and state.is_in_game()


func validate_player(peer_id: int) -> Node:
	var player_node = _router._get_player_node(peer_id)
	if not player_node:
		NetLog.warn(TAG, "Jugador no encontrado para peer %d." % peer_id)
	return player_node


func validate_character_data(player_node: Node, peer_id: int) -> CharacterData:
	var char_data: CharacterData = player_node.character_data
	if not char_data:
		NetLog.warn(TAG, "Jugador %d sin character_data." % peer_id)
	return char_data


func validate_alive(player_node: Node) -> bool:
	if player_node.health <= 0:
		return false
	if player_node.health_state != "alive":
		return false
	return true


func validate_slot(slot_index: int, char_data: CharacterData, _peer_id: int) -> AbilityData:
	if slot_index < 0 or slot_index >= char_data.ability_slots.size():
		NetLog.warn(TAG, "Slot %d fuera de rango." % slot_index)
		return null
	var base_data: AbilityData = char_data.ability_slots[slot_index]
	if not base_data:
		return null
	return base_data


func resolve_ability_version(
	peer_id: int,
	slot_index: int,
	base_data: AbilityData,
	evolution_service: Node,
	lms_svc: Node
) -> Dictionary:
	var stage: int = evolution_service.get_evolved_stage(peer_id, slot_index) if evolution_service else 0
	var lms_wants_evolve: bool = false

	if stage <= 0 and base_data.lms_auto_evolve and base_data.evolved_version:
		if lms_svc and lms_svc.is_lms_active():
			var lms_survivor = lms_svc.get_active_survivor()
			if lms_survivor and PlayerLifecycleManager.get_owner_peer_id(lms_survivor) == peer_id:
				lms_wants_evolve = true
	if lms_wants_evolve:
		stage = 1

	# Camina la cadena evolved_version `stage` veces (soporta multi-hop).
	var ability_data: AbilityData = base_data
	for i in range(stage):
		if ability_data and ability_data.evolved_version:
			ability_data = ability_data.evolved_version
		else:
			break

	var is_evolved: bool = stage > 0 and ability_data != base_data
	return {
		"ability_data": ability_data,
		"is_evolved": is_evolved,
		"lms_wants_evolve": lms_wants_evolve,
	}


func validate_cooldown(peer_id: int, slot_index: int, cd: Node) -> bool:
	if cd and not cd.is_ready(peer_id, slot_index):
		NetLog.debug(TAG, "Bloqueado por cooldown/lock | slot: %d | restante: %ss" % [
			slot_index, cd.get_remaining(peer_id, slot_index)
		])
		return false
	return true


func validate_status_effects(peer_id: int, base_data: AbilityData, status: Node) -> bool:
	if status:
		if status.is_silenced(peer_id):
			NetLog.debug(TAG, "Bloqueado por silence.")
			return false
		if status.is_stunned(peer_id) and not base_data.can_use_while_stunned:
			NetLog.debug(TAG, "Bloqueado por stun.")
			return false
	return true


func validate_tp(
	peer_id: int,
	ability_data: AbilityData,
	slot_index: int,
	base_data: AbilityData,
	abs_svc: Node,
	lms_svc: Node,
	is_evolved: bool,
	lms_wants_evolve: bool
) -> Dictionary:
	var effective_tp_cost: float = _tp.resolve_tp_cost(ability_data, peer_id, slot_index, abs_svc)

	if effective_tp_cost <= 0.0:
		return {"valid": true, "ability_data": ability_data, "is_evolved": is_evolved, "lms_wants_evolve": lms_wants_evolve}

	var tp_svc = GameServiceLocator.tp
	if tp_svc and tp_svc.get_tp_for_peer(peer_id) < effective_tp_cost:
		var is_permanent: bool = base_data.evolved_version != null and base_data.evolved_version.evolution_consume == 1

		if is_permanent:
			return {"valid": false, "ability_data": ability_data, "is_evolved": is_evolved, "lms_wants_evolve": lms_wants_evolve}

		if lms_wants_evolve:
			is_evolved = false
			lms_wants_evolve = false
			ability_data = base_data
			effective_tp_cost = _tp.resolve_tp_cost(base_data, peer_id, slot_index, abs_svc)
			if tp_svc.get_tp_for_peer(peer_id) < effective_tp_cost:
				return {"valid": false, "ability_data": ability_data, "is_evolved": is_evolved, "lms_wants_evolve": lms_wants_evolve}
		elif is_evolved and base_data.lms_auto_evolve and base_data.evolved_version:
			if lms_svc and lms_svc.is_lms_active():
				var lms_survivor = lms_svc.get_active_survivor()
				if lms_survivor and PlayerLifecycleManager.get_owner_peer_id(lms_survivor) == peer_id:
					is_evolved = false
					ability_data = base_data
					effective_tp_cost = _tp.resolve_tp_cost(base_data, peer_id, slot_index, abs_svc)
					if tp_svc.get_tp_for_peer(peer_id) < effective_tp_cost:
						return {"valid": false, "ability_data": ability_data, "is_evolved": is_evolved, "lms_wants_evolve": lms_wants_evolve}
		else:
			return {"valid": false, "ability_data": ability_data, "is_evolved": is_evolved, "lms_wants_evolve": lms_wants_evolve}

	return {"valid": true, "ability_data": ability_data, "is_evolved": is_evolved, "lms_wants_evolve": lms_wants_evolve}
