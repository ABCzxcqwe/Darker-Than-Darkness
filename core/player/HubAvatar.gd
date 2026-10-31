# res://core/player/HubAvatar.gd
# Avatar liviano del hub. No usa Player.gd ni servicios de combate.
# Por ahora usa el idle existente del Vessel y se mueve en top-down.
# El movimiento se replica por RPC a través de Session (posición + flip).
extends CharacterBody2D

signal interactable_changed(prompt: String)
signal interactable_cleared

const SPEED := 240.0
const FRAME_TIME := 0.12
const FRAME_COUNT := 4
const SEND_INTERVAL := 0.1
const INTERP_SPEED := 14.0
const SNAP_DISTANCE := 600.0

@onready var sprite: Sprite2D = $Sprite
@onready var camera: Camera2D = $Camera2D
@onready var name_tag: Label = $NameTag
@onready var interaction_area: Area2D = $InteractionArea

var _frame_accum := 0.0
var _frame := 0
var _send_accum := 0.0
var _can_move := true
var _controls_enabled := true
var _nearby: Array[Area2D] = []
var _current: Node = null
var _net_target_position := Vector2.ZERO
var _has_net_target := false


func _ready() -> void:
	# En el spike local no hay red; en red, solo el dueño mueve su avatar.
	var networked := multiplayer.get_peers().size() > 0 or multiplayer.get_unique_id() > 1
	_can_move = not networked or is_multiplayer_authority()
	if camera:
		camera.enabled = _can_move
		if _can_move:
			camera.make_current()

	_net_target_position = global_position
	_has_net_target = not is_multiplayer_authority()

	refresh_name()

	if interaction_area:
		interaction_area.area_entered.connect(_on_interaction_area_entered)
		interaction_area.area_exited.connect(_on_interaction_area_exited)

	set_controls_enabled(true)


func refresh_name() -> void:
	if name_tag == null:
		return
	var pid := get_multiplayer_authority()
	var info: Dictionary = LobbyManager.players.get(pid, {})
	var display := str(info.get("name", "")).strip_edges()
	if display == "":
		display = "Jugador %d" % pid
	name_tag.text = display


func set_controls_enabled(enabled: bool) -> void:
	_controls_enabled = enabled
	velocity = Vector2.ZERO
	set_physics_process(enabled and _can_move)
	set_process_unhandled_input(enabled and _can_move)
	if interaction_area:
		# Los avatares remotos no necesitan detectar interactuables.
		# El avatar local sigue detectando aunque su input esté bloqueado por un panel.
		interaction_area.monitoring = _can_move
	if enabled and _can_move:
		# Al cerrar un panel, recalcular el prompt por si seguimos junto al objeto.
		refresh_interaction()


func refresh_interaction() -> void:
	_current = null
	_refresh_nearest()


## Posición autoritativa recibida de otro peer (vía Session).
func apply_remote_state(pos: Vector2, flip: bool) -> void:
	if is_multiplayer_authority():
		return
	if not pos.is_finite():
		return
	if global_position.distance_to(pos) > SNAP_DISTANCE:
		global_position = pos
	_net_target_position = pos
	_has_net_target = true
	if sprite:
		sprite.flip_h = flip


func _process(delta: float) -> void:
	_frame_accum += delta
	if _frame_accum >= FRAME_TIME:
		_frame_accum = 0.0
		_frame = (_frame + 1) % FRAME_COUNT
		sprite.frame = _frame

	if not is_multiplayer_authority() and _has_net_target:
		global_position = global_position.lerp(
			_net_target_position,
			clampf(delta * INTERP_SPEED, 0.0, 1.0)
		)


func _physics_process(delta: float) -> void:
	if MenuUtils.is_any_menu_open(get_tree(), self):
		velocity = Vector2.ZERO
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir.length() > 0.01:
		velocity = dir.normalized() * SPEED
		if absf(dir.x) > 0.01:
			sprite.flip_h = dir.x < 0.0
	else:
		velocity = Vector2.ZERO
	move_and_slide()

	# Solo tiene sentido enviar si hay otros peers conectados.
	if multiplayer.get_peers().is_empty():
		return
	_send_accum += delta
	if _send_accum < SEND_INTERVAL:
		return
	_send_accum = 0.0
	var session := get_tree().get_first_node_in_group("hub_session")
	if session and session.has_method("submit_hub_state"):
		session.submit_hub_state(global_position, sprite.flip_h)


func _unhandled_input(event: InputEvent) -> void:
	if not _controls_enabled or not _can_move:
		return
	if MenuUtils.is_any_menu_open(get_tree(), self):
		return
	if event.is_action_pressed("world_interact"):
		if _current == null or not is_instance_valid(_current):
			return
		if not _current.has_method("interact"):
			return
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()
		_current.interact(self)


func _on_interaction_area_entered(area: Area2D) -> void:
	if area == null or not area.has_method("interact"):
		return
	if not _nearby.has(area):
		_nearby.append(area)
	_refresh_nearest()


func _on_interaction_area_exited(area: Area2D) -> void:
	_nearby.erase(area)
	_refresh_nearest()


func _refresh_nearest() -> void:
	var best: Node = null
	var best_dist := INF
	for area in _nearby:
		if not is_instance_valid(area):
			continue
		var dist := global_position.distance_to(area.global_position)
		if dist < best_dist:
			best_dist = dist
			best = area

	if best == _current:
		return
	_current = best

	if _current != null and _current.has_method("get_prompt"):
		interactable_changed.emit(String(_current.get_prompt()))
	else:
		interactable_cleared.emit()
