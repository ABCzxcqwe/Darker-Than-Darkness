extends Control
## BgLight — solo botones eco. Fondos no tocados (mareo vía shader en .tscn).

@export var leader_is_alpha05: bool = true
@export var delay_frames: int = 2
@export var anim_fps: float = 2.0
@export var move_amplitude: Vector2 = Vector2.ZERO
@export var move_speed: float = 0.5

@onready var _btn_alpha05: Sprite2D = $Button
@onready var _btn_alpha1: Sprite2D = $Button2

var _pos_history: Array[Vector2] = []
var _frame_history: Array[int] = []
var _accum: float = 0.0
var _base_pos: Vector2 = Vector2(720, 922.5)
var _t: float = 0.0

func _ready() -> void:
	anchors_preset = Control.PRESET_FULL_RECT
	_base_pos = _get_leader().position if _get_leader() else Vector2(720, 922.5)
	for i in delay_frames + 2:
		_pos_history.append(_base_pos)
		_frame_history.append(_get_leader().frame if _get_leader() else 0)
	_apply_z_order()

func _get_leader() -> Sprite2D:
	return _btn_alpha05 if leader_is_alpha05 else _btn_alpha1

func _get_follower() -> Sprite2D:
	return _btn_alpha1 if leader_is_alpha05 else _btn_alpha05

func _apply_z_order() -> void:
	var leader := _get_leader()
	var follower := _get_follower()
	if leader and follower:
		leader.z_index = 4 if leader == _btn_alpha05 else 5
		follower.z_index = 5 if follower == _btn_alpha1 else 4

func _process(delta: float) -> void:
	_t += delta * move_speed
	var leader := _get_leader()
	var follower := _get_follower()
	if leader == null or follower == null:
		return
	_accum += delta
	if _accum >= 1.0 / max(anim_fps, 0.1):
		_accum = 0.0
		leader.frame = (leader.frame + 1) % maxi(leader.hframes, 1)
	var target_pos: Vector2 = _base_pos
	if move_amplitude != Vector2.ZERO:
		target_pos += Vector2(sin(_t * 1.1) * move_amplitude.x, cos(_t * 0.9) * move_amplitude.y)
		leader.position = target_pos
	_pos_history.push_front(leader.position)
	_frame_history.push_front(leader.frame)
	if _pos_history.size() > delay_frames + 1:
		_pos_history.pop_back()
	if _frame_history.size() > delay_frames + 1:
		_frame_history.pop_back()
	if _pos_history.size() > delay_frames:
		follower.position = _pos_history[delay_frames]
	if _frame_history.size() > delay_frames:
		follower.frame = _frame_history[delay_frames]
