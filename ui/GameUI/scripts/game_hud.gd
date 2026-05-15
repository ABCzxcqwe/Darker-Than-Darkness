# game_hud.gd
extends CanvasLayer

@onready var player_panel: Control       = $PlayerPanel
@onready var allies_panel: Control       = $AlliesPanel
@onready var ability_bar:  HBoxContainer = $AbilityBar
# Asumiendo que la TpBar está instanciada en el HUD o dentro del PlayerPanel
@onready var tp_bar: Control             = find_child("TpBar", true, false)

const PANEL_SLIDE_OFFSET := -80.0
const SLIDE_DURATION     := 0.15

var _player_node:      Node  = null
var _panel_base_pos:   float = 0.0
var _menu_open:        bool  = false

signal selection_confirmed(selection_type: String, payload: Variant)
signal selection_cancelled()

func _ready() -> void:
	add_to_group("game_hud")

func setup(player_node: Node) -> void:
	_player_node = player_node
	# IMPORTANTE: En el cliente, esto devolverá su ID único (ej: 1642049501)
	# En el host, esto devolverá 1.
	var my_real_id := multiplayer.get_unique_id() 
	# 1. Configurar Panel de Jugador
	if player_panel and player_panel.has_method("setup"):
		player_panel.setup(player_node)
		_panel_base_pos = player_panel.position.y
	# 2. Configurar Aliados y Habilidades
	if allies_panel and allies_panel.has_method("setup"):
		allies_panel.setup(my_real_id) # Usamos el ID real aquí también
	if ability_bar and ability_bar.has_method("setup"):
		ability_bar.setup(player_node)
	# 3. Configurar Barra de TP
	var tp_node = find_child("TpBar", true, false)
	if tp_node and tp_node.has_method("setup"):
		var max_tp = 100.0
		if player_node.get("character_data"):
			max_tp = player_node.character_data.tp_max
		# Vinculamos la barra al ID real del cliente
		tp_node.setup(my_real_id, max_tp)
		print("[GameHUD] Barra de TP vinculada al peer local REAL: ", my_real_id)
	else:
		# Esto es solo un aviso por si no la encuentra en el árbol
		print("[GameHUD] Nota: No se encontró 'TpBar' en esta instancia.")
	# 4. Conectar señales de combate
	if player_node.has_signal("ability_used"):
		player_node.ability_used.connect(_on_ability_used)
	var evolution_service: Node = GameServiceLocator.get_service("EvolutionService")
	if evolution_service:
		evolution_service.slot_evolved.connect(_on_slot_evolved)
		evolution_service.slot_devolved.connect(_on_slot_devolved)
	print("[GameHUD] HUD configurado completamente para peer: ", my_real_id)

func on_cooldown_started(ability_name: String, slot_index: int, duration: float) -> void:
	if ability_bar and ability_bar.has_method("on_cooldown_started"):
		ability_bar.on_cooldown_started(ability_name, slot_index, duration)

func _on_ability_used(_slot_index: int) -> void:
	pass

func _on_slot_evolved(peer_id: int, slot_index: int) -> void:
	if peer_id != _player_node.get_multiplayer_authority():
		return
	if ability_bar and ability_bar.has_method("on_slot_evolved"):
		ability_bar.on_slot_evolved(slot_index)

func _on_slot_devolved(peer_id: int, slot_index: int) -> void:
	if peer_id != _player_node.get_multiplayer_authority():
		return
	if ability_bar and ability_bar.has_method("on_slot_devolved"):
		ability_bar.on_slot_devolved(slot_index)

func request_selection(selection_type: String, on_confirm: Callable, on_cancel: Callable = Callable()) -> void:
	if _menu_open: return
	_menu_open = true
	_slide_panel(true)

	var confirm_conn: Callable
	var cancel_conn:  Callable

	confirm_conn = func(type: String, payload: Variant) -> void:
		if type != selection_type: return
		selection_confirmed.disconnect(confirm_conn)
		if selection_cancelled.is_connected(cancel_conn):
			selection_cancelled.disconnect(cancel_conn)
		_close_selection_menu()
		on_confirm.call(payload)

	cancel_conn = func() -> void:
		selection_confirmed.disconnect(confirm_conn)
		selection_cancelled.disconnect(cancel_conn)
		_close_selection_menu()
		if on_cancel.is_valid():
			on_cancel.call()

	selection_confirmed.connect(confirm_conn)
	selection_cancelled.connect(cancel_conn)

func cancel_selection() -> void:
	if not _menu_open: return
	selection_cancelled.emit()

func _close_selection_menu() -> void:
	_menu_open = false
	_slide_panel(false)

func _input(event: InputEvent) -> void:
	if _menu_open and event.is_action_pressed("ui_cancel"):
		cancel_selection()
		get_viewport().set_input_as_handled()

func _slide_panel(slide_up: bool) -> void:
	if not player_panel: return
	var target_y := _panel_base_pos + (PANEL_SLIDE_OFFSET if slide_up else 0.0)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(player_panel, "position:y", target_y, SLIDE_DURATION)
