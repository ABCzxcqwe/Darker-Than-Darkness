extends HBoxContainer

const ABILITY_BUTTON_SCENE := preload("uid://bmtkxxhx3sll5")

const KEY_NAMES := {
	0: "M1",
	1: "E",
	2: "Q",
	3: "X",
	4: "Z",
}

var _player_node: Node = null
var _buttons: Dictionary = {}


func setup(player_node: Node) -> void:
	_player_node = player_node
	if not player_node.character_data:
		push_warning("[AbilityBar] Player sin character_data.")
		return

	var slots: Array = player_node.character_data.ability_slots
	for i in slots.size():
		var data: AbilityData = slots[i]
		if not data:
			continue

		var key_name: String = KEY_NAMES.get(i, str(i))
		var btn := ABILITY_BUTTON_SCENE.instantiate()
		add_child(btn)
		btn.setup(data, i, key_name)
		_buttons[i] = btn


func on_cooldown_state_changed(slot_index: int, duration: float) -> void:
	if not _buttons.has(slot_index):
		return
	_buttons[slot_index].set_cooldown_state(duration)


func on_slot_evolved(slot_index: int) -> void:
	if not _buttons.has(slot_index):
		return
	_buttons[slot_index].set_evolved(true)


func on_slot_devolved(slot_index: int) -> void:
	if not _buttons.has(slot_index):
		return
	_buttons[slot_index].set_evolved(false)


func on_tp_ready(slot_index: int, is_ready: bool) -> void:
	if not _buttons.has(slot_index):
		return
	_buttons[slot_index].set_tp_ready(is_ready)
