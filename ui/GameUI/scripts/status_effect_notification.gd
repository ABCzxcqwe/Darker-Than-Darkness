extends PanelContainer

var _effect_name: String
var _duration: float
var _time_remaining: float
var _peer_id: int


func setup(peer_id: int, effect_name: String, duration: float) -> void:
	_peer_id = peer_id
	_effect_name = effect_name
	_duration = duration
	_time_remaining = duration

	$VBoxContainer/HBoxContainer/EffectLabel.text = _get_display_name(effect_name)

	if is_inf(duration):
		# Duración manual/infinita: sin countdown ni barra de progreso.
		$VBoxContainer/HBoxContainer/TimeLabel.text = "∞"
		$VBoxContainer/ProgressBar.visible = false
	else:
		_duration = maxf(duration, 0.01)
		_time_remaining = _duration
		$VBoxContainer/HBoxContainer/TimeLabel.text = "%.1fs" % _time_remaining
		$VBoxContainer/ProgressBar.max_value = _duration
		$VBoxContainer/ProgressBar.value = _duration


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	if is_inf(_duration):
		return

	_time_remaining -= delta
	_time_remaining = maxf(_time_remaining, 0.0)

	$VBoxContainer/HBoxContainer/TimeLabel.text = "%.1fs" % _time_remaining
	$VBoxContainer/ProgressBar.value = _time_remaining

	if _time_remaining <= 0.0:
		var tween := create_tween()
		tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.3)
		tween.tween_callback(queue_free)


func _get_display_name(effect: String) -> String:
	match effect:
		"stun":        return tr("HUD_FX_STUN")
		"slow":        return tr("HUD_FX_SLOW")
		"root":        return tr("HUD_FX_ROOT")
		"silence":     return tr("HUD_FX_SILENCE")
		"blind":       return tr("HUD_FX_BLIND")
		"speed_boost":       return tr("HUD_FX_SPEED")
		"stamina_reduction": return tr("HUD_FX_STAMINA")
		"protection":        return tr("HUD_FX_PROT")
		"bleed":             return tr("HUD_FX_BLEED")
		"damage_boost":      return tr("HUD_FX_DMGBOOST")
		"damage_reduction":  return tr("HUD_FX_DEF")
		"invisibility":      return tr("HUD_FX_INVIS")
		_:                   return effect.to_upper()
