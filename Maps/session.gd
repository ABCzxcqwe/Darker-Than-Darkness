# res://Maps/session.gd
# Escena persistente de sala/hub y partida. El HubArea y sus avatares siguen
# vivos; el World de la partida cuelga de MatchArea (lejos del hub) y se muestra
# u oculta según la vista local: jugando, espectando o en el hub.
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
var _match_running := false
var _match_ended := false
var _at_hub := true
var _match_instance: Node = null
var _standalone_dummy := false
var _sync_queued := false
var _character_overlay: Control = null
var _character_layer: CanvasLayer = null
var _game_menu: Control = null
var _quick_bar: VBoxContainer = null
var _quick_afk_btn: Button = null
var _quick_spectate_btn: Button = null
var _quick_partida_btn: Button = null
var _countdown_left := 0.0
var _countdown_timer: Timer = null


func _ready() -> void:
	add_to_group("hub_session")
	_setup_hub_audio()
	LobbyManager.lobby_updated.connect(_on_lobby_updated)
	LobbyManager.player_joined.connect(_on_player_joined)
	LobbyManager.player_left.connect(_on_player_left)
	MatchCoordinator.start_countdown_started.connect(_on_start_countdown_started)
	MatchCoordinator.start_countdown_cancelled.connect(_on_start_countdown_cancelled)
	LobbyManager.character_select_started.connect(_on_character_select_started)

	hub_board.interacted.connect(_on_board_interacted)
	board_panel.start_requested.connect(_on_board_start_requested)
	board_panel.closed.connect(_on_board_closed)
	board_panel.map_selected.connect(_on_map_selected)
	board_panel.cancel_requested.connect(_on_board_cancel_requested)
	board_panel.afk_toggle_requested.connect(_on_board_afk_toggle)
	board_panel.host_action_requested.connect(_on_board_host_action)

	_countdown_timer = Timer.new()
	_countdown_timer.wait_time = 1.0
	_countdown_timer.one_shot = false
	_countdown_timer.timeout.connect(_on_countdown_tick)
	add_child(_countdown_timer)

	_build_quick_actions()
	_game_menu = get_node_or_null("UI/DarkGameMenu")
	_configure_hub_game_menu()
	_sync_avatars()
	_update_status()

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
		_update_status()
		_configure_hub_game_menu()
		_refresh_quick_actions()
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
	if LobbyManager.character_select_started.is_connected(_on_character_select_started):
		LobbyManager.character_select_started.disconnect(_on_character_select_started)


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
	_refresh_quick_actions()
	if board_panel.is_open():
		board_panel.refresh()


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
	if _local_avatar and not _at_hub:
		_set_local_avatar_hub_visible(false)
	for pid in _avatars:
		var avatar = _avatars[pid]
		if is_instance_valid(avatar):
			var show_avatar := LobbyManager.is_in_hub(int(pid))
			if int(pid) == _local_peer_id():
				show_avatar = _at_hub
			avatar.visible = show_avatar
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
		if not _at_hub:
			_set_local_avatar_hub_visible(false)
	avatar.visible = _at_hub if peer_id == _local_peer_id() else LobbyManager.is_in_hub(peer_id)
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
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.get_peers().size() > 0 or multiplayer.get_unique_id() > 1


func _local_peer_id() -> int:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return 1
	var id := multiplayer.get_unique_id()
	if id <= 1 and multiplayer.get_peers().is_empty():
		return 1
	return id


func _can_spawn_standalone_dummy() -> bool:
	var ds := get_node_or_null("/root/DedicatedServer")
	if ds and ds.is_dedicated:
		return false
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return true
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
	_open_board_panel()


func _open_board_panel() -> void:
	if not _active or _in_match:
		return
	if prompt_label:
		prompt_label.visible = false
	if _local_avatar and is_instance_valid(_local_avatar):
		_local_avatar.set_controls_enabled(false)
	var can_manage: bool = LobbyManager.is_host or LobbyManager.is_room_host()
	board_panel.open_panel(can_manage)


func _on_board_closed() -> void:
	if _at_hub and not is_instance_valid(_character_overlay) \
			and _local_avatar and is_instance_valid(_local_avatar):
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
	if LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY or _match_running:
		board_panel.set_status("YA HAY UNA PARTIDA EN CURSO")
		return

	var active := LobbyManager.get_active_participants()
	if active.size() < 2 and not DevMode.is_enabled():
		board_panel.set_status("SE NECESITAN 2 JUGADORES ACTIVOS")
		return

	if LobbyManager.is_host:
		MatchCoordinator.start_match_countdown()
	else:
		LobbyManager.rpc_id(1, "request_start_match")
	board_panel.refresh()


func _on_board_cancel_requested() -> void:
	if LobbyManager.is_host:
		MatchCoordinator.stop_match_countdown()
	else:
		LobbyManager.rpc_id(1, "request_cancel_start")


func _on_board_afk_toggle() -> void:
	LobbyManager.request_toggle_afk()


func _on_board_host_action(action: String, peer_id: int) -> void:
	if not (LobbyManager.is_host or LobbyManager.is_room_host()):
		return
	match action:
		"spectator":
			LobbyManager.host_set_spectator(peer_id)
		"survivor":
			LobbyManager.host_set_survivor(peer_id)
		"killer":
			LobbyManager.host_force_killer(peer_id)
		"kick":
			LobbyManager.host_kick_player(peer_id)
	board_panel.refresh()


func _on_start_countdown_started(seconds: float) -> void:
	if not _active:
		return
	_countdown_left = seconds
	if status_label:
		status_label.text = "INICIANDO PARTIDA..."
	board_panel.set_countdown(seconds)
	if _countdown_timer:
		_countdown_timer.start()


func _on_start_countdown_cancelled() -> void:
	if not _active:
		return
	_countdown_left = 0.0
	if _countdown_timer:
		_countdown_timer.stop()
	board_panel.set_countdown(0.0)
	_update_status()


func _on_countdown_tick() -> void:
	if _countdown_left <= 0.0:
		if _countdown_timer:
			_countdown_timer.stop()
		return
	_countdown_left = maxf(_countdown_left - 1.0, 0.0)
	board_panel.set_countdown(_countdown_left)
	if status_label:
		status_label.text = "INICIANDO EN %d..." % int(_countdown_left)
	if _countdown_left <= 0.0 and _countdown_timer:
		_countdown_timer.stop()


func _on_character_select_started() -> void:
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return
	var my_id := multiplayer.get_unique_id()
	if not LobbyManager.is_match_participant(my_id):
		# AFK / espectador: se queda en el hub.
		_queue_sync()
		_update_status()
		_refresh_quick_actions()
		return
	if is_instance_valid(_character_overlay):
		return

	if prompt_label:
		prompt_label.visible = false
	if board_panel.is_open():
		board_panel.close_panel()
	if _local_avatar and is_instance_valid(_local_avatar):
		_local_avatar.set_controls_enabled(false)

	var packed: PackedScene = load("res://ui/GameUI/Scenes/CharacterSelect.tscn")
	_character_overlay = packed.instantiate()
	_character_overlay.name = "CharacterSelectOverlay"
	# El overlay debe vivir en su propia capa alta: si se cuelga del UI del hub,
	# el fondo del hub y los z_index internos del carrusel compiten con él.
	if _character_layer == null or not is_instance_valid(_character_layer):
		_character_layer = CanvasLayer.new()
		_character_layer.name = "CharacterSelectLayer"
		_character_layer.layer = 50
		add_child(_character_layer)
	_character_layer.visible = true
	_character_layer.add_child(_character_overlay)
	_character_overlay.tree_exited.connect(func() -> void:
		_character_overlay = null
		if _active and _at_hub and _local_avatar and is_instance_valid(_local_avatar):
			_local_avatar.set_controls_enabled(true)
		_update_status()
		_refresh_quick_actions()
	)
	if status_label:
		status_label.text = "ELECCIÓN DE PERSONAJE"


func get_match_root() -> Node2D:
	return $MatchArea


## Participante que empieza a jugar: el hub sigue existiendo pero oculto.
func enter_match_view() -> void:
	_in_match = true
	_match_running = true
	_match_ended = false
	_at_hub = false
	if _character_layer and is_instance_valid(_character_layer):
		_character_layer.visible = false
	LobbyManager.set_local_presence("match")
	_close_hub_overlays()
	_set_hub_visible(false)
	_set_local_avatar_hub_visible(false)
	_configure_hub_game_menu()
	_refresh_quick_actions()


## Participante muerto o jugador del hub que empieza a espectar.
func enter_spectator_view() -> void:
	if not _in_match:
		_in_match = true
	if not _match_running:
		_match_running = true
	_at_hub = false
	if _character_layer and is_instance_valid(_character_layer):
		_character_layer.visible = false
	LobbyManager.set_local_presence("spectate")
	_close_hub_overlays()
	_set_hub_visible(false)
	_set_local_avatar_hub_visible(false)
	_configure_hub_game_menu()
	_refresh_quick_actions()


## Vuelta local al hub sin terminar la partida. El World sigue vivo y el
## jugador puede volver a espectar con el botón ESPECTAR.
func return_to_hub_from_spectate() -> void:
	_at_hub = true
	_in_match = true
	if _character_layer and is_instance_valid(_character_layer):
		_character_layer.visible = false
	LobbyManager.set_local_presence("hub")
	_set_hub_visible(true)
	_set_local_avatar_hub_visible(true, true)
	MatchCoordinator.set_local_view_mode("hub")
	_update_status()
	_configure_hub_game_menu()
	_refresh_quick_actions()


## No participante / AFK / late join: ve el hub mientras la partida corre.
func on_match_started_for_hub() -> void:
	_in_match = true
	_match_running = true
	_match_ended = false
	_at_hub = true
	if _character_layer and is_instance_valid(_character_layer):
		_character_layer.visible = false
	LobbyManager.set_local_presence("hub")
	_close_hub_overlays()
	_set_hub_visible(true)
	_set_local_avatar_hub_visible(true)
	_update_status()
	_configure_hub_game_menu()
	_refresh_quick_actions()


## La partida terminó y este peer no va a resultados (AFK/espectador/late join).
func on_match_ended_for_hub() -> void:
	_match_running = false
	_match_ended = true
	_in_match = true
	if _character_layer and is_instance_valid(_character_layer):
		_character_layer.visible = false
	LobbyManager.set_local_presence("hub")
	if board_panel.is_open():
		board_panel.close_panel()
	if not _at_hub:
		_at_hub = true
		_set_hub_visible(true)
		_set_local_avatar_hub_visible(true, true)
		MatchCoordinator.set_local_view_mode("hub")
	_setup_hub_audio()
	_update_status()
	_configure_hub_game_menu()
	_refresh_quick_actions()


func _set_hub_visible(visible_now: bool) -> void:
	$HubArea.visible = visible_now
	$Actors.visible = visible_now
	$UI.visible = visible_now
	$UI.process_mode = Node.PROCESS_MODE_INHERIT if visible_now else Node.PROCESS_MODE_DISABLED


func _close_hub_overlays() -> void:
	if board_panel.is_open():
		board_panel.close_panel()
	if _game_menu and _game_menu.has_method("force_close"):
		_game_menu.force_close()
	var chat := get_node_or_null("UI/ChatPanel")
	if chat and chat.has_method("close_input"):
		chat.close_input()


func _set_local_avatar_hub_visible(visible_now: bool, reset_position: bool = false) -> void:
	if _local_avatar == null or not is_instance_valid(_local_avatar):
		return
	_local_avatar.visible = visible_now
	_local_avatar.set_controls_enabled(visible_now)
	if reset_position and visible_now:
		_local_avatar.global_position = _get_spawn_position(_local_peer_id())
	var cam := _local_avatar.get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.enabled = visible_now
		if visible_now:
			cam.make_current()


func _configure_hub_game_menu() -> void:
	if _game_menu == null:
		return
	if not _game_menu.has_method("set_hub_mode"):
		return
	var show_stats := false
	if multiplayer and multiplayer.multiplayer_peer != null:
		var my_id := multiplayer.get_unique_id()
		show_stats = _match_running and LobbyManager.is_match_participant(my_id)
	_game_menu.set_hub_mode(true, show_stats)


func _build_quick_actions() -> void:
	_quick_bar = VBoxContainer.new()
	_quick_bar.name = "HubQuickActions"
	_quick_bar.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_quick_bar.offset_left = 24.0
	_quick_bar.offset_right = 224.0
	_quick_bar.offset_top = -150.0
	_quick_bar.offset_bottom = 150.0
	_quick_bar.add_theme_constant_override("separation", 10)
	$UI.add_child(_quick_bar)

	_quick_partida_btn = _make_quick_button("PARTIDA")
	_quick_partida_btn.pressed.connect(_on_quick_partida)
	_quick_bar.add_child(_quick_partida_btn)

	_quick_spectate_btn = _make_quick_button("ESPECTAR")
	_quick_spectate_btn.pressed.connect(_on_quick_spectate)
	_quick_bar.add_child(_quick_spectate_btn)

	_quick_afk_btn = _make_quick_button("AFK")
	_quick_afk_btn.pressed.connect(_on_quick_afk)
	_quick_bar.add_child(_quick_afk_btn)

	_refresh_quick_actions()


func _make_quick_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200, 42)
	b.add_theme_font_override("font", load("res://Fonts/deltarune font.ttf"))
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7, 1.0))
	b.focus_mode = Control.FOCUS_ALL
	return b


func _refresh_quick_actions() -> void:
	if _quick_bar == null:
		return
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		return
	var my_id := multiplayer.get_unique_id()
	var in_lobby := LobbyManager.current_phase == LobbyManager.GamePhase.LOBBY \
		and not _in_match and _at_hub
	_quick_partida_btn.disabled = not in_lobby
	_quick_spectate_btn.disabled = not _match_running or _match_ended
	_quick_afk_btn.disabled = not in_lobby or not LobbyManager.can_local_toggle_afk()
	if LobbyManager.players.has(my_id):
		_quick_afk_btn.text = "AFK: SÍ" if LobbyManager.is_afk(my_id) else "AFK: NO"
	else:
		_quick_afk_btn.text = "AFK: NO"


func _on_quick_partida() -> void:
	if not _active or _in_match or not _at_hub:
		return
	_open_board_panel()


func _on_quick_spectate() -> void:
	if not _match_running or _match_ended or not _at_hub:
		return
	if not MatchCoordinator.request_spectate() and status_label:
		status_label.text = "SINCRONIZANDO PARTIDA..."


func _on_quick_afk() -> void:
	if LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY or _in_match:
		return
	LobbyManager.request_toggle_afk()




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

## Compatibilidad con el flujo anterior. La Fase B ya no destruye el hub: la
## Session queda viva y solo se oculta la vista del hub para el participante.
func prepare_for_match() -> void:
	if not _active:
		return
	enter_match_view()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if is_instance_valid(_character_overlay):
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

	# Durante una partida (incluido el hub de muertos/espectadores/AFK) o una
	# selección de personaje, el input de salida del hub no debe poder expulsar
	# al jugador. La salida explícita vive en el menú de pausa.
	if _in_match or LobbyManager.current_phase != LobbyManager.GamePhase.LOBBY:
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
		if _match_ended:
			status_label.text = "PARTIDA FINALIZADA — ESPERANDO AL HOST"
		elif LobbyManager.current_phase == LobbyManager.GamePhase.CHARACTER_SELECT:
			status_label.text = "SELECCIÓN DE PERSONAJE EN CURSO"
		elif _match_running and _at_hub:
			status_label.text = "PARTIDA EN CURSO — PODÉS ESPECTAR"
		elif _match_running:
			status_label.text = "PARTIDA EN CURSO"
		else:
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
	_at_hub = false
	_set_hub_visible(false)
	_set_local_avatar_hub_visible(false)
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
	_at_hub = true
	_set_hub_visible(true)
	_set_local_avatar_hub_visible(true, true)

	if is_instance_valid(_match_instance):
		_match_instance.queue_free()
	_match_instance = null

	if prompt_label:
		prompt_label.visible = false
	_update_status()
	print("[Session] Debug: vuelta al hub")
