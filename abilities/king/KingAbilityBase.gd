extends "res://abilities/AbilityBase.gd"
class_name KingAbilityBase

# Base para habilidades de King — helpers comunes sin static keep_alive compartido.
# Cada subclase mantiene su propio `static var _keep_alive: Array = []` para evitar
# que Lanza y Topo compartan el mismo pool (GDScript 4.x no tiene static polimórfico).

var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _cd_svc: Node = null
var _combat: Node = null


func _cache_common(player_node: Node, data: AbilityData, slot_index: int) -> bool:
	if not is_instance_valid(player_node):
		return false
	_player_node = player_node
	_caster_id = player_node.get_multiplayer_authority()
	_data = data
	_slot_index = slot_index
	_cd_svc = GameServiceLocator.cooldown
	_combat = GameServiceLocator.combat_mediator
	return true


func _consume_tp_or_fail() -> bool:
	var tp_svc = GameServiceLocator.tp
	if _data and _data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(_caster_id, _data.tp_cost):
			_fail_cleanup()
			return false
	return true


func _grant_invincibility(duration: float) -> void:
	if not is_instance_valid(_player_node):
		return
	var ms: int = int(duration * 1000.0)
	_player_node.invincible_until = Time.get_ticks_msec() + ms
	_player_node.rpc("_sync_invincibility", ms)


func _apply_root(duration: float) -> void:
	if _combat and is_instance_valid(_player_node):
		_combat.apply_root(_player_node, duration)


func _remove_root() -> void:
	if _combat and is_instance_valid(_player_node):
		_combat.remove_root(_player_node)


func _get_facing_right(direction: Vector2) -> bool:
	return direction.x >= 0.0 or direction == Vector2.ZERO


func _play_hold_anim(data: AbilityData, slot_index: int, facing_right: bool) -> void:
	if not is_instance_valid(_player_node):
		return
	_player_node.play_ability_animation(data.action_animation, slot_index, facing_right)
	_player_node.hold_ability_anim = true
	_player_node.rpc("_sync_ability_hold", true)


func _play_anim_no_hold(data: AbilityData, slot_index: int, facing_right: bool) -> void:
	if not is_instance_valid(_player_node):
		return
	if data.action_animation != "":
		_player_node.play_ability_animation(data.action_animation, slot_index, facing_right)


func _unhold_anim() -> void:
	if is_instance_valid(_player_node):
		_player_node.hold_ability_anim = false
		_player_node.rpc("_sync_cancel_ability")


func _release_cooldown(success: bool, canceled: bool = false) -> void:
	if not _cd_svc:
		return
	if _cd_svc.has_method("release_lock"):
		_cd_svc.release_lock(_caster_id, _slot_index)
	var cd: float = _data.cooldown if _data else 0.0
	if not success and not canceled and _data and _data.cooldown_fail > 0.0:
		cd = _data.cooldown_fail
	_cd_svc.start(_caster_id, _slot_index, cd)


func _fail_cleanup() -> void:
	if _cd_svc and _cd_svc.has_method("release_lock"):
		_cd_svc.release_lock(_caster_id, _slot_index)
