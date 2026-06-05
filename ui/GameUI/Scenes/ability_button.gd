extends Control

@onready var panel:             Panel       = $Panel
@onready var icon_rect:         TextureRect = $Panel/IconRect
@onready var cooldown_overlay:  ColorRect   = $Panel/CooldownOverlay
@onready var cooldown_label:    Label       = $Panel/CooldownLabel
@onready var key_label:         Label       = $Panel/KeyLabel
@onready var lock_icon:         TextureRect = $Panel/LockIcon if has_node("Panel/LockIcon") else null

const BORDER_COLOR_NORMAL   := Color(0.8156863, 0.4745098, 0.0, 1.0)
const BORDER_COLOR_EVOLVED_A := Color(1.0, 0.9, 0.0, 1.0)
const BORDER_COLOR_EVOLVED_B := Color(1.0, 1.0, 1.0, 1.0)
const EVOLVED_FADE_DURATION  := 0.5

const PANEL_BG_COLOR := Color(0, 0, 0, 0.47058824)
const PANEL_CORNER_DETAIL := 1

enum State { READY, COOLDOWN, LOCKED }

var ability_data:        AbilityData = null
var slot_index:          int         = 0
var _state:              int         = State.READY
var _cooldown_remaining: float       = 0.0
var _is_evolved:         bool        = false
var _evolved_tween:      Tween       = null
var _base_data:          AbilityData = null
var _evolved_data:       AbilityData = null


func setup(data: AbilityData, index: int, key_name: String) -> void:
	ability_data = data
	slot_index   = index
	_base_data   = data
	_evolved_data = data.evolved_version if data and data.evolved_version else null

	_state = State.READY
	_cooldown_remaining = 0.0
	_stop_evolved_tween()
	_is_evolved = false

	var ability_name := data.display_name if data else "(vacío)"
	print("[AbilityButton] setup() — slot ", index, " ('", ability_name, "') tecla: ", key_name)

	if ability_data and data:
		if icon_rect:
			icon_rect.texture = data.icon if data.icon else null
			icon_rect.modulate = Color.WHITE
		if cooldown_label:
			cooldown_label.text = ""
	else:
		if icon_rect:
			icon_rect.texture = null
			icon_rect.modulate = Color(0.3, 0.3, 0.3, 0.5)

	if key_label:
		key_label.text = key_name

	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.set_corner_radius_all(3)
	style.border_color = BORDER_COLOR_NORMAL
	style.corner_detail = PANEL_CORNER_DETAIL
	style.expand_margin_left = 2.0
	style.expand_margin_top = 2.0
	style.expand_margin_right = 2.0
	style.expand_margin_bottom = 2.0
	style.anti_aliasing = false
	panel.add_theme_stylebox_override("panel", style)

	_apply_visual_state()


func _process(delta: float) -> void:
	if _state != State.COOLDOWN:
		return

	_cooldown_remaining -= delta

	if _cooldown_remaining <= 0.0:
		_cooldown_remaining = 0.0
		_state = State.READY
		_apply_visual_state()
		return

	if cooldown_label:
		cooldown_label.text = "%.1f" % _cooldown_remaining


func set_cooldown_state(duration: float) -> void:
	if not ability_data:
		return

	if duration < 0.0:
		_state = State.LOCKED
		_apply_visual_state()
		print("[AbilityButton] Lock — slot ", slot_index, " ('", ability_data.display_name, "')")

	elif duration == 0.0:
		_state = State.READY
		_cooldown_remaining = 0.0
		_apply_visual_state()
		print("[AbilityButton] Ready — slot ", slot_index, " ('", ability_data.display_name, "')")

	else:
		_state = State.COOLDOWN
		_cooldown_remaining = duration
		_apply_visual_state()
		print("[AbilityButton] Cooldown — slot ", slot_index,
			  " ('", ability_data.display_name, "') duración: ", duration, "s")


func set_evolved(evolved: bool) -> void:
	if not ability_data:
		return
	if _is_evolved == evolved:
		return

	_is_evolved = evolved

	if icon_rect:
		if evolved and _evolved_data and _evolved_data.icon:
			icon_rect.texture = _evolved_data.icon
		elif _base_data and _base_data.icon:
			icon_rect.texture = _base_data.icon
		else:
			icon_rect.texture = null


func set_tp_ready(is_ready: bool) -> void:
	if not ability_data or not _evolved_data:
		return

	_stop_evolved_tween()

	if is_ready and _evolved_data.evolution_consume == 0:
		_start_evolved_tween()
	else:
		_set_border_color(BORDER_COLOR_NORMAL)


func _start_evolved_tween() -> void:
	_evolved_tween = create_tween()
	_evolved_tween.set_loops()
	_evolved_tween.set_ease(Tween.EASE_IN_OUT)
	_evolved_tween.set_trans(Tween.TRANS_SINE)
	_evolved_tween.tween_method(_set_border_color, BORDER_COLOR_EVOLVED_A, BORDER_COLOR_EVOLVED_B, EVOLVED_FADE_DURATION)
	_evolved_tween.tween_method(_set_border_color, BORDER_COLOR_EVOLVED_B, BORDER_COLOR_EVOLVED_A, EVOLVED_FADE_DURATION)


func _stop_evolved_tween() -> void:
	if _evolved_tween and _evolved_tween.is_valid():
		_evolved_tween.kill()
	_evolved_tween = null


func _apply_visual_state() -> void:
	match _state:
		State.READY:
			if cooldown_overlay:
				cooldown_overlay.visible = false
			if cooldown_label:
				cooldown_label.visible = false
				cooldown_label.text = ""
			if lock_icon:
				lock_icon.visible = false
			modulate = Color.WHITE

		State.COOLDOWN:
			if cooldown_overlay:
				cooldown_overlay.visible = true
				cooldown_overlay.color = Color(0.2, 0.2, 0.2, 0.6)
			if cooldown_label:
				cooldown_label.visible = true
			if lock_icon:
				lock_icon.visible = false
			modulate = Color(0.55, 0.55, 0.55, 1.0)

		State.LOCKED:
			if cooldown_overlay:
				cooldown_overlay.visible = true
				cooldown_overlay.color = Color(0.15, 0.15, 0.2, 0.75)
			if cooldown_label:
				cooldown_label.visible = false
				cooldown_label.text = ""
			if lock_icon:
				lock_icon.visible = true
			modulate = Color(0.5, 0.5, 0.55, 1.0)


func _set_border_color(color: Color) -> void:
	if not panel:
		return
	if not panel.has_theme_stylebox_override("panel"):
		var base = panel.get_theme_stylebox("panel")
		if base is StyleBoxFlat:
			panel.add_theme_stylebox_override("panel", base.duplicate())
		else:
			return
	var style = panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_color = color
