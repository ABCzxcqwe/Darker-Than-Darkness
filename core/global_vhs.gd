extends Node

var _overlay: ColorRect
var _canvas_layer: CanvasLayer

func _ready() -> void:
	SettingsManager.setting_changed.connect(_on_setting_changed)
	_create_overlay.call_deferred()

func _create_overlay() -> void:
	if is_instance_valid(_canvas_layer):
		return
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 128
	_canvas_layer.name = "GlobalVHSLayer"

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.02
	var noise_image: Image = noise.get_image(256, 256, true, false, false)
	var noise_texture := ImageTexture.create_from_image(noise_image)

	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = preload("res://ui/GameUI/Scenes/GameHUD.gdshader")
	var vp_size := Vector2(1440, 1080)
	if get_viewport():
		vp_size = get_viewport().get_visible_rect().size
		if vp_size.x < 100 or vp_size.y < 100:
			vp_size = Vector2(1440, 1080)
	##shader_mat.set_shader_parameter("vhs_resolution", vp_size)
	shader_mat.set_shader_parameter("vhs_resolution", Vector2(640, 480))
	shader_mat.set_shader_parameter("samples", 3)
	shader_mat.set_shader_parameter("crease_noise", 0.3)
	shader_mat.set_shader_parameter("crease_opacity", 0.5)
	shader_mat.set_shader_parameter("filter_intensity", 0.1)
	shader_mat.set_shader_parameter("curvature_amount", 0.3)
	shader_mat.set_shader_parameter("border_feather", 0.02)
	shader_mat.set_shader_parameter("tape_crease_smear", 0.5)
	shader_mat.set_shader_parameter("tape_crease_intensity", 0.02)
	shader_mat.set_shader_parameter("tape_crease_jitter", 0.1)
	shader_mat.set_shader_parameter("tape_crease_speed", 0.5)
	shader_mat.set_shader_parameter("tape_crease_discoloration", 1.0)
	shader_mat.set_shader_parameter("bottom_border_thickness", 6.0)
	shader_mat.set_shader_parameter("bottom_border_jitter", 6.0)
	shader_mat.set_shader_parameter("noise_intensity", 0.05)
	shader_mat.set_shader_parameter("noise_texture", noise_texture)

	_overlay = ColorRect.new()
	_overlay.name = "VHSOverlay"
	_overlay.material = shader_mat
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_canvas_layer.add_child(_overlay)
	get_tree().root.add_child(_canvas_layer)
	_canvas_layer.visible = SettingsManager.vhs_enabled
	print("[GlobalVHS] overlay listo, visible=", _canvas_layer.visible)

func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "vhs_enabled":
		if not is_instance_valid(_canvas_layer):
			if bool(value):
				_create_overlay.call_deferred()
			return
		_canvas_layer.visible = bool(value)
