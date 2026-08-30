extends Node

## Capa global de brillo - colocada justo antes del VHS (layer 127 vs VHS 128)
## Modula luminosidad sin afectar lógica de juego, persiste entre escenas.

var _canvas_layer: CanvasLayer
var _overlay: ColorRect

func _ready() -> void:
	SettingsManager.setting_changed.connect(_on_setting_changed)
	_create_overlay.call_deferred()

func _create_overlay() -> void:
	if is_instance_valid(_canvas_layer):
		return
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 127
	_canvas_layer.name = "GlobalBrightnessLayer"

	_overlay = ColorRect.new()
	_overlay.name = "BrightnessOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# color base: blanco con alpha 0, modulamos via modulate/color según brightness
	_overlay.color = Color(0, 0, 0, 0)

	_canvas_layer.add_child(_overlay)
	get_tree().root.add_child(_canvas_layer)
	_apply_brightness(SettingsManager.brightness)
	print("[GlobalBrightness] overlay listo, brightness=", SettingsManager.brightness)

func _apply_brightness(v: float) -> void:
	if not is_instance_valid(_overlay):
		return
	# brightness 1.0 = neutro (transparente)
	# <1.0 = oscurecer con overlay negro alpha, >1.0 = aclarar con overlay blanco alpha
	# clamp 0.5-1.5 ya viene de SettingsManager
	v = clampf(v, 0.5, 1.5)
	if v < 1.0:
		# negro con alpha proporcional: 0.5 -> alpha 0.5, 1.0 -> 0
		var alpha := (1.0 - v) # 0.5 de oscurecimiento max
		_overlay.color = Color(0, 0, 0, alpha)
	else:
		# blanco con alpha proporcional: 1.0 -> 0, 1.5 -> 0.25 (aclarado sutil, no sobreexpone en gl_compatibility)
		var alpha2 := (v - 1.0) * 0.5
		_overlay.color = Color(1, 1, 1, alpha2)

func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "brightness":
		if not is_instance_valid(_canvas_layer):
			_create_overlay.call_deferred()
		else:
			_apply_brightness(float(value))
