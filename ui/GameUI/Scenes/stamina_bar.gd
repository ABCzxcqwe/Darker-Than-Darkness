extends Control

@onready var stam_letters:  Label       = $StamLetters
@onready var stam_track:    PanelContainer = $StamTrack
@onready var stam_fill:     ColorRect   = $StamTrack/StamFill
@onready var stam_percent:  Label       = $StamPercent

const COLOR_NORMAL: Color = Color(0.0, 0.702, 0.031, 1.0)
const COLOR_EMPTY:  Color = Color(0.9, 0.1, 0.1, 1.0)
const COLOR_WHITE:  Color = Color.WHITE

var _peer_id: int   = -1
var _max_stam: float = 100.0


func setup(peer_id: int, max_stam: float) -> void:
	_peer_id = peer_id
	_max_stam = max_stam

	var svc: Node = GameServiceLocator.get_service("StaminaService")
	if svc:
		svc.stamina_changed.connect(_on_stamina_changed)
		_update_ui(svc.get_stamina(peer_id))


func _on_stamina_changed(peer_id: int, current: float, max_s: float) -> void:
	if peer_id != _peer_id:
		return
	_max_stam = max_s
	_update_ui(current)


func _update_ui(value: float) -> void:
	if not stam_track or not stam_fill:
		return

	var ratio: float = clampf(value / _max_stam, 0.0, 1.0) if _max_stam > 0 else 0.0
	var track_h: float = stam_track.size.y

	stam_fill.size.y     = track_h * ratio
	stam_fill.position.y = track_h - stam_fill.size.y

	var is_empty: bool = ratio <= 0.01
	stam_fill.color = COLOR_EMPTY if is_empty else COLOR_NORMAL

	var text_color: Color = COLOR_EMPTY if is_empty else COLOR_WHITE
	if stam_letters:
		stam_letters.modulate = text_color
	if stam_percent:
		stam_percent.text = "%d%%" % int(ratio * 100)
		stam_percent.modulate = text_color
