# res://ui/Hub/BoardPanel.gd
# Panel del tablero del hub: por ahora permite elegir el mapa (host) e iniciar.
# El sistema de listo/votos queda para la siguiente iteración.
extends Control

signal start_requested
signal closed
signal map_selected(map_id: String)

@onready var info_label: Label = $Center/Panel/Margin/VBox/Info
@onready var status_label: Label = $Center/Panel/Margin/VBox/StatusLabel
@onready var prev_map_btn: Button = $Center/Panel/Margin/VBox/MapRow/PrevMapBtn
@onready var map_label: Label = $Center/Panel/Margin/VBox/MapRow/MapLabel
@onready var next_map_btn: Button = $Center/Panel/Margin/VBox/MapRow/NextMapBtn
@onready var start_btn: Button = $Center/Panel/Margin/VBox/StartBtn
@onready var close_btn: Button = $Center/Panel/Margin/VBox/CloseBtn

var _maps: Array = []
var _map_index := 0
var _can_edit := false


func _ready() -> void:
	add_to_group("hub_ui")
	visible = false
	prev_map_btn.pressed.connect(_on_prev_map)
	next_map_btn.pressed.connect(_on_next_map)
	start_btn.pressed.connect(_on_start_pressed)
	close_btn.pressed.connect(close_panel)


func open_panel(can_manage: bool = true) -> void:
	_reload_maps()
	info_label.text = "ELEGÍ EL MAPA Y INICIÁ LA PARTIDA."
	set_status("")
	set_can_start(can_manage)
	visible = true
	refresh_map_info()
	if can_manage:
		start_btn.grab_focus()
	else:
		close_btn.grab_focus()


func close_panel() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func set_can_start(can_manage: bool) -> void:
	start_btn.disabled = not can_manage
	start_btn.text = "INICIAR PARTIDA" if can_manage else "ESPERANDO AL HOST"
	_can_edit = can_manage
	_update_map_buttons()


func set_status(text: String) -> void:
	status_label.text = text
	status_label.visible = text != ""


func refresh_map_info() -> void:
	var map_id := LobbyManager.selected_map
	var map_name := map_id
	if map_id != "" and MapRegistry.has_map(map_id):
		var map_data := MapRegistry.get_map(map_id)
		if map_data:
			map_name = map_data.display_name
	if map_name == "":
		map_name = "SIN MAPA"
	map_label.text = "MAPA: " + map_name
	_update_map_index()
	_update_map_buttons()


func _reload_maps() -> void:
	_maps = MapRegistry.get_all()
	_maps.sort_custom(func(a, b) -> bool:
		return str(a.display_name).naturalnocasecmp_to(str(b.display_name)) < 0
	)
	_update_map_index()


func _update_map_index() -> void:
	_map_index = 0
	var current := LobbyManager.selected_map
	for i in _maps.size():
		if str(_maps[i].id) == current:
			_map_index = i
			return


func _update_map_buttons() -> void:
	var enabled := _can_edit and _maps.size() > 1
	prev_map_btn.disabled = not enabled
	next_map_btn.disabled = not enabled


func _on_prev_map() -> void:
	_cycle_map(-1)


func _on_next_map() -> void:
	_cycle_map(1)


func _cycle_map(direction: int) -> void:
	if not _can_edit or _maps.size() <= 1:
		return
	_map_index = (_map_index + direction + _maps.size()) % _maps.size()
	var map_data = _maps[_map_index]
	map_selected.emit(str(map_data.id))


func _on_start_pressed() -> void:
	if start_btn.disabled:
		return
	start_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu_cancel") \
			or event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()
		close_panel()
