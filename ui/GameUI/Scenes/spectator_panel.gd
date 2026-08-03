extends PanelContainer

signal prev_requested()
signal next_requested()

@onready var icon_rect:  AnimatedIcon = $VBoxContainer/TargetRow/TargetInfo/IconRect
@onready var name_label: Label       = $VBoxContainer/TargetRow/TargetInfo/VBoxContainer/NameLabel
@onready var hp_bar:     ProgressBar = $VBoxContainer/TargetRow/TargetInfo/VBoxContainer/HpRow/HpBar
@onready var prev_btn:   Button      = $VBoxContainer/TargetRow/PrevButton
@onready var next_btn:   Button      = $VBoxContainer/TargetRow/NextButton

var _spectating_peer_id: int = -1


func _ready() -> void:
	prev_btn.pressed.connect(func(): prev_requested.emit())
	next_btn.pressed.connect(func(): next_requested.emit())


func set_target(peer_id: int, display_name: String, player_name: String, frames: SpriteFrames = null, fallback_tex: Texture2D = null) -> void:
	_spectating_peer_id = peer_id
	if icon_rect:
		icon_rect.setup(frames, "icon", fallback_tex)
	if name_label:
		name_label.text = player_name if player_name != "" else display_name


func set_hp(current_hp: int, max_hp: int) -> void:
	if not hp_bar:
		return
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp

	var ratio := float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
	if ratio > 0.5:
		hp_bar.modulate = Color(0.4, 1, 0.4, 1)
	elif ratio > 0.2:
		hp_bar.modulate = Color(1, 0.8, 0.2, 1)
	else:
		hp_bar.modulate = Color(1, 0.2, 0.2, 1)


func clear() -> void:
	_spectating_peer_id = -1
	if name_label:
		name_label.text = "—"
	if icon_rect:
		icon_rect.setup(null, "icon", null)
	if hp_bar:
		hp_bar.value = 0
		hp_bar.modulate = Color.WHITE
