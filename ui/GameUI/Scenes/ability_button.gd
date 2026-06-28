extends Control

@onready var panel:              Panel       = $Panel
@onready var icon_rect:          TextureRect = $Panel/IconRect
@onready var cooldown_overlay:   ColorRect   = $Panel/CooldownOverlay
@onready var cooldown_label:     Label       = $Panel/CooldownLabel
@onready var key_label:          Label       = $Panel/KeyLabel
@onready var lock_icon:          TextureRect = $Panel/LockIcon if has_node("Panel/LockIcon") else null
@onready var border_fill_mask:   Control     = $BorderFillMask
@onready var base_fill_rect:     Panel       = $BorderFillMask/BaseFillRect
@onready var evolution_fill_rect: Panel      = $BorderFillMask/EvolutionFillRect

const BORDER_COLOR_NORMAL    := Color(0.8156863, 0.4745098, 0.0, 1.0)
const BORDER_COLOR_EVOLVED_A := Color(1.0, 0.9, 0.0, 1.0)
const BORDER_COLOR_EVOLVED_B := Color(1.0, 1.0, 1.0, 1.0)
const EVOLVED_FADE_DURATION   := 0.5

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
var _ratio_base:         float       = 0.0
var _ratio_evo:          float       = 0.0
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
	# el borde de habilidades con datos lo dibujan BaseFillRect/EvolutionFillRect
	# (relleno por TP). Para un slot vacío, mantenemos el borde estático de siempre.
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


## Se mantiene por compatibilidad con EvolutionService/ability_bar (que siguen
## emitiendo on_slot_evolved/on_slot_devolved). Ya NO controla el ícono — eso
## ahora lo decide _update_tp_fill() según el tramo 2 (más confiable, porque
## usa el TP real en vez de depender de un RPC aparte).
func set_evolved(evolved: bool) -> void:
	if not ability_data:
		return
	if _is_evolved == evolved:
		return
	_is_evolved = evolved
	_update_tp_fill(_last_known_tp)


## Igual, se mantiene por compatibilidad pero ya no hace nada — el botón
## escucha el TPService directo y calcula su propio estado.
func set_tp_ready(_is_ready: bool) -> void:
	pass


# --- Relleno de borde por TP, en dos tramos (base -> evolución) ---

func _setup_tp_tracking() -> void:
	_disconnect_tp_service()
	_stop_fill_tween()

	if not ability_data:
		if border_fill_mask:
			border_fill_mask.visible = false
		return

	if border_fill_mask:
		border_fill_mask.visible = true
	if icon_rect:
		icon_rect.visible = false

	_build_fill_style(base_fill_rect, BORDER_COLOR_NORMAL)
	_build_fill_style(evolution_fill_rect, BORDER_COLOR_EVOLVED_A)
	if evolution_fill_rect:
		evolution_fill_rect.visible = false

	_ratio_base = 0.0
	_ratio_evo  = 0.0

	_tp_service = GameServiceLocator.get_service("TPService")
	if _tp_service:
		_tp_service.tp_changed.connect(_on_tp_changed)
		_update_tp_fill(_tp_service.get_tp_for_peer(_peer_id))
	else:
		push_warning("[AbilityButton] TPService no disponible — slot " + str(slot_index))


func _build_fill_style(rect: Panel, color: Color) -> void:
	if not rect:
		return
	var fstyle := StyleBoxFlat.new()
	fstyle.bg_color = Color(0, 0, 0, 0)
	fstyle.border_width_left = 2
	fstyle.border_width_top = 0
	fstyle.border_width_right = 2
	fstyle.border_width_bottom = 2
	fstyle.set_corner_radius_all(3)
	fstyle.corner_detail = PANEL_CORNER_DETAIL
	fstyle.anti_aliasing = false
	fstyle.border_color = color
	rect.add_theme_stylebox_override("panel", fstyle)
	rect.size = Vector2.ZERO
	rect.position = Vector2.ZERO


func _disconnect_tp_service() -> void:
	if _tp_service and _tp_service.tp_changed.is_connected(_on_tp_changed):
		_tp_service.tp_changed.disconnect(_on_tp_changed)
	_tp_service = null


func _on_tp_changed(peer_id: int, current_tp: float, _max_tp: float) -> void:
	if peer_id != _peer_id:
		return
	_update_tp_fill(current_tp)


func _update_tp_fill(current_tp: float) -> void:
	if not ability_data or not _base_data:
		return

	_last_known_tp = current_tp

	var has_evolution: bool = _evolved_data != null
	var is_permanent: bool  = has_evolution and _evolved_data.evolution_consume == 1
	# Si la evolución es permanente y ya se disparó, el slot adopta la
	# identidad de la habilidad evolucionada por completo: mismo medidor
	# naranja de siempre, pero usando su costo y su ícono (reemplaza al base).
	var permanent_swapped: bool = is_permanent and _is_evolved

	# --- Tramo 1: habilidad "activa" (base, o evolucionada si ya cambió para siempre) ---
	var active_data: AbilityData = _evolved_data if permanent_swapped else _base_data
	var base_cost: float = active_data.tp_cost
	_ratio_base = clampf(current_tp / base_cost, 0.0, 1.0) if base_cost > 0.0 else 1.0

	_apply_growing_border(base_fill_rect, _ratio_base)

	if icon_rect:
		icon_rect.visible = _ratio_base >= 1.0
		icon_rect.texture = active_data.icon if active_data.icon else null

	if not has_evolution or permanent_swapped or is_permanent:
		# Sin evolución, ya evolucionada para siempre, o evolución permanente
		# que aún no se disparó: ninguno de estos casos usa el tramo 2.
		if evolution_fill_rect:
			evolution_fill_rect.visible = false
		_stop_fill_tween()
		_ratio_evo = 0.0
		return

	# --- Tramo 2: evolución temporal. Empieza recién cuando el tramo 1 cerró. ---
	if evolution_fill_rect:
		evolution_fill_rect.visible = true

	var evolved_cost: float = _evolved_data.tp_cost

	if _ratio_base >= 1.0:
		if evolved_cost > base_cost:
			_ratio_evo = clampf((current_tp - base_cost) / (evolved_cost - base_cost), 0.0, 1.0)
		else:
			_ratio_evo = 1.0 if current_tp >= evolved_cost else 0.0
	else:
		_ratio_evo = 0.0

	_apply_growing_border(evolution_fill_rect, _ratio_evo)

	if icon_rect and _ratio_evo >= 1.0:
		icon_rect.texture = _evolved_data.icon if _evolved_data.icon else _base_data.icon

	if _ratio_evo >= 1.0:
		if not (_fill_tween and _fill_tween.is_valid()):
			_start_fill_tween()
	else:
		_stop_fill_tween()
		_set_fill_border_color(BORDER_COLOR_EVOLVED_A)


## Hace crecer `rect` de abajo hacia arriba según `ratio` (0..1). El borde
## superior se mantiene oculto (ancho 0) hasta que el tramo llega al 100%;
## ahí "cierra" el recuadro de golpe.
func _apply_growing_border(rect: Panel, ratio: float) -> void:
	if not rect:
		return

	var full_size: Vector2 = size if size.y > 0.0 else border_fill_mask.size
	var clamped: float = clampf(ratio, 0.0, 1.0)
	var h: float = full_size.y * clamped

	rect.size     = Vector2(full_size.x, h)
	rect.position = Vector2(0.0, full_size.y - h)

	var style = rect.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_width_top = 2 if clamped >= 1.0 else 0


func _start_fill_tween() -> void:
	_fill_tween = create_tween()
	_fill_tween.set_loops()
	_fill_tween.set_ease(Tween.EASE_IN_OUT)
	_fill_tween.set_trans(Tween.TRANS_SINE)
	_fill_tween.tween_method(_set_fill_border_color, BORDER_COLOR_EVOLVED_A, BORDER_COLOR_EVOLVED_B, EVOLVED_FADE_DURATION)
	_fill_tween.tween_method(_set_fill_border_color, BORDER_COLOR_EVOLVED_B, BORDER_COLOR_EVOLVED_A, EVOLVED_FADE_DURATION)


func _stop_fill_tween() -> void:
	if _fill_tween and _fill_tween.is_valid():
		_fill_tween.kill()
	_fill_tween = null


func _set_fill_border_color(color: Color) -> void:
	if not evolution_fill_rect:
		return
	if not evolution_fill_rect.has_theme_stylebox_override("panel"):
		return
	var style = evolution_fill_rect.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_color = color


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
