# tp_bar.gd
# Barra de TP vertical con indicadores de llenado.
# Se ubica al centro izquierda de la pantalla (anchor center-left).
#
# Estructura de nodos esperada en TpBar.tscn:
#   TpBar (Control)
#   ├── TpArrowTop (Control)       ← triángulo decorativo apuntando hacia arriba
#   ├── TpLetters (Label)          ← texto "T\nP"
#   ├── TpTrack (PanelContainer)
#   │   └── TpFill (ColorRect)     ← se ajusta en altura para simular llenado
#   ├── TpPercent (Label)          ← "65%" o "MAX"
#   └── TpArrowBottom (Control)    ← triángulo decorativo apuntando hacia abajo
extends Control

@onready var tp_letters:  Label       = $TpLetters
@onready var tp_track:    PanelContainer = $TpTrack
@onready var tp_fill:     ColorRect   = $TpTrack/TpFill
@onready var tp_percent:  Label       = $TpPercent

const COLOR_NORMAL: Color = Color(0.8,  0.27, 1.0)   # morado
const COLOR_MAX:    Color = Color(1.0,  0.87, 0.0)   # amarillo al llegar al máximo

var _peer_id: int   = -1
var _max_tp:  float = 100.0


func setup(peer_id: int, max_tp: float) -> void:
	_peer_id = peer_id
	_max_tp  = max_tp

	var tp_service: Node = GameServiceLocator.get_service("TPService")
	if tp_service:
		tp_service.tp_changed.connect(_on_tp_changed)
		_update_ui(tp_service.get_tp_for_peer(peer_id))


func _on_tp_changed(peer_id: int, current_tp: float, max_tp: float) -> void:
	if peer_id != _peer_id:
		return
	_max_tp = max_tp
	_update_ui(current_tp)


func _update_ui(value: float) -> void:
	if not tp_track or not tp_fill:
		return

	var ratio: float = clampf(value / _max_tp, 0.0, 1.0) if _max_tp > 0 else 0.0
	var track_h: float = tp_track.size.y

	# Ajustamos la altura y posición de TpFill para simular llenado desde abajo
	tp_fill.size.y       = track_h * ratio
	tp_fill.position.y   = track_h - tp_fill.size.y

	var is_max: bool = ratio >= 1.0
	var color: Color = COLOR_MAX if is_max else COLOR_NORMAL

	tp_fill.color = color

	if tp_letters:
		tp_letters.modulate = color
	if tp_percent:
		tp_percent.text     = "MAX" if is_max else "%d%%" % int(ratio * 100)
		tp_percent.modulate = color
