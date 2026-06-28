extends Control

@onready var panel:             Panel       = $Panel
@onready var icon_rect:         TextureRect = $Panel/IconRect
@onready var cooldown_overlay:  ColorRect   = $Panel/CooldownOverlay
@onready var cooldown_label:    Label       = $Panel/CooldownLabel
@onready var key_label:         Label       = $Panel/KeyLabel
@onready var lock_icon:         TextureRect = $Panel/LockIcon if has_node("Panel/LockIcon") else null
@onready var border_fill_mask:   Control = $BorderFillMask
@onready var border_fill_orange: Panel   = $BorderFillMask/BorderFillOrange
@onready var border_fill_yellow: Panel   = $BorderFillMask/BorderFillYellow

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
var _base_data:          AbilityData = null
var _evolved_data:       AbilityData = null

var _peer_id:            int         = -1
var _tp_service:         Node        = null
var _last_known_tp:      float       = 0.0
var _last_t1_ratio:      float       = 0.0
var _last_t2_ratio:      float       = 0.0
var _fill_tween:         Tween       = null


func setup(data: AbilityData, index: int, key_name: String, peer_id: int = -1) -> void:
	ability_data = data
	slot_index   = index
	_base_data   = data
	_evolved_data = data.evolved_version if data and data.evolved_version else null
	_peer_id     = peer_id

	_state = State.READY
	_cooldown_remaining = 0.0
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

	# El panel base ya no dibuja el borde cuando hay una habilidad real —
	# el borde de habilidades con datos lo dibuja BorderFillRect (relleno por TP).
	# Para un slot vacío, mantenemos el borde estático de siempre.
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.set_corner_radius_all(3)
	style.corner_detail = PANEL_CORNER_DETAIL
	style.expand_margin_left = 2.0
	style.expand_margin_top = 2.0
	style.expand_margin_right = 2.0
	style.expand_margin_bottom = 2.0
	style.anti_aliasing = false

	if ability_data:
		style.border_width_left = 0
		style.border_width_top = 0
		style.border_width_right = 0
		style.border_width_bottom = 0
	else:
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = BORDER_COLOR_NORMAL

	panel.add_theme_stylebox_override("panel", style)

	_apply_visual_state()
	_setup_tp_tracking()


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_border_fill(_last_t1_ratio, _last_t2_ratio)


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

	# Cambió la habilidad "activa" (base <-> evolucionada), así que el costo
	# de TP a comparar también cambió — recalculamos el relleno ya mismo.
	_update_tp_fill(_last_known_tp)


## Mantenido por compatibilidad con EvolutionService/ability_bar — ya no hace
## falta que nos digan "is_ready" desde afuera, el botón escucha el TPService
## directamente y calcula su propio estado en _update_tp_fill().
func set_tp_ready(_is_ready: bool) -> void:
	pass


# --- Relleno de borde según TP (aplica a toda habilidad con datos) ---

func _setup_tp_tracking() -> void:
	_disconnect_tp_service()
	_stop_fill_tween()

	if not ability_data:
		if border_fill_mask:
			border_fill_mask.visible = false
		return

	if border_fill_mask:
		border_fill_mask.visible = true

	var orange_style := StyleBoxFlat.new()
	orange_style.bg_color = Color(0, 0, 0, 0)
	orange_style.border_width_left = 2
	orange_style.border_width_top = 0
	orange_style.border_width_right = 2
	orange_style.border_width_bottom = 2
	orange_style.set_corner_radius_all(3)
	orange_style.corner_detail = PANEL_CORNER_DETAIL
	orange_style.anti_aliasing = false
	orange_style.border_color = BORDER_COLOR_NORMAL
	if border_fill_orange:
		border_fill_orange.add_theme_stylebox_override("panel", orange_style)
		border_fill_orange.size = Vector2.ZERO
		border_fill_orange.position = Vector2.ZERO

	var yellow_style := StyleBoxFlat.new()
	yellow_style.bg_color = Color(0, 0, 0, 0)
	yellow_style.border_width_left = 2
	yellow_style.border_width_top = 0
	yellow_style.border_width_right = 2
	yellow_style.border_width_bottom = 2
	yellow_style.set_corner_radius_all(3)
	yellow_style.corner_detail = PANEL_CORNER_DETAIL
	yellow_style.anti_aliasing = false
	yellow_style.border_color = BORDER_COLOR_EVOLVED_A
	if border_fill_yellow:
		border_fill_yellow.add_theme_stylebox_override("panel", yellow_style)
		border_fill_yellow.size = Vector2.ZERO
		border_fill_yellow.position = Vector2.ZERO
		border_fill_yellow.visible = false

	_last_t1_ratio = 0.0
	_last_t2_ratio = 0.0

	_tp_service = GameServiceLocator.get_service("TPService")
	if _tp_service:
		_tp_service.tp_changed.connect(_on_tp_changed)
		_update_tp_fill(_tp_service.get_tp_for_peer(_peer_id))
	else:
		push_warning("[AbilityButton] TPService no disponible — slot " + str(slot_index))
		_update_tp_fill(0.0)


func _disconnect_tp_service() -> void:
	if _tp_service and _tp_service.tp_changed.is_connected(_on_tp_changed):
		_tp_service.tp_changed.disconnect(_on_tp_changed)
	_tp_service = null


func _on_tp_changed(peer_id: int, current_tp: float, _max_tp: float) -> void:
	if _peer_id != -1 and peer_id != _peer_id:
		return
	_update_tp_fill(current_tp)


func _update_tp_fill(current_tp: float) -> void:
	if not ability_data:
		return

	_last_known_tp = current_tp

	var base_cost: float = _base_data.tp_cost if _base_data else 0.0
	var is_permanent: bool = _evolved_data and _evolved_data.evolution_consume == 1

	# -- Tramo 1 (naranja): de 0 a tp_cost base
	var t1_ratio: float = clampf(current_tp / base_cost, 0.0, 1.0) if base_cost > 0 else 1.0

	# -- Tramo 2 (amarillo): solo si evolucionado, no permanente, y tramo 1 completo
	var t2_ratio: float = 0.0
	var in_tramo_2: bool = false
	if _is_evolved and _evolved_data and not is_permanent and base_cost > 0:
		var t2_total: float = max(_evolved_data.tp_cost - base_cost, 0.0)
		if t2_total > 0 and current_tp >= base_cost:
			t2_ratio = clampf((current_tp - base_cost) / t2_total, 0.0, 1.0)
			in_tramo_2 = true

	_last_t1_ratio = t1_ratio
	_last_t2_ratio = t2_ratio
	_apply_border_fill(t1_ratio, t2_ratio)

	# -- Visibilidad del yellow fill
	if border_fill_yellow:
		border_fill_yellow.visible = in_tramo_2

	# -- Icono
	var t1_complete: bool = t1_ratio >= 1.0
	var t2_complete: bool = t2_ratio >= 1.0

	if icon_rect:
		if is_permanent or not _is_evolved:
			icon_rect.visible = t1_complete
		else:
			if t2_complete:
				var evo_icon: Texture2D = _evolved_data.icon if _evolved_data and _evolved_data.icon else null
				icon_rect.texture = evo_icon if evo_icon else (_base_data.icon if _base_data else null)
				icon_rect.visible = true
			else:
				icon_rect.texture = _base_data.icon if _base_data else null
				icon_rect.visible = t1_complete

	# -- Parpadeo solo si tramo 2 completo y evolucionado no-permanente
	if t2_complete and _is_evolved and not is_permanent:
		if not (_fill_tween and _fill_tween.is_valid()):
			_start_fill_tween()
	else:
		_stop_fill_tween()
		_set_fill_border_color(BORDER_COLOR_NORMAL)
		if border_fill_yellow:
			_set_panel_border_color(border_fill_yellow, BORDER_COLOR_EVOLVED_A)


func _apply_border_fill(t1_ratio: float, t2_ratio: float) -> void:
	var full_size: Vector2 = size if size.y > 0.0 else border_fill_mask.size

	if border_fill_orange:
		var h1: float = full_size.y * t1_ratio
		border_fill_orange.size     = Vector2(full_size.x, h1)
		border_fill_orange.position = Vector2(0.0, full_size.y - h1)
		_set_top_border(border_fill_orange, t1_ratio >= 1.0)

	if border_fill_yellow and border_fill_yellow.visible:
		var h2: float = full_size.y * t2_ratio
		border_fill_yellow.size     = Vector2(full_size.x, h2)
		border_fill_yellow.position = Vector2(0.0, full_size.y - h2)
		_set_top_border(border_fill_yellow, t2_ratio >= 1.0)


func _start_fill_tween() -> void:
	_fill_tween = create_tween()
	_fill_tween.set_loops()
	_fill_tween.set_ease(Tween.EASE_IN_OUT)
	_fill_tween.set_trans(Tween.TRANS_SINE)
	_fill_tween.tween_method(_set_yellow_border_color, BORDER_COLOR_EVOLVED_A, BORDER_COLOR_EVOLVED_B, EVOLVED_FADE_DURATION)
	_fill_tween.tween_method(_set_yellow_border_color, BORDER_COLOR_EVOLVED_B, BORDER_COLOR_EVOLVED_A, EVOLVED_FADE_DURATION)


func _stop_fill_tween() -> void:
	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()
	_fill_tween = null


func _set_fill_border_color(color: Color) -> void:
	if not border_fill_orange:
		return
	if not border_fill_orange.has_theme_stylebox_override("panel"):
		return
	var style = border_fill_orange.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_color = color


func _set_panel_border_color(panel: Panel, color: Color) -> void:
	if not panel:
		return
	if not panel.has_theme_stylebox_override("panel"):
		return
	var style = panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_color = color


func _set_yellow_border_color(color: Color) -> void:
	_set_panel_border_color(border_fill_yellow, color)


func _set_top_border(panel: Panel, visible: bool) -> void:
	if not panel:
		return
	if not panel.has_theme_stylebox_override("panel"):
		return
	var style = panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_width_top = 2 if visible else 0


func _exit_tree() -> void:
	_disconnect_tp_service()
	_stop_fill_tween()


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
