extends Node

enum ProtectionType {
	DAMAGE_SHARE,
	DAMAGE_REDUCE,
	DEATH_SHIELD
}

var _protections: Dictionary = {}

signal damage_dealt(attacker_id: int, target_id: int, final_damage: int, attack_type: String)

func apply_damage(attacker: Node, target: Node, base_damage: int, attack_type: String) -> int:
	if not multiplayer.is_server():
		return 0

	if _check_intercept(attacker, target):
		return 0

	var final_damage: int = _calculate_damage(attacker, target, base_damage, attack_type)
	if final_damage <= 0:
		return 0

	var target_peer: int = target.get_multiplayer_authority()
	var health_svc = GameServiceLocator.get_service("HealthService")
	if not health_svc:
		return 0

	if not health_svc.is_alive(target_peer):
		return 0

	if target.character_data and target.character_data.team == "killer":
		return 0

	var now := Time.get_ticks_msec()
	if now < target.invincible_until:
		if target.character_data and \
		   not attack_type in target.character_data.special_defense_against:
			return 0

	final_damage = _apply_protections(target_peer, target, final_damage)

	if final_damage <= 0:
		return 0

	target.invincible_until = now + int(target.character_data.invincibility_frames * 1000)

	health_svc.take_damage(target, final_damage)

	var att_id: int = attacker.get_multiplayer_authority() if attacker else 0
	damage_dealt.emit(att_id, target_peer, final_damage, attack_type)

	if target.character_data and target.character_data.team == "survivor":
		AudioManager.play_sfx_networked.rpc(6, target.global_position.x, target.global_position.y)

	return final_damage


func calculate_damage(attacker: Node, target: Node, base_damage: int, attack_type: String) -> int:
	return _calculate_damage(attacker, target, base_damage, attack_type)


func _calculate_damage(_attacker: Node, target: Node, base_damage: int, _attack_type: String) -> int:
	var damage: int = base_damage

	if not target.character_data:
		return maxi(1, damage)

	var lms_svc = GameServiceLocator.get_service("LMSService")
	if lms_svc and lms_svc.is_lms_active():
		var target_peer: int = target.get_multiplayer_authority()
		var lms_survivor = lms_svc.get_active_survivor()
		if lms_survivor and lms_survivor.get_multiplayer_authority() == target_peer:
			var resistance: float = target.character_data.lms_damage_resistance
			if resistance > 0.0:
				damage = ceili(damage * (1.0 - resistance))

	var status = GameServiceLocator.get_service("StatusEffectService")
	if status:
		var target_peer: int = target.get_multiplayer_authority()
		var dr: float = status.get_post_stun_dr(target_peer)
		if dr > 0.0:
			damage = ceili(damage * (1.0 - dr))

	return maxi(1, damage)


func _check_intercept(attacker: Node, target: Node) -> bool:
	if not is_instance_valid(target):
		return false

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if not abs_svc:
		return false

	var char_data: CharacterData = target.get("character_data")
	if not char_data or not char_data.ability_slots:
		return false

	var target_peer: int = target.get_multiplayer_authority()

	for slot_index in char_data.ability_slots.size():
		if not abs_svc.is_mode_active(target_peer, slot_index):
			continue

		var ability_data: AbilityData = char_data.ability_slots[slot_index]
		if not ability_data or not ability_data.ability_script:
			continue

		var handler = ability_data.ability_script.new()
		if not handler.has_method("try_intercept"):
			continue

		var intercepted: bool = handler.try_intercept(target, attacker, ability_data, slot_index)
		if intercepted:
			print("[CombatMediator] Daño interceptado por slot ", slot_index,
				  " (", ability_data.display_name, ") | peer: ", target_peer)
			return true

	return false


func apply_stun(target: Node, duration: float, post_stun_dr: float = 0.0) -> void:
	if not multiplayer.is_server():
		return

	if target and target.character_data and target.character_data.team == "killer":
		var ha_id: int = 24 if randi() % 2 == 0 else 25
		AudioManager.play_sfx_networked.rpc(ha_id, target.global_position.x, target.global_position.y)

	var status = GameServiceLocator.get_service("StatusEffectService")
	if status:
		var params := { "duration": duration }
		if post_stun_dr > 0.0:
			params["post_stun_dr"] = post_stun_dr
		status.apply(target, "stun", params)


func apply_slow(target: Node, duration: float, magnitude: float) -> void:
	if not multiplayer.is_server():
		return

	var status = GameServiceLocator.get_service("StatusEffectService")
	if status:
		status.apply(target, "slow", { "duration": duration, "magnitude": magnitude })


func apply_root(target: Node, duration: float) -> void:
	if not multiplayer.is_server():
		return

	var status = GameServiceLocator.get_service("StatusEffectService")
	if status:
		status.apply(target, "root", { "duration": duration })


func remove_root(target: Node) -> void:
	remove_effect(target, "root")


func remove_stun(target: Node) -> void:
	remove_effect(target, "stun")


func remove_slow(target: Node) -> void:
	remove_effect(target, "slow")


func remove_effect(target: Node, effect_name: String) -> void:
	if not multiplayer.is_server():
		return

	var status = GameServiceLocator.get_service("StatusEffectService")
	if status:
		status.remove_effect(target, effect_name)


func register_protection(protected_id: int, protector_id: int, type: int, params: Dictionary = {}) -> void:
	if not _protections.has(protected_id):
		_protections[protected_id] = []
	_protections[protected_id].append({
		"protector_id": protector_id,
		"type": type,
		"params": params
	})


func unregister_protection(protected_id: int, protector_id: int, type: int) -> void:
	if not _protections.has(protected_id):
		return
	_protections[protected_id] = _protections[protected_id].filter(
		func(p): return not (p.protector_id == protector_id and p.type == type)
	)
	if _protections[protected_id].is_empty():
		_protections.erase(protected_id)


func unregister_all_for_protector(protector_id: int) -> void:
	for protected_id in _protections.keys():
		_protections[protected_id] = _protections[protected_id].filter(
			func(p): return p.protector_id != protector_id
		)
		if _protections[protected_id].is_empty():
			_protections.erase(protected_id)


func _apply_protections(peer_id: int, player_node: Node, amount: int) -> int:
	if not _protections.has(peer_id):
		return amount

	var current_hp: int = player_node.health

	if current_hp <= 1:
		_protections.erase(peer_id)
		return amount

	var final_amount: int = amount
	var has_death_shield: bool = false

	for p in _protections[peer_id]:
		match p.type:
			ProtectionType.DEATH_SHIELD:
				has_death_shield = true

			ProtectionType.DAMAGE_REDUCE:
				var reduction: float = p.params.get("reduction_pct", 0.5)
				final_amount = ceil(final_amount * (1.0 - reduction))

			ProtectionType.DAMAGE_SHARE:
				var share_pct: float = p.params.get("share_pct", 0.5)
				var shared: int = ceil(final_amount * share_pct)

				var health_svc = GameServiceLocator.get_service("HealthService")
				if not health_svc:
					continue

				var protector: Node = _find_player_node_by_peer_id(p.protector_id)
				if not is_instance_valid(protector) or not health_svc.is_alive(p.protector_id):
					continue

				var protector_hp: int = protector.health
				if protector_hp <= 1:
					continue

				var new_hp: int = max(1, protector_hp - shared)
				protector.health = new_hp

				var max_hp_p: int = protector.character_data.max_health \
					if protector.character_data else 100
				health_svc.broadcast_health_update(p.protector_id, new_hp, max_hp_p, "alive")

				final_amount = max(0, final_amount - shared)

	if has_death_shield and current_hp - final_amount <= 0 and current_hp > 1:
		return current_hp - 1

	return final_amount


func _find_player_node_by_peer_id(peer_id: int) -> Node:
	return get_tree().root.find_child(str(peer_id), true, false)
