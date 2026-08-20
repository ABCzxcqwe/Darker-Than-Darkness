# JevilPhantom.gd
# Escena de prueba del efecto "fase 2/5" de Jevil (Deltarune):
# desfase al azar + imágenes residuales que siguen su animación y se desvanecen.
# Es autónoma: no depende de autoloads ni de multiplayer. Correr con F6.
extends Node2D

const JEVIL_FRAMES := preload("res://Characters/Jevil/animations.tres")

@export var move_speed: float = 320.0
@export var jitter_amp: float = 4.0

@export var spawn_interval: float = 0.08
@export var max_phantoms: int = 16
@export var phantom_lifetime: float = 0.8
@export var phantom_alpha: float = 0.45
@export var phantom_speed_scale: float = 0.6
@export var min_radius: float = 60.0
@export var radius: float = 150.0
@export var drift_px_s: float = 20.0
@export var blink_min_interval: float = 0.5
@export var blink_max_interval: float = 1.6
@export var blink_duration: float = 0.14
@export var blink_fade_time: float = 0.2

@onready var source_sprite: AnimatedSprite2D = $SourceSprite

var _dir: Vector2
var _spawn_timer: float = 0.0
var _phantoms: Array = []
var _blink_timer: float = 0.0
var _next_blink_at: float = 0.0
var _hidden_timer: float = -1.0
var _source_base_alpha: float = 1.0


func _ready() -> void:
	randomize()
	source_sprite.sprite_frames = JEVIL_FRAMES
	if JEVIL_FRAMES.has_animation("emote_1"):
		source_sprite.play("emote_1")
	_dir = Vector2.from_angle(randf() * TAU).normalized()
	position = _random_position()

func _process(delta: float) -> void:
	_move_source(delta)
	_apply_jitter(delta)
	_spawn_phantoms(delta)
	_update_blink(delta)


func _move_source(delta: float) -> void:
	position += _dir * move_speed * delta

	var vp := get_viewport_rect().size
	var margin := 60.0
	if position.x < margin and _dir.x < 0.0:
		_dir.x = absf(_dir.x)
	elif position.x > vp.x - margin and _dir.x > 0.0:
		_dir.x = -absf(_dir.x)
	if position.y < margin and _dir.y < 0.0:
		_dir.y = absf(_dir.y)
	elif position.y > vp.y - margin and _dir.y > 0.0:
		_dir.y = -absf(_dir.y)


func _apply_jitter(_delta: float) -> void:
	source_sprite.position = Vector2(
		randf_range(-jitter_amp, jitter_amp),
		randf_range(-jitter_amp, jitter_amp)
	)


func _update_blink(delta: float) -> void:
	if _hidden_timer >= 0.0:
		_hidden_timer -= delta
		if _hidden_timer <= 0.0:
			_hidden_timer = -1.0
			_next_blink_at = randf_range(blink_min_interval, blink_max_interval)
			var appear := source_sprite.create_tween()
			appear.tween_property(
				source_sprite, "modulate:a", _source_base_alpha, blink_fade_time
			)
		return

	_blink_timer += delta
	if _blink_timer >= _next_blink_at:
		_blink_timer = 0.0
		_hidden_timer = blink_duration
		var disappear := source_sprite.create_tween()
		disappear.tween_property(source_sprite, "modulate:a", 0.0, blink_fade_time)


func _spawn_phantoms(delta: float) -> void:
	_spawn_timer += delta
	if _spawn_timer < spawn_interval:
		return
	_spawn_timer = 0.0

	_spawn_phantom()


func _spawn_phantom() -> void:
	var phantom := AnimatedSprite2D.new()
	phantom.sprite_frames = JEVIL_FRAMES
	phantom.animation = source_sprite.animation
	phantom.speed_scale = phantom_speed_scale
	phantom.centered = source_sprite.centered
	phantom.flip_h = source_sprite.flip_h
	phantom.modulate = Color(1, 1, 1, phantom_alpha)
	phantom.play(phantom.animation)
	var angle := randf() * TAU
	var dist := min_radius + (radius - min_radius) * sqrt(randf())
	phantom.position = to_local(source_sprite.global_position + Vector2(cos(angle), sin(angle)) * dist)

	var self_ref: WeakRef = weakref(self)
	var phantom_ref: WeakRef = weakref(phantom)
	var tween := phantom.create_tween()
	tween.set_parallel(true)
	tween.tween_property(phantom, "modulate:a", 0.0, phantom_lifetime)
	tween.tween_property(phantom, "position", phantom.position + _dir * drift_px_s, phantom_lifetime)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		var owner_node = self_ref.get_ref()
		if owner_node and is_instance_valid(owner_node):
			owner_node._phantoms.erase(phantom)
		var p = phantom_ref.get_ref()
		if p and is_instance_valid(p):
			p.queue_free()
	)

	add_child(phantom)
	_phantoms.append(phantom)

	while _phantoms.size() > max_phantoms:
		var old = _phantoms.pop_front()
		if old != null and is_instance_valid(old):
			old.queue_free()


func _random_position() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(
		randf_range(60.0, vp.x - 60.0),
		randf_range(60.0, vp.y - 60.0)
	)
