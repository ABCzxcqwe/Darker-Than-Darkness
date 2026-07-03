extends Node2D

@export var enabled: bool = true
@export var spawn_interval: float = 0.05
@export var ghost_lifetime: float = 0.40
@export var initial_alpha: float = 0.5
@export var max_ghosts: int = 9

var target_sprite: AnimatedSprite2D
var _timer: float = 0.0
var _fallback_texture: Texture2D
var _ghosts: Array = []
var _ghost_container: Node

func _ready() -> void:
	target_sprite = get_node("../AnimatedSprite2D") as AnimatedSprite2D
	if not target_sprite:
		return
	var frames := target_sprite.sprite_frames
	if frames and frames.has_animation("travel"):
		target_sprite.play("travel")
		_fallback_texture = frames.get_frame_texture("travel", 0)

func _process(delta: float) -> void:
	if not enabled or not target_sprite or not target_sprite.is_inside_tree():
		return

	_timer += delta
	if _timer < spawn_interval:
		return
	_timer = 0.0

	_spawn_ghost()

func _spawn_ghost() -> void:
	var frames: SpriteFrames = target_sprite.sprite_frames
	if not frames:
		return

	var tex: Texture2D = frames.get_frame_texture(target_sprite.animation, target_sprite.frame)
	if not tex:
		tex = _fallback_texture
	if not tex:
		return

	var ghost: Sprite2D = Sprite2D.new()
	ghost.centered = true
	ghost.texture = tex
	ghost.flip_h = target_sprite.flip_h
	ghost.modulate = Color(1, 1, 1, initial_alpha)
	ghost.z_as_relative = false
	ghost.z_index = 2

	# IMPORTANTE: el fantasma NO se añade como hijo de GhostTrail2D (ni del
	# hitbox). Si lo hiciéramos, "global_position" solo fijaría la posición
	# UNA vez; internamente se guarda como posición LOCAL relativa al padre,
	# así que en los frames siguientes el fantasma se movería junto con el
	# proyectil en vez de quedarse atrás marcando el recorrido. Por eso la
	# estela solo se notaba en el impacto (ahí el padre ya no se mueve).
	#
	# Solución: reparentar a un contenedor fijo en la escena para que el
	# fantasma se quede anclado en el punto donde fue creado.
	var container: Node = _get_ghost_container()
	container.add_child(ghost)
	ghost.global_position = target_sprite.global_position
	ghost.global_rotation = target_sprite.global_rotation
	ghost.global_scale = target_sprite.global_scale

	_ghosts.append(ghost)
	while _ghosts.size() > max_ghosts:
		# pop_front() puede devolver una referencia a un fantasma que ya se
		# liberó solo (por su propio tween). Se usa "var old" sin tipar y
		# se valida con is_instance_valid ANTES de comparar/usar, para no
		# disparar "Trying to assign invalid previously freed instance."
		var old = _ghosts.pop_front()
		if old != null and is_instance_valid(old):
			old.queue_free()

	# weakref hacia self: permite comprobar de forma seguridad si
	# GhostTrail2D sigue vivo cuando el tween termine, sin arriesgar un
	# crash si ya fue liberado (el hitbox expiró antes de que el fantasma
	# terminara de desvanecerse).
	var self_ref: WeakRef = weakref(self)
	var tween = ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, ghost_lifetime)
	tween.tween_callback(func() -> void:
		var owner_node = self_ref.get_ref()
		if owner_node and is_instance_valid(owner_node):
			owner_node._ghosts.erase(ghost)
		if is_instance_valid(ghost):
			ghost.queue_free()
	)

# ── Contenedor fijo para los fantasmas ─────────────────────────────────
# Se busca (o se crea) un nodo "GhostTrailContainer" bajo la escena actual,
# para que los fantasmas no queden atados al transform del proyectil.
func _get_ghost_container() -> Node:
	if _ghost_container and is_instance_valid(_ghost_container):
		return _ghost_container

	var root: Node = get_tree().current_scene
	if not root:
		root = get_tree().root

	var existing: Node = root.get_node_or_null("GhostTrailContainer")
	if existing:
		_ghost_container = existing
		return _ghost_container

	var new_container := Node2D.new()
	new_container.name = "GhostTrailContainer"
	root.add_child(new_container)
	_ghost_container = new_container
	return _ghost_container
