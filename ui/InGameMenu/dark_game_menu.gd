extends Control
## Menú de pausa in-game estilo "Dark World" de Deltarune, adaptado para
## un juego asimétrico online (Killer/Survivor).
##
## Toda la UI vive en DarkGameMenu.tscn (editable en el editor: tamaños,
## posiciones, colores, márgenes, mouse_filter y focus_mode). Este script
## SOLO contiene lógica: navegación, mostrar/ocultar paneles, intercambiar
## los estilos definidos en la escena y actualizar valores de texto.
##
## Navegación (teclado/mando, sin ratón):
##   - En la barra de pestañas: ←→ mueven el cursor, Z/Enter (menu_accept)
##     entra a la pestaña, X/Esc (menu_cancel) cierra el menú.
##   - Dentro de una pestaña: ↑↓ mueven la fila, ←→ ajustan el valor,
##     Z/Enter confirma (p. ej. Restablecer), X/Esc vuelve a la barra.
##   - El menú usa _input y consume los eventos: ningún control GUI puede
##     robar las teclas, aunque tenga el foco.
##
## NOTA: los datos de stats se piden al servidor al abrir la pestaña STATS
## (MatchStatsService.request_my_stats → ClientRelay._rpc_my_stats).

const NAV_REPEAT_MS := 220
const TAB_IDS := ["stats", "audio", "video", "controles", "salir"]

# Filas interactivas por pestaña (ids lógicos, en orden de navegación vertical).
const PANEL_ROWS := {
	"audio": ["music", "sfx"],
	"video": ["brightness", "display", "vhs"],
	"controles": ["deadzone", "reset"],
}

# Nombre de nodo de cada fila (para resaltado / búsqueda en la escena).
const ROW_NODE_NAMES := {
	"music": "MusicRow",
	"sfx": "SfxRow",
	"brightness": "BrightnessRow",
	"display": "DisplayRow",
	"vhs": "VhsRow",
	"deadzone": "DeadzoneRow",
	"reset": "ResetRow",
}

const HINT_TABS := "←→ mover pestaña   ·   Z/Enter entrar   ·   X/Esc cerrar"
const HINT_PANEL := "↑↓ fila   ·   ←→ ajustar   ·   Z/Enter confirmar   ·   X/Esc volver"
const HINT_EXIT := "←→ elegir   ·   Z/Enter confirmar"

const COLOR_GOLD := Color(1, 0.82, 0.3, 1)

# ── Nodos: barra de pestañas ──────────────────────────────────────────
@onready var overlay: ColorRect = $Overlay
@onready var center: CenterContainer = $Root/VBox/TabBarWrap/Center
@onready var tab_nodes: Array[Panel] = [
	$Root/VBox/TabBarWrap/Center/TabBar/TabStats,
	$Root/VBox/TabBarWrap/Center/TabBar/TabAudio,
	$Root/VBox/TabBarWrap/Center/TabBar/TabVideo,
	$Root/VBox/TabBarWrap/Center/TabBar/TabControles,
	$Root/VBox/TabBarWrap/Center/TabBar/TabSalir,
]

# ── Nodos: panel de contenido ─────────────────────────────────────────
@onready var content_panel: PanelContainer = $Root/VBox/ContentPanel
@onready var content_nodes: Dictionary = {
	"stats": $Root/VBox/ContentPanel/ContentMargin/StatsContent,
	"audio": $Root/VBox/ContentPanel/ContentMargin/AudioContent,
	"video": $Root/VBox/ContentPanel/ContentMargin/VideoContent,
	"controles": $Root/VBox/ContentPanel/ContentMargin/ControlesContent,
	"salir": $Root/VBox/ContentPanel/ContentMargin/SalirContent,
}
@onready var hint_center: CenterContainer = $HintWrap/HintCenter
@onready var hint_label: Label = $HintWrap/HintCenter/HintBox/HintMargin/Hint

# ── Nodos: contenido de Stats ─────────────────────────────────────────
@onready var stats_row_kills: HBoxContainer = $Root/VBox/ContentPanel/ContentMargin/StatsContent/RowKills
@onready var stats_row_damage_dealt: HBoxContainer = $Root/VBox/ContentPanel/ContentMargin/StatsContent/RowDamageDealt
@onready var stats_row_stuns_received: HBoxContainer = $Root/VBox/ContentPanel/ContentMargin/StatsContent/RowStunsReceived
@onready var stats_row_danger: HBoxContainer = $Root/VBox/ContentPanel/ContentMargin/StatsContent/RowDanger
@onready var stats_row_damage_taken: HBoxContainer = $Root/VBox/ContentPanel/ContentMargin/StatsContent/RowDamageTaken
@onready var stats_row_stuns_applied: HBoxContainer = $Root/VBox/ContentPanel/ContentMargin/StatsContent/RowStunsApplied
@onready var stats_title: Label = $Root/VBox/ContentPanel/ContentMargin/StatsContent/Title

# ── Nodos: contenido de Audio ──────────────────────────────────────────
@onready var music_value: Label = $Root/VBox/ContentPanel/ContentMargin/AudioContent/MusicRow/Value
@onready var sfx_value: Label = $Root/VBox/ContentPanel/ContentMargin/AudioContent/SfxRow/Value

# ── Nodos: contenido de Video ─────────────────────────────────────────
@onready var brightness_value: Label = $Root/VBox/ContentPanel/ContentMargin/VideoContent/BrightnessRow/Value
@onready var display_value: Label = $Root/VBox/ContentPanel/ContentMargin/VideoContent/DisplayRow/Value
@onready var vhs_value: Label = $Root/VBox/ContentPanel/ContentMargin/VideoContent/VhsRow/Value

# ── Nodos: contenido de Controles ─────────────────────────────────────
@onready var deadzone_value: Label = $Root/VBox/ContentPanel/ContentMargin/ControlesContent/DeadzoneRow/Value

# ── Nodos: contenido de Salir ──────────────────────────────────────────
@onready var exit_opt_si: Panel = $Root/VBox/ContentPanel/ContentMargin/SalirContent/OptionsRow/OptSi
@onready var exit_opt_no: Panel = $Root/VBox/ContentPanel/ContentMargin/SalirContent/OptionsRow/OptNo

# ── Estado ─────────────────────────────────────────────────────────────
var _is_open := false
var _in_tabs := true
var _tab_idx := 0
var _row_idx := 0
var _confirm_idx := 1  # arranca en "NO" por seguridad
var _nav_last := {}
var _tabbar_tween: Tween
var _cached_stats: Dictionary = {}
var _style_normal: StyleBox = null
var _style_highlighted: StyleBox = null


func _ready() -> void:
	add_to_group(GroupNames.GAME_MENU)
	_cache_styles()
	_close(true)


func _exit_tree() -> void:
	var relay := GameServiceLocator.get_client_relay()
	if relay and relay.has_signal("stats_received") and relay.stats_received.is_connected(_on_stats_received):
		relay.stats_received.disconnect(_on_stats_received)


## Copia los estilos definidos como sub-recursos en la escena para
## intercambiarlos al resaltar pestañas y opciones de salida.
func _cache_styles() -> void:
	var sb_h := tab_nodes[0].get_theme_stylebox("panel") as StyleBoxFlat
	if sb_h:
		_style_highlighted = sb_h.duplicate()
	var sb_n := tab_nodes[1].get_theme_stylebox("panel") as StyleBoxFlat
	if sb_n:
		_style_normal = sb_n.duplicate()


func is_open() -> bool:
	return _is_open


# ── Input ────────────────────────────────────────────────────────────
## _input en lugar de _unhandled_input: el menú recibe las teclas ANTES que
## el GUI y las consume, así ningún control (slider, chat, etc.) las roba.
func _input(event: InputEvent) -> void:
	var vp := get_viewport()
	if vp == null:
		return

	if not _is_open:
		if event.is_action_pressed("pause"):
			_open()
			vp.set_input_as_handled()
		return

	if _handle_action(event):
		vp.set_input_as_handled()


func _handle_action(event: InputEvent) -> bool:
	if _in_tabs:
		return _handle_tabbar_input(event)
	if TAB_IDS[_tab_idx] == "salir":
		return _handle_exit_confirm_input(event)
	return _handle_panel_input(event)


## Aceptar: Enter/Space/A (menu_accept) o la tecla Z (estilo menú principal).
func _is_accept(event: InputEvent) -> bool:
	if event.is_action_pressed("menu_accept"):
		return true
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Z:
		return true
	return false


## Cancelar/volver: Esc (menu_cancel/pause) o la tecla X.
func _is_cancel(event: InputEvent) -> bool:
	if event.is_action_pressed("menu_cancel") or event.is_action_pressed("pause"):
		return true
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X:
		return true
	return false


func _handle_tabbar_input(event: InputEvent) -> bool:
	if event.is_action_pressed("menu_left"):
		if not _nav_throttle("left"):
			return false
		_move_tab(-1)
		return true
	if event.is_action_pressed("menu_right"):
		if not _nav_throttle("right"):
			return false
		_move_tab(1)
		return true
	if _is_accept(event):
		if not _nav_throttle("accept"):
			return false
		_enter_tab()
		return true
	if _is_cancel(event):
		if not _nav_throttle("cancel"):
			return false
		_close()
		return true
	return false


func _handle_panel_input(event: InputEvent) -> bool:
	if event.is_action_pressed("menu_up"):
		if not _nav_throttle("up"):
			return false
		_move_row(-1)
		return true
	if event.is_action_pressed("menu_down"):
		if not _nav_throttle("down"):
			return false
		_move_row(1)
		return true
	if event.is_action_pressed("menu_left"):
		if not _nav_throttle("left"):
			return false
		_adjust_row(-1)
		return true
	if event.is_action_pressed("menu_right"):
		if not _nav_throttle("right"):
			return false
		_adjust_row(1)
		return true
	if _is_accept(event):
		if not _nav_throttle("accept"):
			return false
		_confirm_row()
		return true
	if _is_cancel(event):
		if not _nav_throttle("cancel"):
			return false
		_exit_tab()
		return true
	return false


func _handle_exit_confirm_input(event: InputEvent) -> bool:
	if event.is_action_pressed("menu_left") or event.is_action_pressed("menu_right"):
		if not _nav_throttle("confirm_move"):
			return false
		_confirm_idx = 1 - _confirm_idx
		_refresh_exit_confirm()
		AudioManager.play_sfx_ui(SfxId.MENU_MOVE)
		return true
	if _is_accept(event):
		if not _nav_throttle("accept"):
			return false
		if _confirm_idx == 0:
			_on_exit_confirmed()
		else:
			_exit_tab()
		return true
	if _is_cancel(event):
		if not _nav_throttle("cancel"):
			return false
		_exit_tab()
		return true
	return false


func _nav_throttle(key: String) -> bool:
	var now := Time.get_ticks_msec()
	if _nav_last.has(key) and now - _nav_last[key] < NAV_REPEAT_MS:
		return false
	_nav_last[key] = now
	return true


# ── Apertura / cierre (con animación de entrada y salida) ────────────

func _open() -> void:
	_is_open = true
	_in_tabs = true
	_tab_idx = 0
	overlay.visible = true
	center.visible = true
	hint_center.visible = true
	content_panel.visible = false
	_sync_from_settings()
	_refresh_tab_highlight()
	_update_hint()
	_animate_tabbar_in()
	AudioManager.play_sfx_ui(SfxId.SELECT)


func _close(instant := false) -> void:
	_is_open = false
	if instant:
		_hide_all()
		return
	AudioManager.play_sfx_ui(SfxId.SELECT)
	_animate_tabbar_out()


func _animate_tabbar_in() -> void:
	if _tabbar_tween and _tabbar_tween.is_running():
		_tabbar_tween.kill()
	center.position = Vector2(0, -120)
	hint_center.position = Vector2(0, 60)
	_tabbar_tween = create_tween()
	_tabbar_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tabbar_tween.tween_property(center, "position", Vector2.ZERO, 0.25)
	_tabbar_tween.parallel().tween_property(hint_center, "position", Vector2.ZERO, 0.25)


func _animate_tabbar_out() -> void:
	if _tabbar_tween and _tabbar_tween.is_running():
		_tabbar_tween.kill()
	_tabbar_tween = create_tween()
	_tabbar_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tabbar_tween.tween_property(center, "position", Vector2(0, -120), 0.25)
	_tabbar_tween.parallel().tween_property(hint_center, "position", Vector2(0, 60), 0.25)
	_tabbar_tween.tween_callback(_hide_all)


func _hide_all() -> void:
	overlay.visible = false
	content_panel.visible = false
	_hide_all_content()
	center.visible = false
	hint_center.visible = false


# ── Navegación entre pestañas ────────────────────────────────────────

func _move_tab(dir: int) -> void:
	var new_idx: int = clampi(_tab_idx + dir, 0, TAB_IDS.size() - 1)
	if new_idx == _tab_idx:
		return
	_tab_idx = new_idx
	_refresh_tab_highlight()
	AudioManager.play_sfx_ui(SfxId.MENU_MOVE)


func _refresh_tab_highlight() -> void:
	for i in tab_nodes.size():
		_set_panel_highlighted(tab_nodes[i], i == _tab_idx)


func _set_panel_highlighted(panel: Panel, highlighted: bool) -> void:
	var style := _style_highlighted if highlighted else _style_normal
	if style:
		panel.add_theme_stylebox_override("panel", style)


func _enter_tab() -> void:
	_in_tabs = false
	_row_idx = 0
	content_panel.visible = true
	_show_tab_content(TAB_IDS[_tab_idx])
	_update_hint()
	AudioManager.play_sfx_ui(SfxId.SELECT)


func _exit_tab() -> void:
	_in_tabs = true
	content_panel.visible = false
	_hide_all_content()
	_update_hint()
	AudioManager.play_sfx_ui(SfxId.SELECT)


# ── Contenido por pestaña ────────────────────────────────────────────

func _hide_all_content() -> void:
	for node in content_nodes.values():
		if is_instance_valid(node):
			node.visible = false


func _show_tab_content(tab_id: String) -> void:
	_hide_all_content()
	var node: Control = content_nodes.get(tab_id)
	if node == null:
		return
	node.visible = true

	match tab_id:
		"stats":
			_refresh_stats_content()
			_request_local_stats()
		"salir":
			_confirm_idx = 1
			_refresh_exit_confirm()

	_refresh_panel_highlight()


# ── Navegación por filas ─────────────────────────────────────────────

func _current_tab() -> String:
	return TAB_IDS[_tab_idx]


func _current_row_count() -> int:
	var rows: Array = PANEL_ROWS.get(_current_tab(), [])
	return rows.size()


func _move_row(dir: int) -> void:
	var count := _current_row_count()
	if count <= 0:
		return
	var new_idx: int = clampi(_row_idx + dir, 0, count - 1)
	if new_idx == _row_idx:
		return
	_row_idx = new_idx
	_refresh_panel_highlight()
	AudioManager.play_sfx_ui(SfxId.MENU_MOVE)


func _adjust_row(dir: int) -> void:
	var row_id := _current_row_id()
	if row_id == "":
		return
	match row_id:
		"music":
			_set_music(clampf(SettingsManager.music_volume + dir * 0.05, 0.0, 1.0))
		"sfx":
			_set_sfx(clampf(SettingsManager.sfx_volume + dir * 0.05, 0.0, 1.0))
		"brightness":
			_set_brightness(clampf(SettingsManager.brightness + dir * 0.1, 0.5, 1.5))
		"display":
			_toggle_display()
		"vhs":
			_toggle_vhs()
		"deadzone":
			_set_deadzone(clampf(InputService.stick_deadzone + dir * 0.05, 0.05, 0.5))
		_:
			return
	AudioManager.play_sfx_ui(SfxId.MENU_MOVE)


func _confirm_row() -> void:
	var row_id := _current_row_id()
	if row_id == "":
		return
	match row_id:
		"display":
			_toggle_display()
		"vhs":
			_toggle_vhs()
		"reset":
			_reset_controls()
		_:
			AudioManager.play_sfx_ui(SfxId.SELECT)


func _current_row_id() -> String:
	var rows: Array = PANEL_ROWS.get(_current_tab(), [])
	if _row_idx < 0 or _row_idx >= rows.size():
		return ""
	return str(rows[_row_idx])


func _refresh_panel_highlight() -> void:
	for tab_id in PANEL_ROWS:
		var content: Control = content_nodes.get(tab_id)
		if content == null:
			continue
		var is_current: bool = (not _in_tabs) and _current_tab() == tab_id
		for i in PANEL_ROWS[tab_id].size():
			var row: Control = content.get_node_or_null(ROW_NODE_NAMES[PANEL_ROWS[tab_id][i]])
			if row == null:
				continue
			_set_row_highlighted(row, is_current and i == _row_idx)


func _set_row_highlighted(row: Control, selected: bool) -> void:
	for c in row.get_children():
		if c is Label:
			c.modulate = COLOR_GOLD if selected else Color(1, 1, 1, 1)


# ── Sincronización y persistencia de ajustes ─────────────────────────

func _sync_from_settings() -> void:
	_update_value_labels()


func _update_value_labels() -> void:
	music_value.text = _slider_label(SettingsManager.music_volume, 0.0, 1.0, true)
	sfx_value.text = _slider_label(SettingsManager.sfx_volume, 0.0, 1.0, true)
	brightness_value.text = _slider_label(SettingsManager.brightness, 0.5, 1.5, true)
	display_value.text = "Completo" if SettingsManager.display_mode == 3 else "Ventana"
	vhs_value.text = "[X]" if SettingsManager.vhs_enabled else "[ ]"
	deadzone_value.text = _slider_label(InputService.stick_deadzone, 0.05, 0.5, false)


## Etiqueta de valor al estilo del menú principal: "< IIII...... > 40%".
func _slider_label(value: float, min_v: float, max_v: float, as_percent: bool) -> String:
	var t := clampf((value - min_v) / (max_v - min_v), 0.0, 1.0)
	var pct := int(round(t * 10.0))
	var bar := ""
	for i in 10:
		bar += "I" if i < pct else "."
	if as_percent:
		return "< %s > %d%%" % [bar, int(round(value * 100.0))]
	return "< %s > %.2f" % [bar, value]


func _set_music(v: float) -> void:
	SettingsManager.music_volume = v
	music_value.text = _slider_label(v, 0.0, 1.0, true)
	SettingsManager.save_settings()


func _set_sfx(v: float) -> void:
	SettingsManager.sfx_volume = v
	sfx_value.text = _slider_label(v, 0.0, 1.0, true)
	SettingsManager.save_settings()


func _set_brightness(v: float) -> void:
	SettingsManager.brightness = v
	brightness_value.text = _slider_label(v, 0.5, 1.5, true)
	SettingsManager.save_settings()


func _set_deadzone(v: float) -> void:
	InputService.set_stick_deadzone(v)
	deadzone_value.text = _slider_label(v, 0.05, 0.5, false)


func _toggle_display() -> void:
	SettingsManager.display_mode = 0 if SettingsManager.display_mode == 3 else 3
	display_value.text = "Completo" if SettingsManager.display_mode == 3 else "Ventana"
	SettingsManager.save_settings()


func _toggle_vhs() -> void:
	SettingsManager.vhs_enabled = not SettingsManager.vhs_enabled
	vhs_value.text = "[X]" if SettingsManager.vhs_enabled else "[ ]"
	SettingsManager.save_settings()


func _reset_controls() -> void:
	InputService.reset_all()
	deadzone_value.text = _slider_label(InputService.stick_deadzone, 0.05, 0.5, false)
	AudioManager.play_sfx_ui(SfxId.SELECT)


# ── Hint de controles ────────────────────────────────────────────────

func _update_hint() -> void:
	if not _is_open:
		hint_label.text = HINT_TABS
		return
	if _in_tabs:
		hint_label.text = HINT_TABS
	elif _current_tab() == "salir":
		hint_label.text = HINT_EXIT
	else:
		hint_label.text = HINT_PANEL


# ── Stats ────────────────────────────────────────────────────────────

func _refresh_stats_content() -> void:
	var role := _get_local_role()
	stats_title.text = "STATS — %s" % ("KILLER" if role == "killer" else "SURVIVOR")

	var is_killer := role == "killer"
	stats_row_kills.visible = is_killer
	stats_row_damage_dealt.visible = is_killer
	stats_row_stuns_received.visible = is_killer
	stats_row_danger.visible = not is_killer
	stats_row_damage_taken.visible = not is_killer
	stats_row_stuns_applied.visible = not is_killer

	var snapshot := _get_local_snapshot()
	if is_killer:
		_set_row_value(stats_row_kills, str(snapshot.get("kills", 0)))
		_set_row_value(stats_row_damage_dealt, str(snapshot.get("damage_dealt", 0)))
		_set_row_value(stats_row_stuns_received, str(snapshot.get("stuns_received", 0)))
	else:
		_set_row_value(stats_row_danger, "%.1fs" % float(snapshot.get("time_in_danger", 0.0)))
		_set_row_value(stats_row_damage_taken, str(snapshot.get("damage_taken", 0)))
		_set_row_value(stats_row_stuns_applied, str(snapshot.get("stuns_applied", 0)))


func _set_row_value(row: HBoxContainer, text: String) -> void:
	var value_lbl := row.get_node_or_null("Value") as Label
	if value_lbl:
		value_lbl.text = text


func _get_local_role() -> String:
	var my_id := multiplayer.get_unique_id()
	var player := PlayerRegistry.get_player(my_id)
	if player and player.character_data and "team" in player.character_data:
		return str(player.character_data.team)
	var ldata: Dictionary = LobbyManager.players.get(my_id, {})
	return str(ldata.get("assigned_role", "survivor"))


func _request_local_stats() -> void:
	var mss: Node = GameServiceLocator.match_stats
	if mss and mss.has_method("request_my_stats"):
		mss.rpc("request_my_stats")
	var relay := GameServiceLocator.get_client_relay()
	if relay and relay.has_signal("stats_received") and not relay.stats_received.is_connected(_on_stats_received):
		relay.stats_received.connect(_on_stats_received)


func _on_stats_received(stats: Dictionary) -> void:
	_cached_stats = stats
	if _is_open and not _in_tabs and _current_tab() == "stats":
		_refresh_stats_content()


func _get_local_snapshot() -> Dictionary:
	if not _cached_stats.is_empty():
		return _cached_stats
	var relay := GameServiceLocator.get_client_relay()
	if relay and relay.has_method("get_my_stats"):
		return relay.get_my_stats()
	return {}


# ── Pestaña Salir (con confirmación) ─────────────────────────────────

func _refresh_exit_confirm() -> void:
	_set_panel_highlighted(exit_opt_si, _confirm_idx == 0)
	_set_panel_highlighted(exit_opt_no, _confirm_idx == 1)


func _on_exit_confirmed() -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	MatchCoordinator.reset_to_menu()
