# ability_bar.gd
# Barra de habilidades del jugador local.
# El cooldown visual se inicia cuando GameHUD llama on_cooldown_started()
# con los datos que vienen del CooldownService (servidor → cliente via RPC).
# La barra NO lee cooldowns desde character_data por su cuenta.
extends HBoxContainer

const ABILITY_BUTTON_SCENE := preload("res://ui/AbilityButton.tscn")

# Teclas visibles por slot (0=M1, 1-4=habilidades)
const KEY_NAMES := {
	0: "M1",
	1: "E",
	2: "Q",
	3: "X",
	4: "Z",
}

var _player_node: Node = null
# { slot_index: AbilityButton }
var _buttons: Dictionary = {}
# { ability_name: slot_index } — para buscar botón por nombre cuando slot_index == -1
var _name_to_slot: Dictionary = {}


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
		_name_to_slot[data.display_name] = i   # indexar por display_name (mismo string que usa AbilityRouter)


## Llamado por GameHUD cuando CooldownService notifica al cliente.
## ability_name es el nombre usado en CooldownService.start().
## slot_index es -1 si la habilidad no proporcionó el slot al llamar start().
func on_cooldown_started(ability_name: String, slot_index: int, duration: float) -> void:
	var target_slot := slot_index

	# Si no se proporcionó slot, intentar resolverlo por nombre
	if target_slot == -1:
		if _name_to_slot.has(ability_name):
			target_slot = _name_to_slot[ability_name]
		else:
			push_warning("[AbilityBar] No se encontró slot para habilidad: ", ability_name)
			return

	if not _buttons.has(target_slot):
		return
	_buttons[target_slot].start_cooldown(duration)


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
