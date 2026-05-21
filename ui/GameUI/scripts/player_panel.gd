# player_panel.gd
# Panel de vida del jugador local.
#
# Estructura de nodos esperada en PlayerPanel.tscn:
#   PlayerPanel (PanelContainer)
#   └── HBoxContainer
#       ├── IconRect (TextureRect)
#       ├── InfoColumn (VBoxContainer)
#       │   ├── NameLabel (Label)
#       │   └── HpRow (HBoxContainer)
#       │       ├── HpTag (Label)       ← texto fijo "HP"
#       │       └── HpBar (ProgressBar)
#       └── HpNumbers (Label)           ← "128/ 160"
#
# El borde inferior se elimina en el StyleBoxFlat del PanelContainer
# desde el inspector (border_width_bottom = 0).
extends PanelContainer

@onready var icon_rect:   TextureRect = $HBoxContainer/IconRect
@onready var name_label:  Label       = $HBoxContainer/NameLabel
@onready var hp_bar:      ProgressBar = $HBoxContainer/InfoColumn/HpRow/HpBar
@onready var hp_numbers:  Label       = $HBoxContainer/InfoColumn/HpNumbers

const COLOR_OVER_MAX: Color = Color(0.9, 0.2, 0.9)  # magenta: HP sobre el máximo

var _peer_id:      int   = -1
var _max_hp:       int   = 100
var _theme_color:  Color = Color(0.27, 0.78, 0.95)


func setup(player_node: Node) -> void:
	if not player_node.character_data:
		push_warning("[PlayerPanel] Player sin character_data.")
		return

	_peer_id     = player_node.get_multiplayer_authority()
	var data: CharacterData = player_node.character_data
	_max_hp      = data.max_health
	_theme_color = data.theme_color

	if name_label:
		name_label.text = data.display_name.to_upper()
	if icon_rect:
		icon_rect.texture = data.icon if data.icon else null
	if hp_bar:
		hp_bar.max_value = _max_hp
		hp_bar.value     = player_node.health
	if hp_numbers:
		hp_numbers.text = _fmt(player_node.health, _max_hp)

	_apply_border_color(_theme_color)
	_apply_bar_color(player_node.health)

	# Conectar señales de HealthService
	var hs: Node = GameServiceLocator.get_service("HealthService")
	if hs:
		hs.health_changed.connect(_on_health_changed)
		hs.player_state_changed.connect(_on_state_changed)


func _on_health_changed(peer_id: int, current_hp: int, max_hp: int) -> void:
	if peer_id != _peer_id:
		return
	
	# Validar que el panel aún exista
	if not is_inside_tree():
		return
	
	_max_hp = max_hp
	if hp_bar and is_instance_valid(hp_bar):
		hp_bar.max_value = max_hp
		hp_bar.value = current_hp
	if hp_numbers and is_instance_valid(hp_numbers):
		hp_numbers.text = _fmt(current_hp, max_hp)
	_apply_bar_color(current_hp)


func _on_state_changed(peer_id: int, state: String) -> void:
	if peer_id != _peer_id:
		return
	match state:
		"downed":
			_apply_border_color(Color(1.0, 0.5, 0.0))  # naranja
		"dead":
			_apply_border_color(Color(0.3, 0.3, 0.3))  # gris
		"alive":
			_apply_border_color(_theme_color)


# ── Internos ──────────────────────────────────────────────────────────

func _apply_bar_color(current_hp: int) -> void:
	if not hp_bar:
		return
	# Solo cambia a magenta si tiene HP por encima del máximo base
	var color: Color = COLOR_OVER_MAX if current_hp > _max_hp else _theme_color
	var sb = hp_bar.get_theme_stylebox("fill")
	if sb == null:
		return
	sb = sb.duplicate()
	if sb is StyleBoxFlat:
		sb.bg_color = color
		hp_bar.add_theme_stylebox_override("fill", sb)


func _apply_border_color(color: Color) -> void:
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var s := style.duplicate() as StyleBoxFlat
		s.border_color = color
		add_theme_stylebox_override("panel", s)


func _fmt(cur: int, max_val: int) -> String:
	return "%d/ %d" % [cur, max_val]
