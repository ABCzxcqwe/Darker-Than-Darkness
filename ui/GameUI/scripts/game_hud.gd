# game_hud.gd
# HUD principal del juego. Solo existe en el cliente local.
# Recibe notificaciones de cooldown desde CooldownService (via RPC).
# Gestiona el menú de selección de objetivo con desplazamiento del panel.
extends CanvasLayer

@onready var player_panel: Control       = $PlayerPanel
@onready var allies_panel: Control       = $AlliesPanel
@onready var ability_bar:  HBoxContainer = $AbilityBar

# Altura en px que sube el PlayerPanel al abrir el menú de selección
const PANEL_SLIDE_OFFSET := -80.0
const SLIDE_DURATION     := 0.15   # segundos del tween

var _player_node:      Node  = null
var _panel_base_pos:   float = 0.0   # posición Y original del PlayerPanel
var _menu_open:        bool  = false

# Señal para que las habilidades escuchen la selección del jugador
signal selection_confirmed(selection_type: String, payload: Variant)
signal selection_cancelled()


func _ready() -> void:
	add_to_group("game_hud")


func setup(player_node: Node) -> void:
	_player_node = player_node
	var my_peer_id := player_node.get_multiplayer_authority()

	if player_panel and player_panel.has_method("setup"):
		player_panel.setup(player_node)
		_panel_base_pos = player_panel.position.y

	if allies_panel and allies_panel.has_method("setup"):
		allies_panel.setup(my_peer_id)

	if ability_bar and ability_bar.has_method("setup"):
		ability_bar.setup(player_node)

	if player_node.has_signal("ability_used"):
		player_node.ability_used.connect(_on_ability_used)

	var evolution_service: Node = GameServiceLocator.get_service("EvolutionService")
	if evolution_service:
		evolution_service.slot_evolved.connect(_on_slot_evolved)
		evolution_service.slot_devolved.connect(_on_slot_devolved)

	print("[GameHUD] HUD configurado para peer ", my_peer_id)


# ── Cooldown recibido desde CooldownService ────────────────────────────

## Llamado por CooldownService._rpc_cooldown_started() cuando el servidor
## notifica al cliente que un cooldown comenzó.
func on_cooldown_started(ability_name: String, slot_index: int, duration: float) -> void:
	if ability_bar and ability_bar.has_method("on_cooldown_started"):
		ability_bar.on_cooldown_started(ability_name, slot_index, duration)


# ── Habilidad usada ────────────────────────────────────────────────────

func _on_ability_used(_slot_index: int) -> void:
	# El cooldown visual ahora viene del servidor via on_cooldown_started().
	# Esta señal se mantiene por si algún sistema externo la necesita.
	pass


# ── Evolución ─────────────────────────────────────────────────────────

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


# ── Menú de selección de objetivo ─────────────────────────────────────

## Llamado por el script de una habilidad que necesita que el jugador
## seleccione algo antes de activarse.
##
## selection_type: "ally", "area", "confirm" — o cualquier String custom.
## El HUD abre el menú correspondiente y emite selection_confirmed() o
## selection_cancelled() cuando el jugador elige.
##
## Ejemplo desde una habilidad:
##   var hud := _find_hud()
##   hud.request_selection("ally", callback)
func request_selection(selection_type: String, on_confirm: Callable, on_cancel: Callable = Callable()) -> void:
	if _menu_open:
		return
	_menu_open = true
	_slide_panel(true)

	# Conectar listeners de un solo uso
	var confirm_conn: Callable
	var cancel_conn:  Callable

	confirm_conn = func(type: String, payload: Variant) -> void:
		if type != selection_type:
			return
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

	# TODO: instanciar el widget de selección adecuado según selection_type.
	# Por ahora se muestra solo el desplazamiento del panel; el submenú
	# se implementa por habilidad o con un nodo hijo dedicado.
	# Cuando el jugador confirme, llamar: emit_signal("selection_confirmed", selection_type, payload)
	# Cuando cancele (ESC u otra tecla): emit_signal("selection_cancelled")


## Cancela cualquier menú de selección abierto desde fuera (ej: el jugador muere).
func cancel_selection() -> void:
	if not _menu_open:
		return
	selection_cancelled.emit()


func _close_selection_menu() -> void:
	_menu_open = false
	_slide_panel(false)


func _input(event: InputEvent) -> void:
	if _menu_open and event.is_action_pressed("ui_cancel"):
		cancel_selection()
		get_viewport().set_input_as_handled()


# ── Animación del panel ────────────────────────────────────────────────

func _slide_panel(slide_up: bool) -> void:
	if not player_panel:
		return
	var target_y := _panel_base_pos + (PANEL_SLIDE_OFFSET if slide_up else 0.0)
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(player_panel, "position:y", target_y, SLIDE_DURATION)
