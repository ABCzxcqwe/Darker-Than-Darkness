extends Node2D

# Fantasma solo visual para TeleportRage: aparece en old_pos y se reduce en ancho.
# No dispara; el pike lo lanza Jevil real desde new_pos.

var _sprite: AnimatedSprite2D = null
var _shrink_delay: float = 0.5
var _shrink_duration: float = 0.25

func configure(pos: Vector2, _dir: Vector2) -> void:
	global_position = pos

func _ready() -> void:
	var frames: SpriteFrames = preload("res://Characters/Jevil/animations.tres")
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.animation = "jevil_tp"
	_sprite.play("jevil_tp")
	_sprite.scale = Vector2(1.0, 1.0)
	add_child(_sprite)
	_sprite.position = Vector2.ZERO
	_sprite.z_index = 2
	# Programar shrink tras delay (visible 0.5s luego width->0)
	get_tree().create_timer(_shrink_delay).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_do_shrink()
	)
	get_tree().create_timer(_shrink_delay + _shrink_duration + 0.5).timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free()
	)

func _do_shrink() -> void:
	if not is_instance_valid(_sprite):
		return
	var tween := create_tween()
	tween.tween_property(_sprite, "scale:x", 0.0, _shrink_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

# Compat: TeleportRage antiguo llamaba notify_shoot; ahora solo hace shrink
func notify_shoot() -> void:
	if is_instance_valid(_sprite) and _sprite.scale.x > 0.05:
		_do_shrink()
