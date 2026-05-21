# player_panel.gd
# Panel del jugador local — replica el layout del HUD de Deltarune:
#
#  ┌──────────────────────────────────────────────┐
#  │ [ICONO]  {NOMBRE              HP  160/ 160   |
#  |                  }  [█████████████████████]  │
#  └──────────────────────────────────────────────┘
#
# El color de la barra y el borde del panel vienen de CharacterData.theme_color.
# Estados:
#   alive  → theme_color del personaje
#   downed → naranja
#   dead   → gris
#
# Estructura de nodos esperada en PlayerPanel.tscn:
#   PlayerPanel (Control)
#   ├── BGPanel (Panel)            ← fondo oscuro con borde de color
#   └── HBoxContainer
#       ├── IconRect (TextureRect) ← icono del personaje
#       └── InfoColumn (VBoxContainer)
#           ├── NameRow (HBoxContainer)
#           │   └── NameLabel (Label)
#           └── HPRow (HBoxContainer)
#               ├── HPLabel_tag (Label)   ← texto fijo "HP"
#               ├── HPBar (ProgressBar)
#               └── HPLabel (Label)       ← "160/ 160"
extends Control

@onready var icon_rect:  TextureRect = $HBoxContainer/IconRect
@onready var name_label: Label       = $HBoxContainer/NameLabel
@onready var hp_bar:     ProgressBar = $HBoxContainer/InfoColumn/HPBar
@onready var hp_label:   Label       = $HBoxContainer/InfoColumn/NameRow/HPLabel
@onready var bg_panel:   Panel       = $BGPanel

const COLOR_DOWNED: Color = Color(1.0, 0.5,  0.0)
const COLOR_DEAD:   Color = Color(0.4, 0.4,  0.4)

var _player_node:    Node  = null
var _theme_color:    Color = Color(0.0, 0.0, 0.0, 1.0)
var _color_override: Color = Color.TRANSPARENT   # TRANSPARENT = sin override


func setup(player_node: Node) -> void:
	_player_node = player_node

	if not player_node.character_data:
		push_warning("[PlayerPanel] Player sin character_data.")
		return

	var data: CharacterData = player_node.character_data
	_theme_color = data.theme_color

	if name_label:
		name_label.text = data.display_name.to_upper()
	if icon_rect:
		icon_rect.texture = data.icon if data.icon else null
	if hp_bar:
		hp_bar.max_value = data.max_health
		hp_bar.value     = player_node.health
	if hp_label:
		hp_label.text = _format_hp(player_node.health, data.max_health)

	_apply_theme_color(_theme_color)


func _process(_delta: float) -> void:
	if not is_instance_valid(_player_node):
		return
	if not _player_node.character_data:
		return

	var max_hp: int = _player_node.character_data.max_health
	var cur_hp: int = _player_node.health

	if hp_bar:
		hp_bar.value = cur_hp
		if _color_override == Color.TRANSPARENT:
			_apply_bar_color(_player_node.health_state)
	if hp_label:
		hp_label.text = _format_hp(cur_hp, max_hp)


# ── API pública ────────────────────────────────────────────────────────

## Sobreescribe el color de la barra desde una habilidad o efecto externo.
## Pasar Color.TRANSPARENT para volver al automático según health_state.
func set_bar_color(color: Color) -> void:
	_color_override = color
	if not hp_bar:
		return
	if color == Color.TRANSPARENT:
		_apply_bar_color(_player_node.health_state if _player_node else "alive")
	else:
		hp_bar.modulate = color


# ── Internos ───────────────────────────────────────────────────────────

func _apply_theme_color(color: Color) -> void:
	_apply_bar_color("alive")
	_apply_border_color(color)


func _apply_bar_color(state: String) -> void:
	if not hp_bar:
		return
	var target_color: Color
	match state:
		"downed": target_color = COLOR_DOWNED
		"dead":   target_color = COLOR_DEAD
		_:        target_color = _theme_color # "alive" o default
	# Si hay un override manual de color, lo usamos
	if _color_override != Color.TRANSPARENT:
		target_color = _color_override
	# Accedemos al estilo "fill" (la parte de color de la barra)
	var sb = hp_bar.get_theme_stylebox("fill").duplicate()
	if sb is StyleBoxFlat:
		sb.bg_color = target_color
		hp_bar.add_theme_stylebox_override("fill", sb)


## Actualiza el color del borde del BGPanel.
## BGPanel debe tener un StyleBoxFlat en theme_override_styles/panel.
func _apply_border_color(color: Color) -> void:
	if not bg_panel:
		return
	var style := bg_panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var s := style.duplicate() as StyleBoxFlat
		s.border_color = color
		bg_panel.add_theme_stylebox_override("panel", s)


func _format_hp(cur: int, _max: int) -> String:
	return "%d/ %d" % [cur, _max]
