# ability_button.gd
# Botón individual de habilidad. Muestra ícono, nombre y cooldown.
# El cooldown visual es iniciado por CooldownService via GameHUD.on_cooldown_started()
# y terminado cuando el contador llega a 0. No lee character_data por su cuenta.
extends Control

# ── Nodos internos ────────────────────────────────────────────────────
@onready var icon_rect:         TextureRect = $Panel/IconRect
@onready var cooldown_overlay:  ColorRect   = $Panel/CooldownOverlay
@onready var cooldown_label:    Label       = $CooldownLabel
@onready var name_label:        Label       = $CooldownLabel  # muestra display_name
@onready var key_label:         Label       = $Panel/KeyLabel
@onready var evolved_indicator: Control     = $EvolvedIndicator  # puede ser null

# ── Datos ──────────────────────────────────────────────────────────────
var ability_data:        AbilityData = null
var slot_index:          int         = 0
var _cooldown_remaining: float       = 0.0
var _is_on_cooldown:     bool        = false

func setup(data: AbilityData, index: int, key_name: String) -> void:
	ability_data = data
	slot_index   = index

	if icon_rect:
		icon_rect.texture = data.icon if data.icon else null
	if key_label:
		key_label.text = key_name
	if name_label:
		name_label.text = data.display_name

	_set_cooldown_visible(false)
	set_evolved(false)


func _process(delta: float) -> void:
	if not _is_on_cooldown:
		return

	_cooldown_remaining -= delta

	if _cooldown_remaining <= 0.0:
		_cooldown_remaining = 0.0
		_is_on_cooldown     = false
		_set_cooldown_visible(false)
		# Restaurar el nombre de la habilidad al terminar el cooldown
		if name_label and ability_data:
			name_label.text = ability_data.display_name
		return

	# Durante el cooldown: el label muestra el tiempo restante en lugar del nombre
	if name_label:
		name_label.text = "%.1f" % _cooldown_remaining
	if cooldown_label:
		cooldown_label.text = "%.1f" % _cooldown_remaining


## Llamado por GameHUD cuando CooldownService notifica el inicio del cooldown.
## duration es la duración real enviada por el servidor — puede ser variable.
func start_cooldown(duration: float) -> void:
	_cooldown_remaining = duration
	_is_on_cooldown     = true
	_set_cooldown_visible(true)


## Muestra u oculta el indicador de habilidad evolucionada.
func set_evolved(is_evolved: bool) -> void:
	if evolved_indicator:
		evolved_indicator.visible = is_evolved
	if icon_rect:
		icon_rect.modulate = Color(1.0, 0.85, 0.2) if is_evolved else Color.WHITE


func _set_cooldown_visible(active: bool) -> void:
	if cooldown_overlay:
		# En cooldown: overlay gris semitransparente
		cooldown_overlay.visible = active
		cooldown_overlay.color   = Color(0.2, 0.2, 0.2, 0.6) if active else Color(0, 0, 0, 0.39)
	if cooldown_label:
		cooldown_label.visible = active
	# El panel completo se atenúa en cooldown
	modulate = Color(0.55, 0.55, 0.55, 1.0) if active else Color.WHITE
