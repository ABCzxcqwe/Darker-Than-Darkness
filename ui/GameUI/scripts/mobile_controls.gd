extends Control

## Controles táctiles de partida. La disposición vive en
## `res://ui/GameUI/Scenes/MobileControls.tscn` (editable en el editor):
## - MoveStick: movimiento
## - AimStick: apuntado (solo en partida)
## - CORRER: interruptor (toggle)
## - USAR: mantener pulsado
## - LISTA: mantener para ver la tabla de jugadores
## - OK / X: confirmar y cancelar habilidades en fase 2
## - PAUSA / EMOTE: pulsación simple
##
## Las habilidades no se duplican aquí: se activan tocando la barra de
## habilidades del HUD (AbilityButton responde a toques).
##
## Se muestra automáticamente en pantallas táctiles. En desktop se puede
## alternar con F8 para probar.

signal layout_changed(enabled: bool)

@onready var _run_btn: BaseButton = $RunBtn
@onready var _interact_btn: BaseButton = $InteractBtn
@onready var _pause_btn: BaseButton = $PauseBtn
@onready var _score_btn: BaseButton = $ScoreBtn
@onready var _emote_btn: BaseButton = $EmoteBtn
@onready var _confirm_btn: BaseButton = $ConfirmBtn
@onready var _cancel_btn: BaseButton = $CancelBtn
@onready var _move_stick = $MoveStick
@onready var _aim_stick = $AimStick

var player: Node = null

var _active: bool = false
var _held_actions: Dictionary = {}
var _target_is_player: bool = false
var _run_action_held: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bind_hold(_interact_btn, "interact")
	_bind_hold(_score_btn, "scoreboard")
	_bind_tap(_pause_btn, "pause")
	_bind_tap(_emote_btn, "emote_toggle")
	_bind_tap(_confirm_btn, "confirm")
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	_run_btn.toggled.connect(_on_run_toggled)
	_move_stick.changed.connect(_on_move_changed)
	_aim_stick.changed.connect(_on_aim_changed)
	# Hasta que setup() diga lo contrario, los controles de partida no aplican.
	_aim_stick.visible = false
	_confirm_btn.visible = false
	_cancel_btn.visible = false
	var tm := get_node_or_null("/root/ThemeManager")
	if tm:
		if tm.has_signal("theme_changed"):
			tm.theme_changed.connect(_on_theme_arg)
		if tm.has_signal("palette_changed"):
			tm.palette_changed.connect(_on_theme_arg)
	_apply_theme()
	_set_active(is_touch_device())


func _process(_delta: float) -> void:
	_refresh_visibility()


## Llamado por GameHUD (jugador de partida) o Session (avatar del hub).
func setup(target: Node) -> void:
	if player != target and is_instance_valid(player):
		_clear_virtual_state(player)
	_reset_sticks()
	player = target
	_target_is_player = target != null and target.get("input_component") != null
	# En el hub no hay apuntado/scoreboard/emotes: solo mover, correr, usar y pausa.
	_score_btn.visible = _target_is_player
	_emote_btn.visible = _target_is_player
	_aim_stick.visible = _target_is_player
	_confirm_btn.visible = _target_is_player
	_cancel_btn.visible = _target_is_player


func is_touch_device() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


func _refresh_visibility() -> void:
	var menu_open := MenuUtils.is_any_menu_open(get_tree())
	var hud := get_parent()
	if hud and hud.has_method("is_menu_open"):
		menu_open = menu_open or bool(hud.is_menu_open())
	var target_visible := true
	if is_instance_valid(player) and player is CanvasItem:
		target_visible = (player as CanvasItem).visible
	var show := _active and not menu_open and target_visible
	if visible == show:
		return
	visible = show
	if not show:
		# Al ocultarse (pausa/menú) soltamos todo para no dejar acciones
		# pegadas ni al jugador caminando con el joystick.
		_release_held_actions()
		_reset_sticks()


func _unhandled_input(event: InputEvent) -> void:
	# F8: mostrar/ocultar en desktop para probar el layout táctil.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F8:
		_set_active(not _active)
		get_viewport().set_input_as_handled()


func _set_active(enabled: bool) -> void:
	_active = enabled
	if not enabled:
		_release_held_actions()
		_reset_sticks()
	_refresh_visibility()
	layout_changed.emit(enabled)


func _bind_hold(btn: BaseButton, action: String) -> void:
	btn.button_down.connect(_on_hold.bind(action, true))
	btn.button_up.connect(_on_hold.bind(action, false))


func _on_hold(action: String, pressed: bool) -> void:
	if pressed:
		_held_actions[action] = true
	else:
		_held_actions.erase(action)
	_emit_action(action, pressed)


func _bind_tap(btn: BaseButton, action: String) -> void:
	btn.pressed.connect(_tap_action.bind(action))


func _tap_action(action: String) -> void:
	_emit_action(action, true)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_emit_action(action, false)


## CORRER es interruptor: deja la acción "run" pulsada hasta que se apague.
func _on_run_toggled(pressed: bool) -> void:
	_run_action_held = pressed
	if pressed:
		Input.action_press("run")
	else:
		Input.action_release("run")


func _reset_run() -> void:
	if _run_action_held:
		Input.action_release("run")
	_run_action_held = false
	if _run_btn and _run_btn.button_pressed:
		_run_btn.set_pressed_no_signal(false)


## X solo cancela si hay una habilidad en fase 2; fuera de eso no hace nada
## (evita castear el slot 3 sin querer).
func _on_cancel_pressed() -> void:
	var p := _get_player()
	if p == null:
		return
	var slot: Variant = p.get("aiming_slot")
	if slot == null or int(slot) < 0:
		return
	_tap_action("ability_3")


## Mantiene sincronizado el estado de la acción para el polling
## (`Input.is_action_pressed`) y emite el evento para quien usa `_input`
## (`Player._input`). Así funcionan tanto correr como habilidades/pausa.
func _emit_action(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _release_held_actions() -> void:
	for action in _held_actions.keys():
		_emit_action(String(action), false)
	_held_actions.clear()
	_reset_run()


func _reset_sticks() -> void:
	if _move_stick and _move_stick.has_method("reset_value"):
		_move_stick.call("reset_value")
	if _aim_stick and _aim_stick.has_method("reset_value"):
		_aim_stick.call("reset_value")


func _clear_virtual_state(target: Node) -> void:
	if not is_instance_valid(target):
		return
	if target.has_method("clear_virtual_move"):
		target.call("clear_virtual_move")
	var ic: Variant = target.get("input_component")
	if ic != null:
		if ic.has_method("clear_virtual_move"):
			ic.call("clear_virtual_move")
		if ic.has_method("clear_virtual_aim"):
			ic.call("clear_virtual_aim")


func _on_move_changed(value: Vector2) -> void:
	var p := _get_player()
	if p == null:
		return
	if p.has_method("set_virtual_move"):
		p.call("set_virtual_move", value)
		return
	var ic: Variant = p.get("input_component")
	if ic != null and ic.has_method("set_virtual_move"):
		ic.call("set_virtual_move", value)


func _on_aim_changed(value: Vector2) -> void:
	var p := _get_player()
	if p == null:
		return
	var ic: Variant = p.get("input_component")
	if ic != null and ic.has_method("set_virtual_aim"):
		ic.call("set_virtual_aim", value)


func _get_player() -> Node:
	if is_instance_valid(player):
		return player
	for p in PlayerLifecycleManager.get_all_players():
		if p.is_local_owner():
			player = p
			return p
	return null


# ── Tema ─────────────────────────────────────────────────────────────
## Los botones/joysticks siguen la paleta activa (device/light/lo que sea).
func _on_theme_arg(_arg: Variant = null) -> void:
	_apply_theme()


func _apply_theme() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null or not tm.has_method("get_palette"):
		return
	var pal: Dictionary = tm.get_palette()
	var selected: Color = pal.get("selected", Color(0, 1, 0, 1))
	var dim: Color = pal.get("dim", selected)
	var bg: Color = pal.get("bg", Color(0, 0, 0, 1))
	var font: Font = tm.get_font() if tm.has_method("get_font") else null

	var base: StyleBoxFlat = null
	if tm.has_method("make_box_style"):
		base = tm.make_box_style()
	var hover: StyleBoxFlat = base.duplicate() if base else null
	if hover:
		hover.bg_color = Color(selected.r, selected.g, selected.b, 0.12)
	var pressed: StyleBoxFlat = base.duplicate() if base else null
	if pressed:
		pressed.bg_color = Color(selected.r, selected.g, selected.b, 0.24)
	var disabled: StyleBoxFlat = base.duplicate() if base else null
	if disabled:
		disabled.bg_color = Color(bg.r, bg.g, bg.b, 0.35)
		disabled.border_color = Color(dim.r, dim.g, dim.b, 0.6)

	for b in [_run_btn, _interact_btn, _pause_btn, _score_btn, _emote_btn,
			_confirm_btn, _cancel_btn]:
		if b == null:
			continue
		if base:
			b.add_theme_stylebox_override("normal", base)
		if hover:
			b.add_theme_stylebox_override("hover", hover)
		if pressed:
			b.add_theme_stylebox_override("pressed", pressed)
		if disabled:
			b.add_theme_stylebox_override("disabled", disabled)
		b.add_theme_color_override("font_color", selected)
		b.add_theme_color_override("font_hover_color", selected)
		b.add_theme_color_override("font_pressed_color", selected)
		b.add_theme_color_override("font_disabled_color", dim)
		if font:
			b.add_theme_font_override("font", font)

	for stick in [_move_stick, _aim_stick]:
		if stick == null:
			continue
		stick.set("base_color", Color(selected.r, selected.g, selected.b, 0.10))
		stick.set("ring_color", Color(selected.r, selected.g, selected.b, 0.32))
		stick.set("knob_color", Color(selected.r, selected.g, selected.b, 0.42))


func _exit_tree() -> void:
	_release_held_actions()
	var tm := get_node_or_null("/root/ThemeManager")
	if tm:
		if tm.has_signal("theme_changed") and tm.theme_changed.is_connected(_on_theme_arg):
			tm.theme_changed.disconnect(_on_theme_arg)
		if tm.has_signal("palette_changed") and tm.palette_changed.is_connected(_on_theme_arg):
			tm.palette_changed.disconnect(_on_theme_arg)
