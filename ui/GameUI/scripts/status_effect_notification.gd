extends PanelContainer

var _effect_name: String
var _duration: float
var _time_remaining: float
var _peer_id: int


func setup(peer_id: int, effect_name: String, duration: float) -> void:
	_peer_id = peer_id
	_effect_name = effect_name
	_duration = maxf(duration, 0.01)
	_time_remaining = _duration

	$VBoxContainer/HBoxContainer/EffectLabel.text = _get_display_name(effect_name)
	$VBoxContainer/HBoxContainer/TimeLabel.text = "%.1fs" % _time_remaining
	$VBoxContainer/ProgressBar.max_value = _duration
	$VBoxContainer/ProgressBar.value = _duration


func _process(delta: float) -> void:
	if not is_inside_tree():
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
		"stun":        return "ATURDIDO"
		"slow":        return "RALLENTIZADO"
		"root":        return "ENRAIZADO"
		"silence":     return "SILENCIADO"
		"blind":       return "CEGADO"
		"speed_boost": return "VELOCIDAD"
		_:             return effect.to_upper()
