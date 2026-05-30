# CombatMediator.gd
# Capa de coordinación entre habilidades y servicios base.
# Las habilidades llaman a CombatMediator en lugar de llamar directamente
# a HealthService / StatusEffectService.
#
# Responsabilidades:
#   1. Calcular modificadores de daño (LMS resistance, post-stun DR, etc.)
#   2. Verificar interceptores activos (Counter, etc.) antes de aplicar daño
#   3. Aplicar daño y efectos de estado delegando en los servicios base
#   4. Proveer terminación manual de efectos (root, stun, etc.)
#
# SISTEMA DE INTERCEPTORES:
#   Antes de aplicar daño, CombatMediator revisa si el target tiene algún
#   slot con modo activo. Si ese slot tiene un script con try_intercept(),
#   lo llama. Si devuelve true, el daño se cancela completamente.
#
#   Contrato de try_intercept():
#     func try_intercept(target: Node, attacker: Node, data: AbilityData, slot_index: int) -> bool
#     - Devuelve true  → daño cancelado, CombatMediator no aplica nada.
#     - Devuelve false → daño continúa normalmente.
#
# Se accede via: GameServiceLocator.get_service("CombatMediator")
extends Node


# ═══════════════════════════════════════════════════════════════════════════
# DAÑO
# ═══════════════════════════════════════════════════════════════════════════

## Calcula el daño final tras aplicar todas las reducciones y lo aplica.
## Retorna el daño real calculado (0 si no se pudo aplicar o fue interceptado).
func apply_damage(attacker: Node, target: Node, base_damage: int, attack_type: String) -> int:
	if not multiplayer.is_server():
		return 0

	# ── Verificar interceptores antes de calcular daño ───────────────────
	# Si algún slot activo del target intercepta el golpe, cancelamos aquí.
	if _check_intercept(attacker, target):
		return 0

	var final_damage: int = _calculate_damage(attacker, target, base_damage, attack_type)
	if final_damage <= 0:
		return 0

	var health_svc = GameServiceLocator.get_service("HealthService")
	if health_svc:
		var attacker_id: int = attacker.get_multiplayer_authority() if attacker else 0
		health_svc.take_damage(target, final_damage, attacker_id, attack_type)

	return final_damage


## Solo cálculo — útil si la habilidad necesita saber el daño antes de aplicarlo
## (ej. para mostrar un número, decidir si spawnear un VFX, etc.)
## NOTA: No verifica interceptores — usar apply_damage() para el flujo real.
func calculate_damage(attacker: Node, target: Node, base_damage: int, attack_type: String) -> int:
	return _calculate_damage(attacker, target, base_damage, attack_type)


func _calculate_damage(_attacker: Node, target: Node, base_damage: int, _attack_type: String) -> int:
	var damage: int = base_damage

	if not target.character_data:
		return maxi(1, damage)

	# LMS damage resistance
	var lms_svc = GameServiceLocator.get_service("LMSService")
	if lms_svc and lms_svc.is_lms_active():
		var target_peer: int = target.get_multiplayer_authority()
		var lms_survivor = lms_svc.get_active_survivor()
		if lms_survivor and lms_survivor.get_multiplayer_authority() == target_peer:
			var resistance: float = target.character_data.lms_damage_resistance
			if resistance > 0.0:
				damage = ceili(damage * (1.0 - resistance))

	# Post-stun damage reduction
	var status = GameServiceLocator.get_service("StatusEffectService")
	if status:
		var target_peer: int = target.get_multiplayer_authority()
		var dr: float = status.get_post_stun_dr(target_peer)
		if dr > 0.0:
			damage = ceili(damage * (1.0 - dr))

	return maxi(1, damage)


# ═══════════════════════════════════════════════════════════════════════════
# SISTEMA DE INTERCEPTORES
# ═══════════════════════════════════════════════════════════════════════════

## Revisa todos los slots del target buscando uno con modo activo que
## implemente try_intercept(). Si lo encuentra y devuelve true, el daño
## queda cancelado.
## Devuelve true si el daño fue interceptado.
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
		# Solo slots con modo activo son candidatos
		if not abs_svc.is_mode_active(target_peer, slot_index):
			continue

		var ability_data: AbilityData = char_data.ability_slots[slot_index]
		if not ability_data or not ability_data.ability_script:
			continue

		# Instanciar el script y verificar si tiene try_intercept()
		var handler = ability_data.ability_script.new()
		if not handler.has_method("try_intercept"):
			continue

		var intercepted: bool = handler.try_intercept(target, attacker, ability_data, slot_index)
		if intercepted:
			print("[CombatMediator] Daño interceptado por slot ", slot_index,
				  " (", ability_data.display_name, ") | peer: ", target_peer)
			return true

	return false


# ═══════════════════════════════════════════════════════════════════════════
# EFECTOS DE ESTADO — APLICACIÓN
# ═══════════════════════════════════════════════════════════════════════════

## Aplica stun. La habilidad puede pasar post_stun_dr para que el survivor
## reciba reducción de daño temporal al terminar el stun.
func apply_stun(target: Node, duration: float, post_stun_dr: float = 0.0) -> void:
	if not multiplayer.is_server():
		return

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


## Aplica root. duration es un safety timeout por si la habilidad olvida
## llamar remove_root(). La habilidad DEBE llamar remove_root() manualmente
## cuando el personaje deba recuperar la movilidad.
func apply_root(target: Node, duration: float) -> void:
	if not multiplayer.is_server():
		return

	var status = GameServiceLocator.get_service("StatusEffectService")
	if status:
		status.apply(target, "root", { "duration": duration })


# ═══════════════════════════════════════════════════════════════════════════
# EFECTOS DE ESTADO — TERMINACIÓN MANUAL
# ═══════════════════════════════════════════════════════════════════════════

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
