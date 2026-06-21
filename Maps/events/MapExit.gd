extends Area2D
class_name MapExit

@export var exit_id: String = ""
@export var open_during_lms: bool = false
@export var open_sfx: AudioStream = null
@export var close_sfx: AudioStream = null

var is_active: bool = false

@onready var _anim := $AnimatedSprite2D as AnimatedSprite2D


func _play_sfx(stream: AudioStream) -> void:
	AudioManager.play_stream(stream)


func activate() -> void:
	is_active = true
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 2 | 4
	if _anim and _anim.sprite_frames:
		_anim.play("abriendo")
	_play_sfx(open_sfx)


func deactivate() -> void:
	is_active = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	collision_layer = 0
	collision_mask = 0
	if _anim and _anim.sprite_frames:
		_anim.play("cerrando")
	_play_sfx(close_sfx)


func is_nearby(player_pos: Vector2, distance: float = 40.0) -> bool:
	return global_position.distance_to(player_pos) <= distance
