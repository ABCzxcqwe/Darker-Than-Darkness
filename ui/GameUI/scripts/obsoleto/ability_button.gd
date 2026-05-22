# ability_button.gd
# Botón individual de habilidad. Muestra ícono, nombre y cooldown.
extends Control

# ── Nodos internos ────────────────────────────────────────────────────
@onready var icon_rect:         TextureRect = $Panel/IconRect
@onready var cooldown_overlay:  ColorRect   = $Panel/CooldownOverlay
@onready var cooldown_label:    Label       = $Panel/CooldownLabel
@onready var key_label:         Label       = $Panel/KeyLabel

# ── Datos ──────────────────────────────────────────────────────────────
var ability_data:        AbilityData = null
var slot_index:          int         = 0
var _cooldown_remaining: float       = 0.0
var _is_on_cooldown:     bool        = false


func setup(data: AbilityData, index: int, key_name: String) -> void:
	ability_data = data
	slot_index   = index

	# Limpiar cualquier estado anterior
	_is_on_cooldown = false
	_cooldown_remaining = 0.0
	
	# Configurar según si hay habilidad o no
	if ability_data and data:
		# Hay habilidad - mostrar icono normal
		if icon_rect:
			icon_rect.texture = data.icon if data.icon else null
			icon_rect.modulate = Color.WHITE
		if cooldown_label:
			cooldown_label.text = ""
	else:
		# Slot vacío - mostrar oscurecido
		if icon_rect:
			icon_rect.texture = null
			icon_rect.modulate = Color(0.3, 0.3, 0.3, 0.5)
	
	# Configurar tecla de acceso rápido
	if key_label:
		key_label.text = key_name
	
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


## Llamado por GameHUD cuando CooldownService notifica el inicio del cooldown.
func start_cooldown(duration: float) -> void:
	if not ability_data:
		return  # Los slots vacíos no tienen cooldown
	
	_cooldown_remaining = duration
	_is_on_cooldown = true
	_set_cooldown_visible(true)


## Muestra u oculta el indicador de habilidad evolucionada.
func set_evolved(is_evolved: bool) -> void:
	if not ability_data:
		return
	
	if icon_rect:
		icon_rect.modulate = Color(1.0, 0.85, 0.2) if is_evolved else Color.WHITE


func _set_cooldown_visible(active: bool) -> void:
	if cooldown_overlay:
		cooldown_overlay.visible = active
		cooldown_overlay.color = Color(0.2, 0.2, 0.2, 0.6) if active else Color(0, 0, 0, 0.39)
	if cooldown_label:
		cooldown_label.visible = active
	# El panel completo se atenúa en cooldown
	modulate = Color(0.55, 0.55, 0.55, 1.0) if active else Color.WHITE
