# ally_bar.gd
# Barra de vida de un aliado. Una instancia por cada aliado en AlliesPanel.
#
# Estructura de nodos esperada en AllyBar.tscn:
#   AllyBar (PanelContainer)
#   └── HBoxContainer
#       ├── AllyIcon (ColorRect)   ← pequeño cuadrado del color del personaje
#       ├── AllyInfo (VBoxContainer)
#       │   ├── AllyName (Label)
#       │   └── AllyHpBar (ProgressBar)
extends PanelContainer

@onready var ally_icon:   ColorRect   = $HBoxContainer/AllyIcon
@onready var ally_name:   Label       = $HBoxContainer/AllyInfo/AllyName
@onready var ally_hp_bar: ProgressBar = $HBoxContainer/AllyInfo/AllyHpBar

var _peer_id:     int   = -1
var _theme_color: Color = Color.WHITE


func setup(player_node: Node) -> void:
	if not player_node.character_data:
		push_warning("[AllyBar] Player sin character_data.")
		return

	_peer_id     = player_node.get_multiplayer_authority()
	var data: CharacterData = player_node.character_data
	_theme_color = data.theme_color

	if ally_icon:
		ally_icon.color = _theme_color
	if ally_name:
		ally_name.text = data.display_name.to_upper()
	if ally_hp_bar:
		ally_hp_bar.max_value = data.max_health
		ally_hp_bar.value     = player_node.health
		_apply_bar_color("alive")

	_apply_border_color(_theme_color)

	var hs: Node = GameServiceLocator.get_service("HealthService")
	if hs:
		hs.health_changed.connect(_on_health_changed)
		hs.player_state_changed.connect(_on_state_changed)


func _on_health_changed(peer_id: int, current_hp: int, max_hp: int) -> void:
	if peer_id != _peer_id:
		return
	if ally_hp_bar:
		ally_hp_bar.max_value = max_hp
		ally_hp_bar.value     = current_hp


func _on_state_changed(peer_id: int, state: String) -> void:
	if peer_id != _peer_id:
		return
	_apply_bar_color(state)
	match state:
		"downed":
			if ally_name: ally_name.modulate = Color(1.0, 0.5, 0.0)
			_apply_border_color(Color(1.0, 0.5, 0.0))
		"dead":
			if ally_name: ally_name.modulate = Color(0.3, 0.3, 0.3)
			_apply_border_color(Color(0.2, 0.2, 0.2))
			modulate.a = 0.35
		"alive":
			if ally_name: ally_name.modulate = Color.WHITE
			_apply_border_color(_theme_color)
			modulate.a = 1.0


# ── Internos ──────────────────────────────────────────────────────────

func _apply_bar_color(state: String) -> void:
	if not ally_hp_bar:
		return
	var color: Color
	match state:
		"downed": color = Color(1.0, 0.5, 0.0)
		"dead":   color = Color(0.3, 0.3, 0.3)
		_:        color = _theme_color
	var sb = ally_hp_bar.get_theme_stylebox("fill").duplicate()
	if sb is StyleBoxFlat:
		sb.bg_color = color
		ally_hp_bar.add_theme_stylebox_override("fill", sb)


func _apply_border_color(color: Color) -> void:
	var style = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var s := style.duplicate() as StyleBoxFlat
		s.border_color = color
		add_theme_stylebox_override("panel", s)
