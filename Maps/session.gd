# res://Maps/session.gd
# Escena de sala/hub. Mantiene el HubArea cargado y crea un HubAvatar por peer.
# El mapa de partida se sigue manejando con el flujo existente de MatchCoordinator
# (CharacterSelect -> World); esta escena es el punto de retorno entre partidas.
extends Node2D

const HUB_AVATAR_SCENE := preload("res://core/player/HubAvatar.tscn")
const TEST_MAP_SCENE := preload("res://Maps/Test/TestMap.tscn")

## Offsets fijos por peer para que los avatares no se apilen al entrar.
const SPAWN_OFFSETS: Array[Vector2] = [
	Vector2(0, 0),
	Vector2(-120, 0),
	Vector2(120, 0),
	Vector2(0, -90),
	Vector2(0, 90),
	Vector2(-120, -90),
	Vector2(120, -90),
	Vector2(-120, 90),
	Vector2(120, 90),
	Vector2(0, 170),
]

@onready var actors: Node2D = $Actors
@onready var hub_spawn: Marker2D = $HubArea/HubSpawn
@onready var hub_board = $HubArea/HubBoard
@onready var match_area: Node2D = $MatchArea
@onready var map_container: Node2D = $MatchArea/MapContainer
@onready var status_label: Label = $UI/StatusLabel
@onready var prompt_label: Label = $UI/PromptLabel
@onready var board_panel: Control = $UI/BoardPanel

var _avatars: Dictionary = {}
var _local_avatar: Node = null
var _active := true
var _in_match := false
var _match_instance: Node = null
var _standalone_dummy := false
var _sync_queued := false


func _ready() -> void:
	add_to_group("hub_session")
	_setup_hub_audio()
	LobbyManager.lobby_updated.connect(_on_lobby_updated)
	LobbyManager.player_joined.connect(_on_player_joined)
	LobbyManager.player_left.connect(_on_player_left)
	MatchCoordinator.start_countdown_started.connect(_on_start_countdown_started)
	MatchCoordinator.start_countdown_cancelled.connect(_on_start_countdown_cancelled)

	hub_board.interacted.connect(_on_board_interacted)
	board_panel.start_requested.connect(_on_board_start_requested)
	board_panel.closed.connect(_on_board_closed)
	board_panel.map_selected.connect(_on_map_selected)

	_sync_avatars()
	_update_status()
	print("[Session] Hub listo con %d jugador(es) en LobbyManager." % LobbyManager.players.size())


func _setup_hub_audio() -> void:
	var ds := get_node_or_null("/root/DedicatedServer")
	if ds and ds.is_dedicated:
		return
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_menu_drone") and am.current_global_state != "menu_drone":
		am.play_menu_drone()


func _exit_tree() -> void:
	if LobbyManager.lobby_updated.is_connected(_on_lobby_updated):
		LobbyManager.lobby_updated.disconnect(_on_lobby_updated)
	if LobbyManager.player_joined.is_connected(_on_player_joined):
		LobbyManager.player_joined.disconnect(_on_player_joined)
	if LobbyManager.player_left.is_connected(_on_player_left):
		LobbyManager.player_left.disconnect(_on_player_left)
	if MatchCoordinator.start_countdown_started.is_connected(_on_start_countdown_started):
		MatchCoordinator.start_countdown_started.disconnect(_on_start_countdown_started)
	if MatchCoordinator.start_countdown_cancelled.is_connected(_on_start_countdown_cancelled):
		MatchCoordinator.start_countdown_cancelled.disconnect(_on_start_countdown_cancelled)


# ── Avatares ────────────────────────────────────────────────────────────

func _on_lobby_updated() -> void:
	_queue_sync()


func _on_player_joined(_peer_id: int, _info: Dictionary) -> void:
	_queue_sync()


func _on_player_left(_peer_id: int) -> void:
	_queue_sync()


## No agregar/quitar nodos dentro de multiplayer.poll(): las señales del lobby
## pueden llegar en pleno _physics_process de NetworkManager.
func _queue_sync() -> void:
	if not _active or _sync_queued:
		return
	_sync_queued = true
	call_deferred("_run_sync")


func _run_sync() -> void:
	_sync_queued = false
	if not _active:
		return
	_sync_avatars()
	_update_status()
	if board_panel.is_open():
		board_panel.refresh_map_info()


func _sync_avatars() -> void:
	if not _active:
		return

	var ids: Array = LobbyManager.players.keys()
	ids.sort()

	# En la escena standalone (sin red y sin lobby) creamos un avatar local dummy.
	if ids.is_empty() and _avatars.is_empty() and _can_spawn_standalone_dummy():
		_spawn_avatar(1)
		_standalone_dummy = true
		ids = [1]

	for pid in ids:
		_spawn_avatar(int(pid))

	for pid in _avatars.keys():
		if LobbyManager.players.has(pid):
			continue
		if _standalone_dummy and int(pid) == 1 and LobbyManager.players.is_empty():
			continue
		_remove_avatar(int(pid))
	if not LobbyManager.players.is_empty():
		_standalone_dummy = false

	_local_avatar = _avatars.get(_local_peer_id(), null)
	for pid in _avatars:
		var avatar = _avatars[pid]
		if is_instance_valid(avatar):
			avatar.refresh_name()


func _spawn_avatar(peer_id: int) -> void:
	if _avatars.has(peer_id):
		return
	var avatar := HUB_AVATAR_SCENE.instantiate()
	avatar.name = str(peer_id)
	avatar.set_multiplayer_authority(peer_id)
	actors.add_child(avatar)
	avatar.global_position = _get_spawn_position(peer_id)
	_avatars[peer_id] = avatar

	if peer_id == _local_peer_id():
		_local_avatar = avatar
		_connect_local_avatar(avatar)
	avatar.refresh_name()
	print("[Session] Avatar creado para peer %d (local=%s)" % [
		peer_id, str(peer_id == _local_peer_id())
	])


func _remove_avatar(peer_id: int) -> void:
	if not _avatars.has(peer_id):
		return
	var avatar = _avatars[peer_id]
	_avatars.erase(peer_id)
	if avatar == _local_avatar:
		_local_avatar = null
		if prompt_label:
			prompt_label.visible = false
	if is_instance_valid(avatar):
		avatar.queue_free()


func _is_networked() -> bool:
	return multiplayer.get_peers().size() > 0 or multiplayer.get_unique_id() > 1


func _local_peer_id() -> int:
	var id := multiplayer.get_unique_id()
	if id <= 1 and multiplayer.get_peers().is_empty():
		return 1
	return id


func _can_spawn_standalone_dummy() -> bool:
	var ds := get_node_or_null("/root/DedicatedServer")
	if ds and ds.is_dedicated:
		return false
	return multiplayer.get_peers().is_empty() and multiplayer.get_unique_id() <= 1


func _get_spawn_position(peer_id: int) -> Vector2:
	var idx: int = absi(peer_id) % SPAWN_OFFSETS.size()
	return hub_spawn.global_position + SPAWN_OFFSETS[idx]


func _connect_local_avatar(avatar: Node) -> void:
	if avatar.interactable_changed.is_connected(_on_interactable_changed) == false:
		avatar.interactable_changed.connect(_on_interactable_changed)
	if avatar.interactable_cleared.is_connected(_on_interactable_cleared) == false:
		avatar.interactable_cleared.connect(_on_interactable_cleared)
	avatar.refresh_interaction()


# ── Interacción / tablero ───────────────────────────────────────────────

func _on_interactable_changed(prompt: String) -> void:
	if prompt_label == null or board_panel.is_open():
		return
	prompt_label.text = "[E] " + prompt
	prompt_label.visible = true


func _on_interactable_cleared() -> void:
	if prompt_label:
		prompt_label.visible = false


func _on_board_interacted(player: Node) -> void:
	if not _active or _in_match or player != _local_avatar or board_panel.is_open():
		return
	if prompt_label:
		prompt_label.visible = false
	if _local_avatar:
		_local_avatar.set_controls_enabled(false)
	var can_start: bool = LobbyManager.is_host or LobbyManager.is_room_host()
	board_panel.open_panel(can_start)


func _on_board_closed() -> void:
	if _local_avatar and is_instance_valid(_local_avatar):
		_local_avatar.set_controls_enabled(true)


func _on_map_selected(map_id: String) -> void:
	if not (LobbyManager.is_host or LobbyManager.is_room_host()):
		board_panel.set_status("SOLO EL HOST PUEDE CAMBIAR EL MAPA")
		return
	LobbyManager.request_select_map(map_id)


func _on_board_start_requested() -> void:
	if not _active:
		return
	if not (LobbyManager.is_host or LobbyManager.is_room_host()):
		board_panel.set_status("SOLO EL HOST PUEDE INICIAR")
		return

	var player_count := 0
	for pid in LobbyManager.players:
		if not LobbyManager.is_spectator(pid):
			player_count += 1
	if player_count < 2 and not DevMode.is_enabled():
		board_panel.set_status("SE NECESITAN 2 JUGADORES")
		return

	board_panel.close_panel()
	if status_label:
		status_label.text = "INICIANDO PARTIDA..."

	if LobbyManager.is_host:
		LobbyManager.host_start_character_selection()
	else:
		LobbyManager.rpc_id(1, "request_start_match")


func _on_start_countdown_started(_seconds: float) -> void:
	if not _active:
		return
	if board_panel.is_open():
		board_panel.close_panel()
	if status_label:
		status_label.text = "INICIANDO PARTIDA..."


func _on_start_countdown_cancelled() -> void:
	if _active:
		_update_status()


# ── Sincronización de avatares (RPC, sin MultiplayerSynchronizer) ────────

## Llamado por el HubAvatar local. El servidor retransmite a todos.
func submit_hub_state(pos: Vector2, flip: bool) -> void:
	if not _active:
		return
	if multiplayer.is_server():
		_apply_hub_state.rpc(multiplayer.get_unique_id(), pos, flip)
	else:
		rpc_id(1, "_submit_hub_state", pos, flip)


@rpc("any_peer", "unreliable_ordered")
func _submit_hub_state(pos: Vector2, flip: bool) -> void:
	if not _active or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not _avatars.has(sender):
		return
	if not pos.is_finite():
		return
	if pos.distance_to(hub_spawn.global_position) > 3000.0:
		return
	_apply_hub_state.rpc(sender, pos, flip)


@rpc("authority", "unreliable_ordered", "call_local")
func _apply_hub_state(peer_id: int, pos: Vector2, flip: bool) -> void:
	if not _active:
		return
	var avatar = _avatars.get(peer_id)
	if avatar and is_instance_valid(avatar):
		avatar.apply_remote_state(pos, flip)


# ── Ciclo de escena ─────────────────────────────────────────────────────

## Llamado por LobbyManager antes de pasar a CharacterSelect. En servidor
## dedicado la escena queda como shell sin avatares; en clientes se libera
## igual al cambiar de escena.
func prepare_for_match() -> void:
	if not _active:
		return
	_active = false
	set_process_unhandled_input(false)

	if LobbyManager.lobby_updated.is_connected(_on_lobby_updated):
		LobbyManager.lobby_updated.disconnect(_on_lobby_updated)
	if LobbyManager.player_joined.is_connected(_on_player_joined):
		LobbyManager.player_joined.disconnect(_on_player_joined)
	if LobbyManager.player_left.is_connected(_on_player_left):
		LobbyManager.player_left.disconnect(_on_player_left)

	for avatar in _avatars.values():
		if is_instance_valid(avatar):
			avatar.queue_free()
	_avatars.clear()
	_local_avatar = null

	if status_label:
		status_label.visible = false
	if prompt_label:
		prompt_label.visible = false
	if board_panel:
		board_panel.visible = false
	$HubArea.visible = false
	$MatchArea.visible = false
	$Actors.visible = false
	$UI.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	# Atajo de debug solo para la escena standalone.
	if not _is_networked() \
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

	var leave: bool = event.is_action_pressed("menu_cancel") \
			or event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_X)
	if leave:
		if board_panel.is_open():
			return
		var vp2 := get_viewport()
		if vp2:
			vp2.set_input_as_handled()
		MatchCoordinator.reset_to_menu()


func _update_status() -> void:
	if status_label == null:
		return
	if _in_match:
		status_label.text = "PARTIDA (DEBUG) — F2 VOLVER AL HUB"
		return
	var count := LobbyManager.players.size()
	if count <= 1:
		status_label.text = "HUB — ACERCATE AL TABLERO"
	else:
		status_label.text = "HUB — %d JUGADORES — ACERCATE AL TABLERO" % count


# ── Debug local del spike (sin red) ─────────────────────────────────────

func _enter_match() -> void:
	if _in_match or _local_avatar == null:
		return
	_in_match = true
	if prompt_label:
		prompt_label.visible = false
	_update_status()

	_match_instance = TEST_MAP_SCENE.instantiate()
	map_container.add_child(_match_instance)
	if not _match_instance.is_node_ready():
		await _match_instance.ready

	var spawn := match_area.global_position
	if _match_instance.has_method("get_random_survivor_spawn"):
		spawn = _match_instance.get_random_survivor_spawn()
	_local_avatar.global_position = spawn
	print("[Session] Debug: partida cargada en ", spawn)


func _return_to_hub() -> void:
	if not _in_match:
		return
	_in_match = false

	if is_instance_valid(_match_instance):
		_match_instance.queue_free()
	_match_instance = null

	if _local_avatar:
		_local_avatar.global_position = _get_spawn_position(_local_peer_id())
	if prompt_label:
		prompt_label.visible = false
	_update_status()
	print("[Session] Debug: vuelta al hub")
