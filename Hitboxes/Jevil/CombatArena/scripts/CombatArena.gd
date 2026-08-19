# CombatArena.gd
# Área de combate compartida por las habilidades de Jevil (el "mismo elemento").
# Posee el centro, el radio y los helpers de targeting (survivors vivos dentro
# del área / survivor más cercano). Se replica en red por MultiplayerSynchronizer.
extends Node2D

## Radio del área de combate. Las habilidades usan ESTE radio en vez de
## duplicar su propio const (antes const AOE_RADIUS: float = 600.0 por fase).
var radius: float = 600.0

var _closing: bool = false


func _ready() -> void:
	_play_enter()


func configure(center: Vector2, p_radius: float = 600.0) -> void:
	global_position = center
	radius = p_radius


func _play_enter() -> void:
	modulate.a = 0.0
	scale = Vector2(0.92, 0.92)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.3)
	t.tween_property(self, "scale", Vector2.ONE, 0.3)


## Survivors vivos DENTRO del área de combate.
func survivors_in_arena() -> Array:
	var result: Array = []
	var tree := get_tree()
	if not tree:
		return result
	for s in tree.get_nodes_in_group("survivor"):
		if not is_instance_valid(s):
			continue
		if s.get("health_state") != "alive":
			continue
		if s.global_position.distance_to(global_position) <= radius:
			result.append(s)
	return result


## Survivor vivo más cercano al punto dado (dentro del área de combate).
func nearest_survivor(from: Vector2) -> Node2D:
	var candidates := survivors_in_arena()
	if candidates.is_empty():
		return null
	var best: Node2D = null
	var best_dist: float = INF
	for s in candidates:
		var d: float = s.global_position.distance_to(from)
		if d < best_dist:
			best_dist = d
			best = s
	return best


@rpc("authority", "call_local", "reliable")
func _rpc_disappear() -> void:
	if _closing:
		return
	_closing = true
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.tween_property(self, "scale", Vector2(0.92, 0.92), 0.3)
	t.chain().tween_callback(queue_free)