extends KingAbilityBase
class_name ChannelledAbilityBase

# Para habilidades canalizadas de King (Topo, Lanza) que usan hold + root durante toda la canalización.

func _setup_channelled(data: AbilityData, slot_index: int, facing_right: bool, root_duration: float, invincibility_duration: float = -1.0) -> void:
	_play_hold_anim(data, slot_index, facing_right)
	_apply_root(root_duration)
	if invincibility_duration >= 0.0:
		_grant_invincibility(invincibility_duration)


func _finish_channelled() -> void:
	_remove_root()
	_unhold_anim()
