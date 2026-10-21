extends HBoxContainer

const ABILITY_BUTTON_SCENE := preload("uid://bmtkxxhx3sll5")
const FASE2_CANCEL_ICON := preload("res://abilities/susie/AxeSlash/icons/axe.png")

var _player_node: Node = null
var _buttons: Dictionary = {}

# ── Fase 2: M1 = disparar/confirmar, X = cancelar ─────────────────────────
var _fase2_active: bool = false
var _fase2_temps: Array = []
var _fase2_entry_slot: int = -1
var _fase2_fire_btn: Node = null
var _fase2_cancel_btn: Node = null
var _fase2_last_phase: String = ""
var _fase2_charge_total: float = 0.0


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
	set_process(true)


func _process(_delta: float) -> void:
	if not is_instance_valid(_player_node):
		return
	var raw_aim = _player_node.get("aiming_slot")
	var aiming: int = int(raw_aim) if raw_aim != null else -1
	var in_fase2: bool = aiming >= 0
	if in_fase2 != _fase2_active:
		if in_fase2:
			enter_fase2_mode(aiming)
		else:
			exit_fase2_mode()

	if in_fase2 and _fase2_active:
		var raw_phase = _player_node.get("fase2_phase")
		var phase: String = String(raw_phase) if raw_phase != null else "aim"
		if phase != _fase2_last_phase:
			_fase2_last_phase = phase
			_apply_fase2_phase_visibility(phase)
		_update_fase2_charge(phase)


## Muestra en el botón M1 el tiempo que falta para poder disparar (carga AIM).
func _update_fase2_charge(phase: String) -> void:
	if phase != "aim" or _fase2_charge_total <= 0.0:
		return
	if not is_instance_valid(_fase2_fire_btn):
		return
	if not _fase2_fire_btn.has_method("set_charge_state"):
		return
	var remaining: float = 0.0
	if _player_node.has_method("get_fase2_charge_remaining"):
		remaining = _player_node.get_fase2_charge_remaining()
	_fase2_fire_btn.set_charge_state(remaining)


## Fase 2 activa: oculta la barra real y muestra solo
## M1 = disparar/confirmar y X = cancelar.
func enter_fase2_mode(entry_slot: int) -> void:
	if _fase2_active:
		return
	_fase2_active = true
	_fase2_entry_slot = entry_slot
	_fase2_last_phase = ""
	for slot in _buttons:
		_buttons[slot].visible = false
	var peer_id: int = _player_node.get_multiplayer_authority()
	var entry_data: AbilityData = null
	var slots: Array = _player_node.character_data.ability_slots if _player_node.character_data else []
	if entry_slot >= 0 and entry_slot < slots.size():
		entry_data = slots[entry_slot]
	if entry_data:
		_fase2_charge_total = entry_data.fase2_charge_time
		var fire_btn := ABILITY_BUTTON_SCENE.instantiate()
		add_child(fire_btn)
		fire_btn.setup(entry_data, 0, "M1", peer_id)
		if fire_btn.has_method("set_key_label"):
			fire_btn.set_key_label("M1")
		_fase2_temps.append(fire_btn)
		_fase2_fire_btn = fire_btn
	var cancel_data := AbilityData.new()
	cancel_data.display_name = "Cancelar"
	cancel_data.icon = FASE2_CANCEL_ICON
	var cancel_btn := ABILITY_BUTTON_SCENE.instantiate()
	add_child(cancel_btn)
	cancel_btn.setup(cancel_data, 3, "X", peer_id)
	if cancel_btn.has_method("set_key_label"):
		cancel_btn.set_key_label("X")
	_fase2_temps.append(cancel_btn)
	_fase2_cancel_btn = cancel_btn
	_apply_fase2_phase_visibility("aim")
	print("[AbilityBar] Fase2 visual | entry: ", entry_slot, " | M1 dispara, X cancela")


## En CHANNEL no se puede volver a disparar: se oculta M1. X solo se muestra
## si la habilidad permite cancelar la canalización.
func _apply_fase2_phase_visibility(phase: String) -> void:
	var is_channel: bool = phase == "channel"
	if is_instance_valid(_fase2_fire_btn):
		_fase2_fire_btn.visible = not is_channel
	if is_instance_valid(_fase2_cancel_btn):
		var can_cancel := true
		if is_channel:
			var slots: Array = _player_node.character_data.ability_slots if _player_node.character_data else []
			if _fase2_entry_slot >= 0 and _fase2_entry_slot < slots.size():
				var entry_data: AbilityData = slots[_fase2_entry_slot]
				if entry_data:
					can_cancel = entry_data.fase2_channel_cancel_on_player
		_fase2_cancel_btn.visible = can_cancel


func exit_fase2_mode() -> void:
	if not _fase2_active:
		return
	_fase2_active = false
	_fase2_entry_slot = -1
	_fase2_fire_btn = null
	_fase2_cancel_btn = null
	_fase2_last_phase = ""
	_fase2_charge_total = 0.0
	for tmp in _fase2_temps:
		if is_instance_valid(tmp):
			tmp.queue_free()
	_fase2_temps.clear()
	for slot in _buttons:
		if is_instance_valid(_buttons[slot]):
			_buttons[slot].visible = true
	_refresh_labels()
	print("[AbilityBar] Fase2 visual cerrada, barra restaurada")


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