extends Control
## PlayMode — ONLINE / LAN — Deltarune, ONLINE oculto si no disponible.

const ALL_OPTIONS := ["LAN", "ONLINE"]
const ALL_HINTS := ["Partidas en red local", "Partidas por Internet (Steam)"]

@onready var _labels: Array[Label] = []
@onready var _soul: TextureRect = $SoulCursor
@onready var _hint: Label = $CenterContainer/DeltaruneBox/Margin/VBox/HintLabel

var _visible_options: Array[String] = []
var _visible_hints: Array[String] = []
var _index := 0
var _busy := false

func _ready() -> void:
	var am0 := get_node_or_null("/root/AudioManager")
	if am0 and am0.has_method("play_menu_drone") and am0.current_global_state != "menu_drone":
		am0.play_menu_drone()
	_rebuild_options()
	var vbox := $CenterContainer/DeltaruneBox/Margin/VBox/MenuList
	for c in vbox.get_children():
		if c is Label:
			_labels.append(c)
	# Sincronizar visibilidad con _visible_options
	for i in _labels.size():
		if i < _visible_options.size():
			_labels[i].visible = true
			_labels[i].text = _visible_options[i]
		else:
			_labels[i].visible = false
	_index = 0
	_highlight(_index)
	_position_soul(_index, true)
	grab_focus()

func _rebuild_options() -> void:
	var nm := get_node_or_null("/root/NetworkManager")
	var online_available := false
	if nm and nm.has_method("is_online_available"):
		online_available = nm.is_online_available()
	elif nm and nm.has_method("is_steam_ready"):
		online_available = nm.is_steam_ready()
	if online_available:
		_visible_options = ["LAN", "ONLINE"]
		_visible_hints = ["Partidas en red local", "Partidas por Internet (Steam)"]
	else:
		_visible_options = ["LAN"]
		_visible_hints = ["Partidas en red local (ONLINE no disponible)"]

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	var vp := get_viewport()
	if vp == null:
		return
	if event.is_action_pressed("menu_up"):
		_move(-1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		_move(1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_accept") or event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_Z):
		_confirm()
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		_go_back()
		vp.set_input_as_handled()

func _move(dir: int) -> void:
	var ni := clampi(_index + dir, 0, _visible_options.size() - 1)
	if ni == _index:
		return
	_index = ni
	_highlight(_index)
	_position_soul(_index, false)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)

func _highlight(idx: int) -> void:
	for j in _labels.size():
		var lbl: Label = _labels[j]
		if j < _visible_options.size():
			if j == idx:
				lbl.modulate = Color(0, 1, 0, 1)
				lbl.text = "    " + _visible_options[j]
			else:
				lbl.modulate = Color(0, 0.50196081, 0, 1)
				lbl.text = "" + _visible_options[j]
		else:
			lbl.visible = false
	if _hint and idx < _visible_hints.size():
		_hint.text = _visible_hints[idx]

func _position_soul(idx: int, instant: bool) -> void:
	if _soul == null or _labels.is_empty():
		return
	if idx < 0 or idx >= _labels.size():
		return
	var target: Label = _labels[idx]
	if not is_instance_valid(target) or not target.visible:
		return
	await get_tree().process_frame
	if not is_instance_valid(target):
		return
	var dest := target.global_position + Vector2(-28, (target.size.y - _soul.size.y) / 2.0) - global_position
	if instant:
		_soul.position = dest
	else:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_soul, "position", dest, 0.08)

func _confirm() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.SELECT)
	_busy = true
	var lbl: Label = _labels[_index] if _index < _labels.size() else null
	if lbl:
		var tw := create_tween()
		tw.tween_property(lbl, "modulate", Color(0.6, 0.6, 0.6, 1), 0.06)
		tw.tween_property(lbl, "modulate", Color(0, 1, 0, 1), 0.06)
		await tw.finished
	_busy = false
	var opt: String = _visible_options[_index] if _index < _visible_options.size() else ""
	if opt == "ONLINE":
		_open_browser("ONLINE")
	elif opt == "LAN":
		_open_browser("LAN")
	else:
		_go_back()

func _go_back() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.SELECT)
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")

func _open_browser(mode: String) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	var nm := get_node_or_null("/root/NetworkManager")
	if sm:
		sm.network_mode = 1 if mode == "ONLINE" else 0
		if "online_provider" in sm and mode == "ONLINE":
			sm.online_provider = "steam"
		sm.save_settings()
	if nm:
		if mode == "ONLINE":
			var ok := false
			if nm.has_method("initialize_online"):
				var prov := "steam"
				if sm and "online_provider" in sm:
					prov = sm.online_provider
				ok = nm.initialize_online(prov)
			elif nm.has_method("initialize_steam"):
				ok = nm.initialize_steam()
			if not ok:
				var am2 := get_node_or_null("/root/AudioManager")
				if am2 and am2.has_method("play_sfx_ui"):
					am2.play_sfx_ui(SfxId.ERROR)
				if _hint:
					_hint.text = "ONLINE no disponible — usa LAN"
				return
		else:
			nm.set_lan_mode()
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/ServerBrowser.tscn")
