extends Node2D

const MAX_SIZE: float = 0.5
const FORCE: float = 0.08
const THICKNESS: float = 0.06

var duration: float = 1.0
var _time: float = 0.0


func set_duration(value: float) -> void:
	duration = maxf(value, 0.1)


func _ready() -> void:
	var quad: Polygon2D = $WaveQuad
	quad.material.set_shader_parameter("center", Vector2(0.5, 0.5))
	quad.material.set_shader_parameter("force", FORCE)
	quad.material.set_shader_parameter("thickness", THICKNESS)
	quad.material.set_shader_parameter("size", 0.0)


func _process(delta: float) -> void:
	_time += delta
	var t := clampf(_time / duration, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 3.0)

	var quad: Polygon2D = $WaveQuad
	var mat: ShaderMaterial = quad.material
	mat.set_shader_parameter("size", eased * MAX_SIZE)
	mat.set_shader_parameter("force", FORCE * (1.0 - t))

	var cam := get_viewport().get_camera_2d()
	if cam:
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		if viewport_size.x > 0.0 and viewport_size.y > 0.0:
			var uv: Vector2 = cam.get_canvas_transform() * global_position / viewport_size
			mat.set_shader_parameter("center", uv)

	if _time >= duration:
		queue_free()
