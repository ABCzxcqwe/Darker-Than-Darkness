extends AbilityBase
class_name RugidoAbility

const VISION_FACTOR: float = 0.5
const VISION_DURATION: float = 10.0
const REVEAL_DURATION: float = 10.0

static var _keep_alive: Array = []

var _active: bool = false
var _player_node: Node = null
var _caster_id: int = -1
var _slot_index: int = -1
var _data: AbilityData = null
var _cd_svc: Node = null
var _combat: Node = null

var _cast_duration: float = 1.5


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	_player_node = player_node
	_caster_id = player_node.get_multiplayer_authority()
	_data = data
	_slot_index = slot_index
	_active = true
	_cast_duration = data.cast_duration if data and data.cast_duration > 0.0 else 1.5

	var tp_svc = GameServiceLocator.tp
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(_caster_id, data.tp_cost):
			_fail_cleanup()
			return

	_cd_svc = GameServiceLocator.cooldown
	_combat = GameServiceLocator.combat_mediator

	var facing_right: bool = direction.x >= 0.0 or direction == Vector2.ZERO
	player_node.play_ability_animation(data.action_animation, _slot_index, facing_right)

	if _combat:
		_combat.apply_root(_player_node, _cast_duration)

	_keep_alive.append(self)

	if player_node.multiplayer.is_server():
		var relay = GameServiceLocator.get_client_relay()
		if is_instance_valid(relay):
			relay.rpc("_rpc_camera_shake", 20.0, 1.5)

	var spawn_delay: float = data.spawn_delay if data.spawn_delay > 0.0 else 0.0
	if player_node.get_tree():
		player_node.get_tree().create_timer(spawn_delay).timeout.connect(
			func(): _spawn_wave()
		)

	_apply_slow_to_nearby()
	_apply_vision_reduction_to_survivors()
	_reveal_survivors()

	AudioManager.play_sfx_global_networked.rpc(SfxId.KING_LAUGH)

	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
		_cd_svc.start(_caster_id, _slot_index, data.cooldown)

	if player_node.get_tree():
		player_node.get_tree().create_timer(_cast_duration).timeout.connect(
			func(): _finish()
		)

	print("[Rugido] Habilidad iniciada | peer: ", _caster_id)


func _spawn_wave() -> void:
	if not _active or not is_instance_valid(_player_node):
		return
	if not _data or not _data.ability_scene:
		return

	var world = _player_node.get_tree().root.find_child("World", true, false)
	if not world:
		return
	var container = world.get_node_or_null("Projectiles")
	if not container:
		return

	var wave = _data.ability_scene.instantiate()
	container.add_child(wave, true)
	wave.global_position = _player_node.global_position
	if wave.has_method("set_duration"):
		wave.set_duration(_cast_duration)

	print("[Rugido] Onda generada en ", wave.global_position)


func _apply_slow_to_nearby() -> void:
	var radius: float = _data.range_ if _data else 1000.0
	var duration: float = _data.slow_duration if _data else 5.0
	var magnitude: float = _data.slow_magnitude if _data else 0.2
	var origin: Vector2 = _player_node.global_position

	for survivor in _player_node.get_tree().get_nodes_in_group("survivor"):
		if not is_instance_valid(survivor):
			continue
		if survivor.health_state != "alive":
			continue
		if survivor.global_position.distance_to(origin) > radius:
			continue
		if _combat:
			_combat.apply_slow(survivor, duration, magnitude)


func _apply_vision_reduction_to_survivors() -> void:
	for survivor in _player_node.get_tree().get_nodes_in_group("survivor"):
		if is_instance_valid(survivor) and survivor.has_method("_sync_vision_reduction"):
			survivor.rpc("_sync_vision_reduction", VISION_FACTOR, VISION_DURATION)


func _reveal_survivors() -> void:
	var radar = GameServiceLocator.radar
	if radar and radar.has_method("reveal_enemies"):
		radar.reveal_enemies(_caster_id, REVEAL_DURATION)


func _finish() -> void:
	if not _active:
		return
	_active = false

	if _combat and is_instance_valid(_player_node):
		_combat.remove_root(_player_node)

	if is_instance_valid(_player_node):
		_player_node.rpc("_sync_cancel_ability")

	_keep_alive.erase(self)
	print("[Rugido] Habilidad finalizada | peer: ", _caster_id)


func _fail_cleanup() -> void:
	_active = false
	if _cd_svc:
		if _cd_svc.has_method("release_lock"):
			_cd_svc.release_lock(_caster_id, _slot_index)
	print("[Rugido] Fallo en activación | peer: ", _caster_id)
