# ability_bar.gd
# Barra de habilidades del jugador local.
# El cooldown visual se inicia cuando GameHUD llama on_cooldown_state_changed()
# con los datos que vienen del CooldownService (servidor → cliente via RPC).
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
		if i == 0 and player_node.character_data.team != "killer":
			continue

		var key_name: String = KEY_NAMES.get(i, str(i))
		var btn := ABILITY_BUTTON_SCENE.instantiate()
		add_child(btn)
		btn.setup(data, i, key_name)
		_buttons[i] = btn


## Llamado por GameHUD cuando CooldownService notifica al cliente.
## duration > 0 → cooldown normal con timer
## duration = 0 → listo (sin cooldown)
## duration < 0 → lock activo (indefinido)
func on_cooldown_state_changed(slot_index: int, duration: float) -> void:
	if not _buttons.has(slot_index):
		return
	_buttons[slot_index].set_cooldown_state(duration)


## Llamado por EvolutionService (via GameHUD) cuando un slot evoluciona.
func on_slot_evolved(slot_index: int) -> void:
	if not _buttons.has(slot_index):
		return
	_buttons[slot_index].set_evolved(true)


## Llamado por EvolutionService (via GameHUD) cuando un slot vuelve a normal.
func on_slot_devolved(slot_index: int) -> void:
	if not _buttons.has(slot_index):
		return
	_buttons[slot_index].set_evolved(false)
