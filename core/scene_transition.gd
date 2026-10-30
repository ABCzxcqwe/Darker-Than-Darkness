# res://core/scene_transition.gd
# Fade largo para entrar/salir de partida. Para los menús usamos el fondo
# persistente (MenuBackdrop), no este fade.
extends Node

const LAYER := 300

var _layer: CanvasLayer
var _overlay: ColorRect
var _busy := false
var _attached := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer = CanvasLayer.new()
	_layer.name = "SceneTransitionLayer"
	_layer.layer = LAYER

	_overlay = ColorRect.new()
	_overlay.name = "SceneTransitionFade"
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_overlay)
	_attach_layer.call_deferred()


func _attach_layer() -> void:
	if not is_instance_valid(_layer):
		return
	if _layer.get_parent() == null:
		get_tree().root.add_child(_layer)
	_attached = true


func _input(event: InputEvent) -> void:
	if _busy:
		get_viewport().set_input_as_handled()


## Cambia de escena con fade-out, hold negro y fade-in.
## En headless (dedicated/test) cambia de inmediato para no frenar la simulación.
func change_scene(path: String, fade_out: float = 0.5, hold_black: float = 0.25, fade_in: float = 0.7) -> void:
	if _busy:
		return

	if DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file(path)
		return

	if not _attached:
		await get_tree().process_frame
		_attach_layer()

	_busy = true
	if _overlay:
		_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	await _fade_to(1.0, fade_out)

	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("[SceneTransition] No se pudo cargar '%s' (error %d)" % [path, err])
		await _fade_to(0.0, fade_in)
		_finish()
		return

	# Dejar que la escena nueva haga _ready, aplique tema y dibuje al menos
	# un frame antes de descubrirla.
	await get_tree().process_frame
	await get_tree().process_frame
	if hold_black > 0.0:
		await get_tree().create_timer(hold_black).timeout

	await _fade_to(0.0, fade_in)
	_finish()


## Fade a negro sin cambiar de escena. Útil para transiciones internas
## (CharacterSelect -> World) que no usan change_scene_to_file.
func fade_to_black(duration: float = 0.45) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not _attached:
		await get_tree().process_frame
		_attach_layer()
	if _busy:
		return
	_busy = true
	if _overlay:
		_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0, duration)


## Revela la escena actual después de fade_to_black().
func fade_from_black(duration: float = 0.6) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not _attached:
		await get_tree().process_frame
		_attach_layer()
	await _fade_to(0.0, duration)
	_finish()


func _fade_to(target: float, duration: float) -> void:
	if _overlay == null:
		return
	if duration <= 0.0:
		_overlay.color.a = target
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_overlay, "color:a", target, duration)
	await tw.finished


func _finish() -> void:
	if _overlay:
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
