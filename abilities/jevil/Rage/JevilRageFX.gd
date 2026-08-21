# res://abilities/jevil/Rage/JevilRageFX.gd
# ============================================================
# VFX del Rage de Jevil — adaptación del efecto "fase 2" de
# fx_tests/JevilPhantom/JevilPhantom.gd al jugador real:
#   - Jitter sobre animated_sprite.offset (restaurado al salir;
#     position.y pertenece al bob idle de Jevil en Player.gd)
#   - Fantasmas: clones AnimatedSprite2D que copian la animación
#     actual del jugador y se desvanecen a su alrededor
#
# El blink NO vive aquí: el controlador de modulate de Player.gd
# sobrescribe modulate cada frame, así que se integra ahí vía el
# flag active_effects["rage_blink"] (_sync_effect desde Rage.gd).
#
# Nodo puramente visual: solo existe en clientes, no toca lógica.
# ============================================================
extends Node2D

const JITTER_AMP: float = 4.0
const SPAWN_INTERVAL: float = 0.08
const MAX_PHANTOMS: int = 16
const PHANTOM_LIFETIME: float = 0.8
const PHANTOM_ALPHA: float = 0.45
const PHANTOM_SPEED_SCALE: float = 0.6
const MIN_RADIUS: float = 60.0
const MAX_RADIUS: float = 150.0
const DRIFT_PX_S: float = 20.0

var _player: Node2D = null
var _sprite: AnimatedSprite2D = null
var _base_offset: Vector2 = Vector2.ZERO
var _spawn_timer: float = 0.0
var _phantoms: Array = []


func _ready() -> void:
	_player = get_parent() as Node2D
	if _player == null:
		queue_free()
		return
	_sprite = _player.get_node_or_null("AnimatedSprite2D")
	if _sprite == null:
		queue_free()
		return
	_base_offset = _sprite.offset


func _process(delta: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_sprite):
		return
	_apply_jitter()
	_spawn_phantoms(delta)


func _apply_jitter() -> void:
	_sprite.offset = _base_offset + Vector2(
		randf_range(-JITTER_AMP, JITTER_AMP),
		randf_range(-JITTER_AMP, JITTER_AMP)
	)


func _spawn_phantoms(delta: float) -> void:
	_spawn_timer += delta
	if _spawn_timer < SPAWN_INTERVAL:
		return
	_spawn_timer = 0.0
	_spawn_phantom()


func _spawn_phantom() -> void:
	if not is_instance_valid(_sprite) or _sprite.sprite_frames == null:
		return
	var phantom := AnimatedSprite2D.new()
	phantom.sprite_frames = _sprite.sprite_frames
	if _sprite.sprite_frames.has_animation(_sprite.animation):
		phantom.animation = _sprite.animation
		phantom.frame = _sprite.frame
		phantom.flip_h = _sprite.flip_h
		phantom.speed_scale = PHANTOM_SPEED_SCALE
		phantom.play(phantom.animation)
	else:
		return
	phantom.modulate = Color(1, 1, 1, PHANTOM_ALPHA)
	phantom.z_index = 1
	var pos := _random_ring_position()
	phantom.position = pos
	add_child(phantom)
	_phantoms.append(phantom)
	var phantom_ref: WeakRef = weakref(phantom)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(phantom, "modulate:a", 0.0, PHANTOM_LIFETIME)
	tween.tween_property(phantom, "position", pos + pos.normalized() * DRIFT_PX_S, PHANTOM_LIFETIME)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		var p = phantom_ref.get_ref()
		if p and is_instance_valid(p):
			p.queue_free()
	)
	while _phantoms.size() > MAX_PHANTOMS:
		var old = _phantoms.pop_front()
		if old != null and is_instance_valid(old):
			old.queue_free()


func _random_ring_position() -> Vector2:
	var angle := randf() * TAU
	var dist := MIN_RADIUS + (MAX_RADIUS - MIN_RADIUS) * sqrt(randf())
	return Vector2(cos(angle), sin(angle)) * dist


func _exit_tree() -> void:
	if is_instance_valid(_sprite):
		_sprite.offset = _base_offset
