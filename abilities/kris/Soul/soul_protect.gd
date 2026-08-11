extends AbilityBase

const DURATION: float = 10.0
const SHARE_PCT: float = 0.5
const ANIM_FALLBACK: float = 1.6

var _caster_id: int = -1
var _target_peer_id: int = -1
var _player_node: Node = null
var _combat: Node = null
var _broken: bool = false


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		return

	_caster_id = player_node.get_multiplayer_authority()
	_target_peer_id = pending_target_peer
	_player_node = player_node

	if _target_peer_id <= 0 or _target_peer_id == _caster_id:
		return

	var tp_svc = GameServiceLocator.tp
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(_caster_id, data.tp_cost):
			return

	_combat = GameServiceLocator.combat_mediator
	if not _combat:
		return

	# Play action animation first (root is already active from prepare phase)
	var anim_dur := _get_anim_duration(player_node, data.action_animation)

	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, slot_index, player_node.facing_right)

	player_node.get_tree().create_timer(anim_dur).timeout.connect(
		func() -> void:
			if not is_instance_valid(player_node):
				return

			_combat.remove_root(player_node)

			_combat.register_protection(_target_peer_id, _caster_id,
				_combat.ProtectionType.DAMAGE_SHARE, { "share_pct": SHARE_PCT })
			_combat.register_protection(_target_peer_id, _caster_id,
				_combat.ProtectionType.DEATH_SHIELD, {})

			_spawn_shield()

			if not _combat.damage_dealt.is_connected(_on_player_damaged):
				_combat.damage_dealt.connect(_on_player_damaged)

			var cd_svc = GameServiceLocator.cooldown
			var expire_timer := player_node.get_tree().create_timer(DURATION)
			expire_timer.timeout.connect(func() -> void:
				if not is_instance_valid(player_node):
					return

				_combat.unregister_protection(_target_peer_id, _caster_id,
					_combat.ProtectionType.DAMAGE_SHARE)
				_combat.unregister_protection(_target_peer_id, _caster_id,
					_combat.ProtectionType.DEATH_SHIELD)

				break_shield()

				if _combat.damage_dealt.is_connected(_on_player_damaged):
					_combat.damage_dealt.disconnect(_on_player_damaged)

				if cd_svc:
					if cd_svc.has_method("release_lock"):
						cd_svc.release_lock(_caster_id, slot_index)
					cd_svc.start(_caster_id, slot_index, data.cooldown)

				print("[SoulProtect] Proteccion expirada para ", _target_peer_id)
			)

			player_node.rpc("_sync_cancel_ability")

			print("[SoulProtect] Kris(", _caster_id, ") protege a ", _target_peer_id,
				  " por ", DURATION, "s | comparte ", SHARE_PCT * 100, "% del daño")
	)


func _on_player_damaged(attacker_id: int, target_id: int, _final_damage: int, _attack_type: String) -> void:
	if _broken:
		return
	if target_id != _caster_id and target_id != _target_peer_id:
		return

	var attacker: Node = PlayerRegistry.get_player(attacker_id)
	if not is_instance_valid(attacker):
		return
	var cd: CharacterData = attacker.get("character_data")
	if cd and cd.team != "killer":
		return

	break_shield()


func _spawn_shield() -> void:
	if not is_instance_valid(_player_node):
		return
	_player_node.rpc("_rpc_soul_protect_show", _caster_id)
	_player_node.rpc("_rpc_soul_protect_show", _target_peer_id)


func break_shield() -> void:
	if _broken:
		return
	_broken = true
	if not is_instance_valid(_player_node):
		return
	_player_node.rpc("_rpc_soul_protect_break", _caster_id)
	_player_node.rpc("_rpc_soul_protect_break", _target_peer_id)


func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return ANIM_FALLBACK
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return ANIM_FALLBACK
	if not sprite.sprite_frames.has_animation(anim_name):
		return ANIM_FALLBACK
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return ANIM_FALLBACK
	return frame_count / fps
