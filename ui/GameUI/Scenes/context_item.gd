# context_item.gd
# Ítem individual del menú contextual de selección de objetivo.
# Solo muestra nombre e icono del personaje — sin HP.
#
# Estructura de nodos esperada en ContextItem.tscn:
#   ContextItem (PanelContainer)
#   └── HBoxContainer
#       ├── IconRect (TextureRect)  ← icono del personaje (opcional)
#       └── NameLabel (Label)       ← nombre del personaje en mayúsculas
extends PanelContainer

@onready var icon_rect:  TextureRect = $HBoxContainer/IconRect
@onready var name_label: Label       = $HBoxContainer/NameLabel


const COLOR_SELECTED: Color = Color(1.0, 0.871, 0.0, 1.0)   # amarillo TP: #FFDE00
const COLOR_IDLE:     Color = Color(0.816, 0.475, 0.0, 1.0)  # naranja original

var _peer_id:  int  = -1
var _selected: bool = false
var _style: StyleBoxFlat = null

signal item_clicked(peer_id: int)


func setup(peer_id: int, display_name: String, icon: Texture2D) -> void:
	_peer_id = peer_id
	if name_label:
		name_label.text = display_name.to_upper()
	if icon_rect:
		if icon:
			icon_rect.texture = icon
			icon_rect.visible = true
		else:
			icon_rect.visible = false
	set_selected(false)

func set_selected(selected: bool) -> void:
	_selected = selected
	if not _style:
		var base = get_theme_stylebox("panel")
		if base is StyleBoxFlat:
			_style = base.duplicate() as StyleBoxFlat
			add_theme_stylebox_override("panel", _style)
	if _style:
		_style.border_color = COLOR_SELECTED if selected else COLOR_IDLE

func get_peer_id() -> int:
	return _peer_id


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		item_clicked.emit(_peer_id)
