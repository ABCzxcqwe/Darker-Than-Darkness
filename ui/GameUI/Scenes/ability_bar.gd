extends HBoxContainer

const ABILITY_BUTTON_SCENE := preload("uid://bmtkxxhx3sll5")

var _player_node: Node = null
var _buttons: Dictionary = {}


func setup(player_node: Node) -> void:
	_player_node = player_node
	if not player_node.character_data:
		push_warning("[AbilityBar] Player sin character_data.")
		return
	var peer_id: int = player_node.get_multiplayer_authority()
	var slots: Array = player_node.character_data.ability_slots
	for i in slots.size():
		var data: AbilityData = slots[i]
		if not data:
			continue
		var btn := ABILITY_BUTTON_SCENE.instantiate()
		add_child(btn)
		btn.setup(data, i, "", peer_id)
		_buttons[i] = btn

	if InputService.device_changed.is_connected(_on_device_changed):
		InputService.device_changed.disconnect(_on_device_changed)
	InputService.device_changed.connect(_on_device_changed)
	_refresh_labels()


func _refresh_labels() -> void:
	for slot in _buttons:
		var action := "ability_%d" % slot
		var label: String = InputService.get_action_label(action)
		if _buttons[slot].has_method("set_key_label"):
			_buttons[slot].set_key_label(label)


func _on_device_changed(_device: int) -> void:
	_refresh_labels()


func on_cooldown_state_changed(slot_index: int, duration: float) -> void:
	if not _buttons.has(slot_index):
		return
	_buttons[slot_index].set_cooldown_state(duration)


func on_slot_evolved(slot_index: int, stage: int) -> void:
	if not _buttons.has(slot_index):
		return
	_buttons[slot_index].set_evolution_stage(stage)


func on_slot_devolved(slot_index: int) -> void:
	if not _buttons.has(slot_index):
		return
	_buttons[slot_index].set_evolution_stage(0)


func on_tp_ready(slot_index: int, is_ready: bool) -> void:
	if not _buttons.has(slot_index):
		return
	_buttons[slot_index].set_tp_ready(is_ready)


func on_rage_ready(charged: bool, progress: int, required: int) -> void:
	if not _buttons.has(4):
		return
	_buttons[4].set_rage_state(charged, progress, required)


func on_rage_time(remaining: float) -> void:
	if not _buttons.has(4):
		return
	var btn = _buttons[4]
	if btn.has_method("set_rage_time"):
		btn.set_rage_time(remaining)


func on_ability_slot_updated(slot_index: int, tp_cost: float, cooldown: float, stage: int) -> void:
	if not _buttons.has(slot_index):
		return
	var btn = _buttons[slot_index]
	if btn.has_method("set_evolution_stage"):
		btn.set_evolution_stage(stage)
	# Cooldown and TP are handled via dynamic overrides in tp_bar / button _update_tp_fill
	# Keep button visuals in sync (icon already swapped via evolution stage)
	if btn.has_method("set_dynamic_cost"):
		btn.set_dynamic_cost(tp_cost)