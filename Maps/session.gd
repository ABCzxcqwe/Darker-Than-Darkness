# res://Network/session/session.gd
extends Node2D
## Escena persistente de sala/hub y partida.
##
## El HubArea y sus avatares siguen vivos; el World de la partida cuelga de
## MatchArea y se muestra u oculta según la vista local. La UI vive en HubUI,
## los avatares en HubAvatars y el RPC de estado en HubState.

const TAG := "Session"

@onready var hub_spawn: Marker2D = $HubArea/HubSpawn
@onready var match_area: Node2D = $MatchArea
@onready var map_container: Node2D = $MatchArea/MapContainer

var avatars: HubAvatars
var ui: HubUI
var hub_state: HubState

var _active := true
var _in_match := false
var _match_running := false
var _match_ended := false
var _at_hub := true
var _match_instance: Node = null


func _ready() -> void:
	add_to_group(NetScenes.HUB_SESSION_GROUP)
	_setup_hub_audio()

	avatars = HubAvatars.new()
	avatars.name = "HubAvatars"
	add_child(avatars)
	avatars.setup(self)

	ui = HubUI.new()
	ui.name = "HubUI"
	add_child(ui)
	ui.setup(self)

	hub_state = HubState.new()
	hub_state.name = "HubState"
	add_child(hub_state)
	hub_state.setup(self)

	LobbyManager.lobby_updated.connect(_on_lobby_changed)
	LobbyManager.player_joined.connect(_on_player_joined)
	LobbyManager.player_left.connect(_on_player_left)

	avatars.sync()
	if _at_hub:
		_set_local_avatar_hub_visible(true, true)
	ui.update_status()

	var my_id := 1
	if multiplayer and multiplayer.multiplayer_peer:
		my_id = multiplayer.get_unique_id()
	if LobbyManager.current_phase == LobbyManager.GamePhase.ENDED \
			and not LobbyManager.is_match_participant(my_id):
		on_match_ended_for_hub()
	elif LobbyManager.current_phase == LobbyManager.GamePhase.PLAYING \
			and not LobbyManager.is_match_participant(my_id):
		on_match_started_for_hub()
	elif LobbyManager.current_phase == LobbyManager.GamePhase.CHARACTER_SELECT \
			and not LobbyManager.is_match_participant(my_id):
		_in_match = true
		_match_running = false
		_at_hub = true
		ui.update_status()
		ui.configure_game_menu()
		ui.refresh_quick_actions()

	NetLog.info(TAG, "Hub listo con %d jugador(es) en LobbyManager." % LobbyManager.players.size())


func _setup_hub_audio() -> void:
	var ds := get_node_or_null("/root/DedicatedServer")
	if ds and ds.is_dedicated:
		return
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_menu_drone") and am.current_global_state != "menu_drone":
		am.play_menu_drone()


func _exit_tree() -> void:
	if LobbyManager.lobby_updated.is_connected(_on_lobby_changed):
		LobbyManager.lobby_updated.disconnect(_on_lobby_changed)
	if LobbyManager.player_joined.is_connected(_on_player_joined):
		LobbyManager.player_joined.disconnect(_on_player_joined)
	if LobbyManager.player_left.is_connected(_on_player_left):
		LobbyManager.player_left.disconnect(_on_player_left)


# ── Estado / acceso para helpers ──

func is_active() -> bool:
	return _active


func is_in_match() -> bool:
	return _in_match


func is_match_running() -> bool:
	return _match_running


func is_match_ended() -> bool:
	return _match_ended


func is_at_hub() -> bool:
	return _at_hub


func is_networked() -> bool:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.get_peers().size() > 0 or multiplayer.get_unique_id() > 1


func local_peer_id() -> int:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return 1
	var id := multiplayer.get_unique_id()
	if id <= 1 and multiplayer.get_peers().is_empty():
		return 1
	return id


func can_spawn_standalone_dummy() -> bool:
	var ds := get_node_or_null("/root/DedicatedServer")
	if ds and ds.is_dedicated:
		return false
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return true
	return multiplayer.get_peers().is_empty() and multiplayer.get_unique_id() <= 1


func get_local_avatar() -> Node:
	return avatars.get_local_avatar()


func get_hub_spawn_position() -> Vector2:
	return hub_spawn.global_position


func set_local_avatar_controls(enabled: bool) -> void:
	var avatar := avatars.get_local_avatar()
	if avatar and avatar.has_method("set_controls_enabled"):
		avatar.set_controls_enabled(enabled)


func show_prompt(text: String) -> void:
	ui.show_prompt(text)


func hide_prompt() -> void:
	ui.hide_prompt()


func submit_hub_state(pos: Vector2, flip: bool) -> void:
	hub_state.submit(pos, flip)


func on_avatars_synced() -> void:
	ui.on_lobby_changed()


func _on_lobby_changed() -> void:
	avatars.queue_sync()


func _on_player_joined(_peer_id: int, _info: Dictionary) -> void:
	avatars.queue_sync()


func _on_player_left(_peer_id: int) -> void:
	avatars.queue_sync()


# ── Transiciones de vista ──

func get_match_root() -> Node2D:
	return $MatchArea as Node2D


func enter_match_view() -> void:
	_in_match = true
	_match_running = true
	_match_ended = false
	_at_hub = false
	ui.hide_character_select()
	LobbyManager.set_local_presence("match")
	ui.close_hub_overlays()
	_set_hub_visible(false)
	_set_local_avatar_hub_visible(false)
	ui.configure_game_menu()
	ui.refresh_quick_actions()


func enter_spectator_view() -> void:
	if not _in_match:
		_in_match = true
	if not _match_running:
		_match_running = true
	_at_hub = false
	ui.hide_character_select()
	LobbyManager.set_local_presence("spectate")
	ui.close_hub_overlays()
	_set_hub_visible(false)
	_set_local_avatar_hub_visible(false)
	ui.configure_game_menu()
	ui.refresh_quick_actions()


func return_to_hub_from_spectate() -> void:
	_at_hub = true
	_in_match = true
	ui.hide_character_select()
	LobbyManager.set_local_presence("hub")
	_set_hub_visible(true)
	_set_local_avatar_hub_visible(true, true)
	MatchCoordinator.set_local_view_mode("hub")
	ui.update_status()
	ui.configure_game_menu()
	ui.refresh_quick_actions()


func on_match_started_for_hub() -> void:
	_in_match = true
	_match_running = true
	_match_ended = false
	_at_hub = true
	ui.hide_character_select()
	LobbyManager.set_local_presence("hub")
	ui.close_hub_overlays()
	_set_hub_visible(true)
	_set_local_avatar_hub_visible(true)
	ui.update_status()
	ui.configure_game_menu()
	ui.refresh_quick_actions()


func on_match_ended_for_hub() -> void:
	_match_running = false
	_match_ended = true
	_in_match = true
	ui.hide_character_select()
	LobbyManager.set_local_presence("hub")
	if ui.is_board_open():
		ui.close_hub_overlays()
	if not _at_hub:
		_at_hub = true
		_set_hub_visible(true)
		_set_local_avatar_hub_visible(true, true)
		MatchCoordinator.set_local_view_mode("hub")
	_setup_hub_audio()
	ui.update_status()
	ui.configure_game_menu()
	ui.refresh_quick_actions()


func _set_hub_visible(visible_now: bool) -> void:
	$HubArea.visible = visible_now
	$Actors.visible = visible_now
	$UI.visible = visible_now
	$UI.process_mode = Node.PROCESS_MODE_INHERIT if visible_now else Node.PROCESS_MODE_DISABLED


## API pública para helpers (HubAvatars).
func set_local_avatar_hub_visible(visible_now: bool, reset_position: bool = false) -> void:
	_set_local_avatar_hub_visible(visible_now, reset_position)


func _set_local_avatar_hub_visible(visible_now: bool, reset_position: bool = false) -> void:
	var avatar := avatars.get_local_avatar()
	if avatar == null:
		return
	avatar.visible = visible_now
	avatar.set_controls_enabled(visible_now)
	if reset_position and visible_now:
		avatar.global_position = avatars.get_spawn_position(local_peer_id())
	var rig := CameraRig.find_for(self)
	if rig:
		if visible_now:
			rig.set_follow_target(avatar as Node2D, true)
			rig.set_view_mode("hub")
		else:
			rig.set_view_mode("disabled")


## Compatibilidad con el flujo anterior.
func prepare_for_match() -> void:
	if _active:
		enter_match_view()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if ui.character_select_open():
		return

	# Atajo de debug solo para la escena standalone.
	if not is_networked() \
			and event is InputEventKey and event.pressed and event.keycode == KEY_F2 \
			and not event.echo:
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()
		if _in_match:
			_return_to_hub()
		else:
			_enter_match()
		return

	# Durante una partida o selección, la salida explícita vive en el menú.
	if _in_match or LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY:
		return

	var leave: bool = event.is_action_pressed("menu_cancel") \
			or event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_X)
	if leave:
		if ui.is_board_open():
			return
		var vp2 := get_viewport()
		if vp2:
			vp2.set_input_as_handled()
		MatchCoordinator.reset_to_menu()


# ── Debug local del spike (sin red) ──

func _enter_match() -> void:
	if _in_match:
		return
	var local_avatar := avatars.get_local_avatar()
	if local_avatar == null:
		return

	_in_match = true
	_at_hub = false
	_set_hub_visible(false)
	_set_local_avatar_hub_visible(false)
	ui.hide_prompt()
	ui.update_status()

	var packed := load(NetScenes.TEST_MAP) as PackedScene
	if packed == null:
		NetLog.error(TAG, "No se pudo cargar TestMap (%s)." % NetScenes.TEST_MAP)
		return
	_match_instance = packed.instantiate()
	map_container.add_child(_match_instance)
	if not _match_instance.is_node_ready():
		await _match_instance.ready

	var spawn := match_area.global_position
	if _match_instance.has_method("get_random_survivor_spawn"):
		spawn = _match_instance.get_random_survivor_spawn()
	local_avatar.global_position = spawn
	NetLog.debug(TAG, "Debug: partida cargada en %s." % str(spawn))


func _return_to_hub() -> void:
	if not _in_match:
		return
	_in_match = false
	_at_hub = true
	_set_hub_visible(true)
	_set_local_avatar_hub_visible(true, true)

	if is_instance_valid(_match_instance):
		_match_instance.queue_free()
	_match_instance = null

	ui.hide_prompt()
	ui.update_status()
	NetLog.debug(TAG, "Debug: vuelta al hub.")
