# res://Network/session/world_view.gd
class_name WorldView
extends Node
## Modo de vista local del World: play / spectate / hub.
## No carga mapas ni crea jugadores; solo ajusta HUD, cámara y espectador.

const TAG := "WorldView"

var _world: Node
var _local_view_mode := "play"
var _local_view_ready := false
var _applying := false
var _canvas_modulates: Array[CanvasModulate] = []


func setup(world: Node) -> void:
	_world = world


func set_initial_mode(mode: String) -> void:
	_local_view_mode = mode if mode in ["play", "spectate", "hub"] else "play"


func get_mode() -> String:
	return _local_view_mode


func mark_ready() -> void:
	_local_view_ready = true


func set_local_view_mode(mode: String) -> void:
	if mode not in ["play", "spectate", "hub"]:
		return
	_local_view_mode = mode
	if _world:
		_world.set_meta("local_view_mode", mode)
	if _local_view_ready and not _applying:
		apply()


func collect_canvas_modulates() -> void:
	_canvas_modulates.clear()
	for node in _world.find_children("*", "CanvasModulate", true, false):
		if node is CanvasModulate:
			_canvas_modulates.append(node)


func apply() -> void:
	if not _local_view_ready:
		return
	_applying = true
	var scoreboard: Node = _world.hud.get_scoreboard()

	match _local_view_mode:
		"play":
			_set_canvas_visible(true)
			deactivate_spectator()
			set_local_player_camera(true)
			_world.hud.set_hud_mode("play")
		"spectate":
			_set_canvas_visible(false)
			if scoreboard and is_instance_valid(scoreboard):
				scoreboard.visible = false
			set_local_player_camera(false)
			_world.hud.set_hud_mode("spectate")
			activate_spectator()
		"hub":
			_set_canvas_visible(false)
			if scoreboard and is_instance_valid(scoreboard):
				scoreboard.visible = false
			deactivate_spectator()
			set_local_player_camera(false)
			for panel in _world.get_tree().get_nodes_in_group("chat_panel"):
				if panel.has_method("close_input"):
					panel.close_input()
			_world.hud.set_hud_mode("hub")

	_applying = false


func activate_spectator() -> void:
	var ctrl: Node = _world.get_spectator_controller()
	if ctrl and ctrl.has_method("activate"):
		ctrl.activate()


func deactivate_spectator() -> void:
	var ctrl: Node = _world.get_spectator_controller()
	if ctrl and ctrl.has_method("deactivate"):
		ctrl.deactivate()


func set_local_player_camera(enabled: bool) -> void:
	var rig := CameraRig.find_for(_world)
	if rig == null:
		return
	if not enabled:
		rig.set_view_mode("disabled")
		return
	var player := PlayerLifecycleManager.get_player(_world.multiplayer.get_unique_id())
	if player and is_instance_valid(player):
		rig.set_follow_target(player as Node2D, true)
	rig.set_view_mode("play")


func _set_canvas_visible(visible_now: bool) -> void:
	for cm in _canvas_modulates:
		if is_instance_valid(cm):
			cm.visible = visible_now
