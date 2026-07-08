extends MeleeAbilityBase

func _get_config(data: AbilityData) -> Dictionary:
	return {
		"hitbox_lifetime": 0.5,
		"initial_hitbox_damage": 0,
		"damage_multiplier": data.evo_damage_multiplier,
		"stun_duration_bonus": data.evo_status_duration_bonus,
		"sfx": SfxId.HIT,
	}
