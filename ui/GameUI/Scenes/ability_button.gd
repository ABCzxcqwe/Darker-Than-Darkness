# ability_button.gd
# Botón individual de habilidad. Muestra ícono, nombre y cooldown.
extends Control

# ── Nodos internos ────────────────────────────────────────────────────
@onready var panel:             Panel       = $Panel
@onready var icon_rect:         TextureRect = $Panel/IconRect
@onready var cooldown_overlay:  ColorRect   = $Panel/CooldownOverlay
@onready var cooldown_label:    Label       = $Panel/CooldownLabel
@onready var key_label:         Label       = $Panel/KeyLabel

# ── Colores ────────────────────────────────────────────────────────────
## Color base del borde (naranja, igual al definido en la escena)
const BORDER_COLOR_NORMAL := Color(0.8156863, 0.4745098, 0.0, 1.0)
const BORDER_COLOR_EVOLVED_A := Color(1.0, 0.9, 0.0, 1.0)   # amarillo
const BORDER_COLOR_EVOLVED_B := Color(1.0, 1.0, 1.0, 1.0)   # blanco
const EVOLVED_FADE_DURATION  := 0.5                           # segundos por mitad del ciclo

const PANEL_BG_COLOR := Color(0, 0, 0, 0.47058824)
const PANEL_CORNER_DETAIL := 1

# ── Datos ──────────────────────────────────────────────────────────────
var ability_data:        AbilityData = null
var slot_index:          int         = 0
var _cooldown_remaining: float       = 0.0
var _is_on_cooldown:     bool        = false
var _is_evolved:         bool        = false
var _evolved_tween:      Tween       = null


func setup(data: AbilityData, index: int, key_name: String) -> void:
	ability_data = data
	slot_index   = index

	# Limpiar cualquier estado anterior
	_is_on_cooldown = false
	_cooldown_remaining = 0.0
	_stop_evolved_tween()
	_is_evolved = false

	var ability_name := data.display_name if data else "(vacío)"
	print("[AbilityButton] setup() — slot ", index, " ('", ability_name, "') tecla: ", key_name)

	# Configurar según si hay habilidad o no
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

	# Configurar tecla de acceso rápido
	if key_label:
		key_label.text = key_name

	# Crear StyleBoxFlat único por instancia (el SubResource de la escena se comparte entre todas).
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = BORDER_COLOR_NORMAL
	style.corner_detail = PANEL_CORNER_DETAIL
	style.expand_margin_left = 2.0
	style.expand_margin_top = 2.0
	style.expand_margin_right = 2.0
	style.expand_margin_bottom = 2.0
	style.anti_aliasing = false
	panel.add_theme_stylebox_override("panel", style)

	_set_cooldown_visible(false)


func _process(delta: float) -> void:
	if not _is_on_cooldown:
		return

	_cooldown_remaining -= delta

	if _cooldown_remaining <= 0.0:
		_cooldown_remaining = 0.0
		_is_on_cooldown = false
		_set_cooldown_visible(false)
		return

	if cooldown_label:
		cooldown_label.text = "%.1f" % _cooldown_remaining


# ── Cooldown ──────────────────────────────────────────────────────────

## Llamado por AbilityBar cuando CooldownService notifica el inicio del cooldown.
func start_cooldown(duration: float) -> void:
	if not ability_data:
		return
	print("[AbilityButton] Cooldown iniciado — slot ", slot_index,
		  " ('", ability_data.display_name, "') duración: ", duration, "s")
	_cooldown_remaining = duration
	_is_on_cooldown = true
	_set_cooldown_visible(true)


# ── Evolución ─────────────────────────────────────────────────────────

## Activa o desactiva el efecto visual de habilidad evolucionada.
## Evolucionado  → fade continuo amarillo <-> blanco en el borde.
## Normal        → borde naranja base sin animación.
func set_evolved(is_evolved: bool) -> void:
	if not ability_data:
		print("[AbilityButton] set_evolved(", is_evolved, ") ignorado — slot ",
			  slot_index, " sin AbilityData.")
		return
	if _is_evolved == is_evolved:
		print("[AbilityButton] set_evolved(", is_evolved, ") ignorado — slot ",
			  slot_index, " ('", ability_data.display_name, "') ya estaba en ese estado.")
		return

	_is_evolved = is_evolved
	_stop_evolved_tween()

	if is_evolved:
		print("[AbilityButton] Slot ", slot_index, " ('", ability_data.display_name,
			  "') EVOLUCIONADO — iniciando fade amarillo/blanco.")
		_start_evolved_tween()
	else:
		print("[AbilityButton] Slot ", slot_index, " ('", ability_data.display_name,
			  "') devuelto a NORMAL — borde naranja.")
		_set_border_color(BORDER_COLOR_NORMAL)


func _start_evolved_tween() -> void:
	_evolved_tween = create_tween()
	_evolved_tween.set_loops()          # loop infinito
	_evolved_tween.set_ease(Tween.EASE_IN_OUT)
	_evolved_tween.set_trans(Tween.TRANS_SINE)

	# amarillo -> blanco -> amarillo, ciclo continuo
	_evolved_tween.tween_method(
		_set_border_color,
		BORDER_COLOR_EVOLVED_A,
		BORDER_COLOR_EVOLVED_B,
		EVOLVED_FADE_DURATION
	)
	_evolved_tween.tween_method(
		_set_border_color,
		BORDER_COLOR_EVOLVED_B,
		BORDER_COLOR_EVOLVED_A,
		EVOLVED_FADE_DURATION
	)


func _stop_evolved_tween() -> void:
	if _evolved_tween and _evolved_tween.is_valid():
		_evolved_tween.kill()
	_evolved_tween = null


# ── Internos ──────────────────────────────────────────────────────────

func _set_border_color(color: Color) -> void:
	if not panel:
		return
	# Si aún no tenemos override propio, duplicamos el recurso base para
	# no modificar el StyleBoxFlat compartido entre todos los botones.
	if not panel.has_theme_stylebox_override("panel"):
		var base = panel.get_theme_stylebox("panel")
		if base is StyleBoxFlat:
			panel.add_theme_stylebox_override("panel", base.duplicate())
		else:
			print("[AbilityButton] _set_border_color: StyleBox del panel no es StyleBoxFlat — slot ", slot_index)
			return
	var style = panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_color = color


func _set_cooldown_visible(active: bool) -> void:
	if cooldown_overlay:
		cooldown_overlay.visible = active
		cooldown_overlay.color = Color(0.2, 0.2, 0.2, 0.6) if active else Color(0, 0, 0, 0.39)
	if cooldown_label:
		cooldown_label.visible = active
	# El panel completo se atenúa en cooldown
	modulate = Color(0.55, 0.55, 0.55, 1.0) if active else Color.WHITE
