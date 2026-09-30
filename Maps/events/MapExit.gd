extends Area2D
class_name MapExit

@export var exit_id: String = ""
@export var open_during_lms: bool = false
@export var open_sfx: AudioStream = null
@export var close_sfx: AudioStream = null

var is_active: bool = false

@onready var _anim := $AnimatedSprite2D as AnimatedSprite2D


func _play_sfx(stream: AudioStream, silent: bool = false) -> void:
	if silent or stream == null:
		return
	# El servidor es la autoridad: replica el SFX a todos (call_local lo oye él también).
	if not multiplayer.is_server():
		return
	AudioManager.play_stream_2d_rpc.rpc(stream.resource_path, global_position.x, global_position.y)


func activate(silent: bool = false) -> void:
	is_active = true
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	collision_layer = 1
	collision_mask = 2 | 4
	if _anim and _anim.sprite_frames:
		_anim.play("abriendo")
	_play_sfx(open_sfx, silent)


func deactivate(silent: bool = false) -> void:
	is_active = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	collision_layer = 0
	collision_mask = 0
	if _anim and _anim.sprite_frames:
		_anim.play("cerrando")
	_play_sfx(close_sfx, silent)


func is_nearby(player_pos: Vector2, distance: float = 40.0) -> bool:
	return global_position.distance_to(player_pos) <= distance
