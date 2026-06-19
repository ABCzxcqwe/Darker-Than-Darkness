# res://scripts/game_hud.gd
# HUD principal de la partida. Se configura una sola vez con setup(player_node).
# Gestiona: timer, TP, panel de jugador, habilidades, aliados y menú contextual estático.
extends CanvasLayer

# ── Nodos ──────────────────────────────────────────────────────────────
@onready var timer_panel:      PanelContainer = $TimerPanel
@onready var timer_label:      Label          = $TimerPanel/VBoxContainer/TimerLabel
@onready var timer_numbers:    Label          = $TimerPanel/VBoxContainer/TimerNumbers

@onready var tp_bar:           Control        = $TpBar

@onready var killer_hp_public: PanelContainer = $KillerHpPublic
@onready var killer_name_lbl:  Label          = $KillerHpPublic/HBoxContainer/KillerNameLabel
@onready var killer_hp_bar:    ProgressBar    = $KillerHpPublic/HBoxContainer/KillerHpBar
@onready var killer_hp_nums:   Label          = $KillerHpPublic/HBoxContainer/KillerHpNumbers

@onready var player_panel_wrap: VBoxContainer  = $PlayerPanelWrap
@onready var player_panel:      PanelContainer = $PlayerPanelWrap/PlayerPanel
@onready var ability_panel:     PanelContainer = $PlayerPanelWrap/AbilityPanel
@onready var ability_bar:       HBoxContainer  = $PlayerPanelWrap/AbilityPanel/AbilityBar

@onready var context_menu:     PanelContainer  = $ContextMenu
@onready var context_title:    Label           = $ContextMenu/VBoxContainer/ContextTitle
@onready var context_grid:     GridContainer   = $ContextMenu/VBoxContainer/ContextGrid
@onready var context_hint:     Label           = $ContextMenu/VBoxContainer/ContextHint

@onready var allies_panel:     VBoxContainer   = $AlliesPanel

# ── Constantes ─────────────────────────────────────────────────────────
const CONTEXT_ITEM_SCENE := preload("uid://b8p1jgthpblec")
const TIMER_URGENT_SECS  := 15.0
const COLOR_SURVIVOR:    Color = Color(0.27, 0.78, 0.95)  # cian
const COLOR_KILLER:      Color = Color(1.0,  0.27, 0.27)  # rojo
const FONT_DELTARUNE    := preload("res://Fonts/deltarune font.ttf")

# ── Estado ─────────────────────────────────────────────────────────────
var _player_node:      Node     = null
var _my_team:          String   = "survivor"
var _theme_color:      Color    = COLOR_SURVIVOR
var _menu_open:        bool     = false
var _ctx_items:        Array    = []
var _ctx_selected_idx: int      = 0
var _on_confirm:       Callable = Callable()
var _on_cancel:        Callable = Callable()
var _my_id:            int        = 0
var _revive_prompts:   Dictionary = {}
var _name_labels:      Dictionary = {}
var _radar_layer:      Control    = null

signal selection_confirmed(peer_id: int)
signal selection_cancelled()

func _ready() -> void:
	add_to_group("game_hud")
	if context_menu:
		context_menu.visible = false
	if killer_hp_public:
		killer_hp_public.visible = false

func setup(player_node: Node) -> void:
	_player_node = player_node
	_my_id = multiplayer.get_unique_id()
	var my_id := _my_id

	if not player_node.character_data:
		push_warning("[GameHUD] Player sin character_data en setup.")
		return

	_my_team     = player_node.character_data.team
	_theme_color = player_node.character_data.theme_color

	# 1. PlayerPanels
	if player_panel and player_panel.has_method("setup"):
		player_panel.setup(player_node)
	if ability_panel and ability_panel.has_method("setup"):
		ability_panel.setup(player_node)
	if ability_bar and ability_bar.has_method("setup"):
		ability_bar.setup(player_node)

	# 2. TpBar
	if tp_bar and tp_bar.has_method("setup"):
		var max_tp: float = player_node.character_data.tp_max if player_node.character_data else 100.0
		tp_bar.setup(my_id, max_tp)

	# 3. AlliesPanel
	if allies_panel and allies_panel.has_method("setup"):
		allies_panel.setup(my_id, _my_team)

	# 4. RadarLayer
	var radar_script := load("res://ui/GameUI/scripts/radar_layer.gd")
	if radar_script and not _radar_layer:
		_radar_layer = Control.new()
		_radar_layer.name = "RadarLayer"
		_radar_layer.set_script(radar_script)
		_radar_layer.setup(my_id, _my_team)
		add_child(_radar_layer)
		_radar_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_radar_layer.set_anchors_preset(Control.PRESET_FULL_RECT)

	_configure_killer_hp_visibility(player_node)

	# 4. Conectar señales globales de servicios
	var timer_svc: Node = GameServiceLocator.get_service("TimerService")
	if timer_svc:
		timer_svc.timer_changed.connect(_on_timer_changed)

	if player_node.has_signal("ability_used"):
		player_node.ability_used.connect(_on_ability_used)

	var cooldown_svc: Node = GameServiceLocator.get_service("CooldownService")
	if cooldown_svc and cooldown_svc.has_signal("cooldown_state_changed"):
		cooldown_svc.cooldown_state_changed.connect(on_cooldown_state_changed)

	var evolution_svc: Node = GameServiceLocator.get_service("EvolutionService")
	if evolution_svc:
		evolution_svc.slot_evolved.connect(_on_slot_evolved)
		evolution_svc.slot_devolved.connect(_on_slot_devolved)

	var health_svc: Node = GameServiceLocator.get_service("HealthService")
	if health_svc and health_svc.has_signal("player_state_changed"):
		health_svc.player_state_changed.connect(_on_player_state_changed)

	NetworkManager.player_left.connect(_on_player_left_for_label)

	var revive_svc: Node = GameServiceLocator.get_service("ReviveService")
	if revive_svc:
		if revive_svc.has_signal("revive_started"):
			revive_svc.revive_started.connect(_on_revive_session_started)
		if revive_svc.has_signal("revive_cancelled"):
			revive_svc.revive_cancelled.connect(_on_revive_session_cancelled)
		if revive_svc.has_signal("revive_completed"):
			revive_svc.revive_completed.connect(_on_revive_session_completed)

	_create_name_labels()

	print("[GameHUD] HUD configurado para peer: ", my_id, " | equipo: ", _my_team)

# ── Configuración de HP del Killer ─────────────────────────────────────
func _configure_killer_hp_visibility(_node: Node) -> void:
	if _my_team == "killer":
		if killer_hp_public:
			killer_hp_public.visible = false
		if player_panel:
			var hp_row = player_panel.find_child("HpRow", true, false)
			if hp_row: hp_row.visible = false
			var hp_numbers = player_panel.find_child("HpNumbers", true, false)
			if hp_numbers: hp_numbers.visible = false
	else:
		_try_connect_killer_hp()

func _try_connect_killer_hp() -> void:
	var killers := get_tree().get_nodes_in_group("killer")
	if killers.is_empty(): return
	var killer := killers[0]
	if not killer.character_data: return

# ── Timer ──────────────────────────────────────────────────────────────
func _on_timer_changed(seconds_left: float) -> void:
	if not timer_numbers: return
	var m := int(seconds_left / 60.0)
	var s := int(seconds_left) % 60
	timer_numbers.text = "%02d:%02d" % [m, s]

	var urgent: bool = seconds_left <= TIMER_URGENT_SECS
	var color: Color = Color.RED if urgent else _theme_color
	if timer_label:
		timer_label.text     = "¡TIEMPO!" if urgent else "TIMER"
		timer_label.modulate = color
	_apply_panel_border_color(timer_panel, color)

# ── Cooldowns y evolución ──────────────────────────────────────────────
func on_cooldown_state_changed(slot_index: int, duration: float) -> void:
	if ability_bar and ability_bar.has_method("on_cooldown_state_changed"):
		ability_bar.on_cooldown_state_changed(slot_index, duration)

func _on_ability_used(_slot_index: int) -> void:
	pass

## Llamado por EvolutionService._rpc_sync_slot_state() desde el servidor
## para actualizar el visual de evolución en clientes remotos.
func visual_evolve_slot(slot_index: int) -> void:
	if ability_bar and ability_bar.has_method("on_slot_evolved"):
		ability_bar.on_slot_evolved(slot_index)

func visual_devolve_slot(slot_index: int) -> void:
	if ability_bar and ability_bar.has_method("on_slot_devolved"):
		ability_bar.on_slot_devolved(slot_index)

func _on_slot_evolved(peer_id: int, slot_index: int) -> void:
	if not is_instance_valid(_player_node):
		return
	if peer_id != _player_node.get_multiplayer_authority(): return
	if ability_bar and ability_bar.has_method("on_slot_evolved"):
		ability_bar.on_slot_evolved(slot_index)

func _on_slot_devolved(peer_id: int, slot_index: int) -> void:
	if not is_instance_valid(_player_node):
		return
	if peer_id != _player_node.get_multiplayer_authority(): return
	if ability_bar and ability_bar.has_method("on_slot_devolved"):
		ability_bar.on_slot_devolved(slot_index)

# ── TP readiness (servidor → cliente vía EvolutionService) ────────────
func visual_tp_ready(slot_index: int, is_ready: bool) -> void:
	if ability_bar and ability_bar.has_method("on_tp_ready"):
		ability_bar.on_tp_ready(slot_index, is_ready)

# ── Menú contextual Simplificado (Aparición directa) ───────────────────
func request_selection(title: String, on_confirm: Callable, on_cancel: Callable = Callable(), filter_peer_id: int = -1, can_target_self: bool = false) -> void:
	if _menu_open: return
	_menu_open   = true
	_on_confirm  = on_confirm
	_on_cancel   = on_cancel

	_build_context_items(filter_peer_id, can_target_self)

	if context_title:
		context_title.text = title.to_upper()
	if context_menu:
		context_menu.visible = true

	if can_target_self and filter_peer_id > 0 and _ctx_items.size() == 1:
		print("[GameHUD] Solo el caster disponible — auto-curando")
		_close_context_menu()
		if _on_confirm.is_valid():
			_on_confirm.call(filter_peer_id)
		return

	if not _ctx_items.is_empty():
		_select_ctx_item(0)

func cancel_selection() -> void:
	if not _menu_open: return
	_close_context_menu()
	if _on_cancel.is_valid():
		_on_cancel.call()
	selection_cancelled.emit()

func _build_context_items(filter_peer_id: int = -1, can_target_self: bool = false) -> void:
	for child in context_grid.get_children():
		child.queue_free()
	_ctx_items.clear()
	_ctx_selected_idx = 0

	for player in get_tree().get_nodes_in_group("survivor"):
		var data: CharacterData = player.character_data if player.get("character_data") else null
		if not data: continue

		var p_id = player.get_multiplayer_authority()
		# Saltar al propio caster si can_target_self es false
		if filter_peer_id > 0 and p_id == filter_peer_id and not can_target_self:
			continue

		var item = CONTEXT_ITEM_SCENE.instantiate()
		context_grid.add_child(item)

		var icon: Texture2D = data.icon if data.icon else null
		var p_name = NetworkManager.players.get(p_id, {}).get("name", "")
		item.setup(p_id, data.display_name, icon, p_name)
		item.item_clicked.connect(_on_ctx_item_clicked)

		_ctx_items.append(item)

func _on_ctx_item_clicked(peer_id: int) -> void:
	_close_context_menu()
	if _on_confirm.is_valid():
		_on_confirm.call(peer_id)
	selection_confirmed.emit(peer_id)

func _close_context_menu() -> void:
	_menu_open = false
	if context_menu:
		context_menu.visible = false # Desaparece al instante

func _select_ctx_item(idx: int) -> void:
	if _ctx_items.is_empty(): return
	_ctx_selected_idx = clamp(idx, 0, _ctx_items.size() - 1)
	for i in _ctx_items.size():
		if _ctx_items[i].has_method("set_selected"):
			_ctx_items[i].set_selected(i == _ctx_selected_idx)

# ── Input del menú contextual ──────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _menu_open: return

	if event.is_action_pressed("ui_cancel"):
		cancel_selection()
		get_viewport().set_input_as_handled()
		return

	var cols: int = context_grid.columns if context_grid else 2
	var is_key: bool = event is InputEventKey and event.pressed and not event.echo
	if is_key:
		match event.keycode:
			KEY_S, KEY_DOWN:
				_select_ctx_item(_ctx_selected_idx + cols)
				get_viewport().set_input_as_handled()
				return
			KEY_W, KEY_UP:
				_select_ctx_item(_ctx_selected_idx - cols)
				get_viewport().set_input_as_handled()
				return
			KEY_D, KEY_RIGHT:
				_select_ctx_item(_ctx_selected_idx + 1)
				get_viewport().set_input_as_handled()
				return
			KEY_A, KEY_LEFT:
				_select_ctx_item(_ctx_selected_idx - 1)
				get_viewport().set_input_as_handled()
				return

	if event.is_action_pressed("ui_down"):
		_select_ctx_item(_ctx_selected_idx + cols)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_select_ctx_item(_ctx_selected_idx - cols)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_select_ctx_item(_ctx_selected_idx + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_select_ctx_item(_ctx_selected_idx - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if not _ctx_items.is_empty():
			var target_item = _ctx_items[_ctx_selected_idx]
			# Verificamos que el nodo de UI tenga implementado get_peer_id()
			if target_item.has_method("get_peer_id"):
				_on_ctx_item_clicked(target_item.get_peer_id())
		get_viewport().set_input_as_handled()

# ── Revive prompts (marcador sobre el caído con barra de progreso) ───
func _on_player_state_changed(peer_id: int, state: String) -> void:
	if _my_team == "killer":
		return
	if state == "downed":
		var player = _find_player_by_peer_id(peer_id)
		if player:
			_create_revive_prompt(player)
	elif _revive_prompts.has(peer_id):
		_remove_revive_prompt(peer_id)


func _find_player_by_peer_id(peer_id: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_multiplayer_authority() == peer_id:
			return p
	return null


func _create_revive_prompt(player_node: Node) -> void:
	var pid = player_node.get_multiplayer_authority()
	if _revive_prompts.has(pid):
		return

	var panel := PanelContainer.new()
	panel.name = "RevivePrompt_%d" % pid

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.75)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color.WHITE
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()

	# ── Barra de progreso (oculta hasta presionar F) ──
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 1)
	bar_bg.custom_minimum_size = Vector2(130, 6)
	bar_bg.size = Vector2(130, 6)
	bar_bg.name = "BarBg"

	var bar_fill := ColorRect.new()
	bar_fill.color = Color(1, 1, 1, 1)
	bar_fill.size = Vector2(0, 6)
	bar_fill.position = Vector2(0, 0)
	bar_fill.name = "BarFill"

	bar_bg.add_child(bar_fill)
	vbox.add_child(bar_bg)

	var label := Label.new()
	label.text = "REVIVIR [F]"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT_DELTARUNE)
	label.add_theme_font_size_override("font_size", 16)
	label.modulate = Color.WHITE
	label.custom_minimum_size = Vector2(140, 28)
	vbox.add_child(label)

	panel.add_child(vbox)
	panel.size = Vector2(140, 38)

	add_child(panel)
	_revive_prompts[pid] = {
		"player": player_node,
		"panel": panel,
		"bar_bg": bar_bg,
		"bar_fill": bar_fill,
		"active": false,
		"start_time": 0.0,
		"duration": 0.0
	}


func _remove_revive_prompt(peer_id: int) -> void:
	var entry = _revive_prompts.get(peer_id)
	if not entry:
		return
	var panel = entry.get("panel")
	if is_instance_valid(panel):
		panel.queue_free()
	_revive_prompts.erase(peer_id)


# ── Seguimiento de sesión de revive activa ───────────────────────────
func _on_revive_session_started(rescuer_id: int, target_id: int, duration: float) -> void:
	if rescuer_id != _my_id:
		return
	var entry = _revive_prompts.get(target_id)
	if not entry:
		return
	entry["active"] = true
	entry["start_time"] = Time.get_ticks_msec() / 1000.0
	entry["duration"] = maxf(duration, 0.001)
	var fill = entry.get("bar_fill")
	if is_instance_valid(fill):
		fill.size.x = 0
	var bg = entry.get("bar_bg")
	if is_instance_valid(bg):
		bg.visible = true


func _on_revive_session_cancelled(rescuer_id: int, target_id: int) -> void:
	if rescuer_id != _my_id:
		return
	var entry = _revive_prompts.get(target_id)
	if not entry:
		return
	entry["active"] = false
	var fill = entry.get("bar_fill")
	if is_instance_valid(fill):
		fill.size.x = 0


func _on_revive_session_completed(rescuer_id: int, target_id: int) -> void:
	if rescuer_id != _my_id:
		return
	var entry = _revive_prompts.get(target_id)
	if entry:
		entry["active"] = false
		var fill = entry.get("bar_fill")
		var bg = entry.get("bar_bg")
		if is_instance_valid(fill) and is_instance_valid(bg):
			fill.size.x = bg.size.x
	if not is_instance_valid(self) or not is_inside_tree():
		return
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if _revive_prompts.has(target_id):
		_remove_revive_prompt(target_id)


func _process(_delta: float) -> void:
	for pid in _revive_prompts.keys():
		var entry = _revive_prompts[pid]
		if not entry:
			continue
		var player = entry.get("player")
		var panel = entry.get("panel")
		if not is_instance_valid(player) or not is_instance_valid(panel):
			_revive_prompts.erase(pid)
			continue
		var cam = get_viewport().get_camera_2d()
		if not cam:
			continue
		var screen_pos = cam.get_canvas_transform() * player.global_position
		panel.position = screen_pos + Vector2(-panel.size.x * 0.5, -80)

		# ── Animar barra de progreso ──
		var bar_bg = entry.get("bar_bg")
		var bar_fill = entry.get("bar_fill")
		if is_instance_valid(bar_bg) and is_instance_valid(bar_fill):
			if entry.get("active", false):
				var start_time = entry.get("start_time", 0.0)
				var duration = entry.get("duration", 0.001)
				var elapsed = Time.get_ticks_msec() / 1000.0 - start_time
				var progress = clampf(elapsed / duration, 0.0, 1.0)
				bar_fill.size.x = bar_bg.size.x * progress
				bar_bg.visible = true
			else:
				bar_bg.visible = false
				bar_fill.size.x = 0

		if _player_node and is_instance_valid(_player_node):
			var dist = _player_node.global_position.distance_to(player.global_position)
			panel.visible = dist <= 200.0
		else:
			panel.visible = true

	for pid in _name_labels:
		var entry = _name_labels[pid]
		if not entry:
			continue
		var player = entry.get("player")
		var panel = entry.get("panel")
		if not is_instance_valid(player) or not is_instance_valid(panel):
			_name_labels.erase(pid)
			continue
		var cam = get_viewport().get_camera_2d()
		if not cam:
			continue
		var screen_pos = cam.get_canvas_transform() * player.global_position
		panel.position = screen_pos + Vector2(-panel.size.x * 0.5, -120)

		if _player_node and is_instance_valid(_player_node):
			var dist = _player_node.global_position.distance_to(player.global_position)
			panel.visible = dist <= 1200.0
		else:
			panel.visible = true


# ── Name labels sobre los personajes ──────────────────────────────────
func _create_name_labels() -> void:
	for player in get_tree().get_nodes_in_group("players"):
		var pid = player.get_multiplayer_authority()
		if _name_labels.has(pid) or pid == _my_id:
			continue
		_create_name_label(player, pid)


func _create_name_label(player: Node, peer_id: int) -> void:
	var name_str = NetworkManager.players.get(peer_id, {}).get("name", "Jugador %d" % peer_id)

	var panel := PanelContainer.new()
	panel.name = "NameLabel_%d" % peer_id

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color.WHITE
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = name_str
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT_DELTARUNE)
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color.WHITE
	label.custom_minimum_size = Vector2(100, 20)

	panel.add_child(label)
	panel.size = Vector2(100, 22)

	add_child(panel)
	_name_labels[peer_id] = {
		"player": player,
		"panel": panel,
	}


func _remove_name_label(peer_id: int) -> void:
	var entry = _name_labels.get(peer_id)
	if not entry:
		return
	var panel = entry.get("panel")
	if is_instance_valid(panel):
		panel.queue_free()
	_name_labels.erase(peer_id)


func _on_player_left_for_label(peer_id: int) -> void:
	_remove_name_label(peer_id)


# ── Utilidades ─────────────────────────────────────────────────────────
func _apply_panel_border_color(panel: PanelContainer, color: Color) -> void:
	if not panel: return
	var style = panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		var s := style.duplicate() as StyleBoxFlat
		s.border_color = color
		panel.add_theme_stylebox_override("panel", s)
