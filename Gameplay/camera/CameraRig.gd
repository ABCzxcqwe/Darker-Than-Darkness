class_name CameraRig
extends Node2D
## Rig único de cámara por escena (World / Session).
##
## Nodos esperados (ver CameraRig.tscn):
##   Camera2D
##   └── PhantomCameraHost
##   FollowPCam (PhantomCamera2D)
##   NoiseEmitter (PhantomCameraNoiseEmitter2D)
##
## La cámara es 100% visual: no participa del rollback ni del estado de netfox.
## El PCam sigue la posición predicha/interpolada del jugador local.

const GROUP := "camera_rig"
const DEFAULT_ZOOM_BASE := 0.7
const DEFAULT_ZOOM_SPRINT := 0.45
const DEFAULT_ZOOM_SPEED := 3.0
const DEFAULT_SMOOTH_SPEED := 5.0
const DEFAULT_PEEK_AMOUNT := 0.3
const DEFAULT_PEEK_LIMIT := 120.0
const BLIND_ZOOM_MULTIPLIER := 1.4
const DEFAULT_SPECTATE_ZOOM := 0.7
const SHAKE_LAYER := 1

@onready var camera: Camera2D = $Camera2D
@onready var pcam: PhantomCamera2D = $FollowPCam
@onready var noise_emitter: PhantomCameraNoiseEmitter2D = $NoiseEmitter

## Perfil de cámara del personaje actual.
var zoom_base := DEFAULT_ZOOM_BASE
var zoom_sprint := DEFAULT_ZOOM_SPRINT
var zoom_speed := DEFAULT_ZOOM_SPEED
var smooth_speed := DEFAULT_SMOOTH_SPEED
var peek_amount := DEFAULT_PEEK_AMOUNT
var peek_limit := DEFAULT_PEEK_LIMIT
var spectate_zoom := DEFAULT_SPECTATE_ZOOM
var follow_base_offset := Vector2.ZERO

var mode := "disabled"
var _target: Node2D = null
var _noise: PhantomCameraNoise2D = null
var _active := false


func _ready() -> void:
	add_to_group(GROUP)
	_noise = PhantomCameraNoise2D.new()
	_noise.amplitude = 10.0
	_noise.frequency = 0.5
	_noise.positional_noise = true
	_noise.rotational_noise = false

	pcam.follow_damping = true
	pcam.follow_damping_value = Vector2.ONE * _damping_from_smooth(DEFAULT_SMOOTH_SPEED)
	pcam.noise_emitter_layer = SHAKE_LAYER
	pcam.zoom = Vector2.ONE * DEFAULT_ZOOM_BASE
	pcam.tween_on_load = false

	noise_emitter.noise = _noise
	noise_emitter.noise_emitter_layer = SHAKE_LAYER
	noise_emitter.continuous = false
	noise_emitter.growth_time = 0.0

	camera.enabled = false


func _process(delta: float) -> void:
	if not _active or mode == "disabled" or _target == null or not is_instance_valid(_target):
		return
	PlayerCameraController.update(self, _target, delta)


## Rig activo de la escena. Si hay más de uno, gana el primero del grupo.
static func get_active() -> CameraRig:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node in tree.get_nodes_in_group(GROUP):
		if node is CameraRig and node.is_active_rig():
			return node
	return null


func is_active_rig() -> bool:
	return _active


## Busca el rig de una escena concreta (World/Session). Si no lo encuentra,
## cae al rig activo global. Evita que hub y World se pisen al activar.
static func find_for(scene_root: Node) -> CameraRig:
	if scene_root != null:
		var rig := scene_root.get_node_or_null("CameraRig")
		if rig is CameraRig:
			return rig
	return get_active()


## Desactiva este rig sin tocar el resto. Usado cuando hub y World coexisten.
func deactivate_rig() -> void:
	_active = false
	if camera:
		camera.enabled = false


func get_mode() -> String:
	return mode


func get_target() -> Node2D:
	return _target


func set_follow_target(target: Node2D, snap: bool = false) -> void:
	_target = target
	if pcam:
		pcam.follow_target = target
	PlayerCameraController.apply_character(self, target)
	if snap:
		snap_to_target()


func set_spectate_target(target: Node2D, snap: bool = true) -> void:
	_target = target
	if mode == "disabled":
		set_view_mode("spectate")
	if pcam:
		pcam.follow_target = target
		pcam.follow_offset = follow_base_offset
		pcam.zoom = Vector2.ONE * spectate_zoom
	if snap:
		snap_to_target()


func set_view_mode(new_mode: String) -> void:
	mode = new_mode
	if new_mode == "disabled":
		deactivate_rig()
		return

	# Hub y World pueden coexistir; solo un rig debe controlar la cámara.
	var tree := get_tree()
	if tree:
		for node in tree.get_nodes_in_group(GROUP):
			if node != self and node is CameraRig:
				(node as CameraRig).deactivate_rig()
	_active = true
	camera.enabled = true
	camera.make_current()


## Compatibilidad con el flujo anterior de WorldView/Session.
func set_local_player_camera(enabled: bool) -> void:
	set_view_mode("play" if enabled else "disabled")


func set_zoom_profile(base_zoom: float, sprint_zoom: float, p_zoom_speed: float, p_smooth_speed: float) -> void:
	zoom_base = maxf(0.01, base_zoom)
	zoom_sprint = maxf(0.01, sprint_zoom)
	zoom_speed = maxf(0.01, p_zoom_speed)
	smooth_speed = maxf(0.01, p_smooth_speed)
	if pcam:
		pcam.follow_damping_value = Vector2.ONE * _damping_from_smooth(smooth_speed)


func set_peek_profile(amount: float, limit: float) -> void:
	peek_amount = maxf(0.0, amount)
	peek_limit = maxf(0.0, limit)


func set_follow_offset(offset: Vector2) -> void:
	if pcam:
		pcam.follow_offset = follow_base_offset + offset


func set_zoom(value: float, delta: float) -> void:
	if pcam == null:
		return
	var target := Vector2.ONE * maxf(0.01, value)
	var weight := clampf(zoom_speed * delta, 0.0, 1.0)
	pcam.zoom = pcam.zoom.lerp(target, weight)


func set_map_bounds(rect: Rect2) -> void:
	if pcam == null:
		return
	pcam.limit_left = int(rect.position.x)
	pcam.limit_top = int(rect.position.y)
	pcam.limit_right = int(rect.position.x + rect.size.x)
	pcam.limit_bottom = int(rect.position.y + rect.size.y)


func snap_to_target() -> void:
	if pcam and pcam.has_method("teleport_position"):
		pcam.teleport_position()


## Shake local. No se replica: ClientRelay ya decide qué clientes lo reciben.
func shake(intensity: float = 5.0, duration: float = 0.2) -> void:
	if _noise == null or noise_emitter == null:
		return
	if intensity <= 0.0 or duration <= 0.0:
		return
	_noise.amplitude = maxf(0.1, intensity)
	_noise.randomize_noise_seed = true
	noise_emitter.duration = maxf(0.05, duration)
	noise_emitter.decay_time = maxf(0.0, duration * 0.5)
	noise_emitter.emit()


func _damping_from_smooth(value: float) -> float:
	return clampf(1.0 / maxf(value, 0.1), 0.05, 0.5)
