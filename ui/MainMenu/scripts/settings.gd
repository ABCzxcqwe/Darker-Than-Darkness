extends Control

##  Settings lateral — pestañas izquierda General/Audio/Video/Controles/Volver
## Derecha lista única scroll, teclado-only Z/X/C, soul rojo, #008000/#00FF00

const TABS := ["GENERAL", "AUDIO", "VIDEO", "CONTROLES", "VOLVER"]
const TAB_HINTS := ["Nombre, idioma y tema", "Música y efectos", "Brillo, pantalla y VHS", "Zona muerta y restablecer", "Volver al menú"]

var _tab_idx := 0
var _content_idx := 0
var _in_tabs := true
var _busy := false
var _soul_tween: Tween

# Definición de filas por pestaña: cada fila {label, type, ...}
var _tab_rows := {
	"GENERAL": [
		{"label": "IDIOMA", "type": "option", "options": ["Español [Bloqueado]"], "value": 0},
		{"label": "NOMBRE JUGADOR", "type": "input", "value": ""},
		{"label": "PROVEEDOR ONLINE", "type": "option", "options": ["LAN"], "value": 0},
		{"label": "TEMA", "type": "theme_option", "value": 0, "theme_ids": PackedStringArray(["device"])},
	],
	"AUDIO": [
		{"label": "MUSICA", "type": "slider", "min": 0.0, "max": 1.0, "step": 0.05, "value": 1.0},
		{"label": "SFX", "type": "slider", "min": 0.0, "max": 1.0, "step": 0.05, "value": 1.0},
	],
	"VIDEO": [
		{"label": "BRILLO", "type": "slider", "min": 0.5, "max": 1.5, "step": 0.1, "value": 1.0},
		{"label": "PANTALLA", "type": "option", "options": ["Ventana", "Completo"], "value": 0},
		{"label": "VHS", "type": "check", "value": true},
	],
	"CONTROLES": [
		{"label": "DEADZONE", "type": "slider", "min": 0.05, "max": 0.5, "step": 0.05, "value": 0.2},
		{"label": "RESTABLECER", "type": "button"},
	],
}

@onready var _soul: TextureRect = $SoulCursor
@onready var _left_labels: Array[Label] = []
@onready var _right_title: Label = $RightPanel/Margin/RightVBox/RightTitle
@onready var _content_list: VBoxContainer = $RightPanel/Margin/RightVBox/Scroll/Content
@onready var _hint: Label = $RightPanel/Margin/RightVBox/Hint
@onready var _scroll: ScrollContainer = $RightPanel/Margin/RightVBox/Scroll

func _ready() -> void:
	_setup_audio()
	
	var tabs_vbox := $LeftPanel/Margin/LeftVBox/Tabs
	for c in tabs_vbox.get_children():
		if c is Label:
			_left_labels.append(c)

	_sync_from_settings()
	_build_content(_tab_idx)
	_highlight_tabs()
	_position_soul_tabs(_tab_idx, true)
	_apply_theme()

	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed"):
		if not tm.theme_changed.is_connected(_on_theme_changed):
			tm.theme_changed.connect(_on_theme_changed)

	grab_focus()

func _exit_tree() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm and tm.has_signal("theme_changed") and tm.theme_changed.is_connected(_on_theme_changed):
		tm.theme_changed.disconnect(_on_theme_changed)

func _setup_audio() -> void:
	var am0 := get_node_or_null("/root/AudioManager")
	if am0 and am0.has_method("play_menu_drone"):
		if am0.get("current_global_state") != "menu_drone":
			am0.play_menu_drone()

func _on_theme_changed(_id: String) -> void:
	_apply_theme()
	_sync_from_settings()
	if TABS[_tab_idx] == "GENERAL":
		_build_content(_tab_idx)
		_highlight_content()

func _apply_theme() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	if tm == null:
		return

	var pal: Dictionary = tm.get_palette() if tm.has_method("get_palette") else {}
	var bg_node := get_node_or_null("Background")
	if bg_node and tm.has_method("apply_to_background"):
		tm.apply_to_background(bg_node)

	var left_panel := get_node_or_null("LeftPanel") as PanelContainer
	var right_panel := get_node_or_null("RightPanel") as PanelContainer
	if tm.has_method("make_box_style"):
		var box: StyleBoxFlat = tm.make_box_style()
		if left_panel and box:
			left_panel.add_theme_stylebox_override("panel", box)
		if right_panel and box:
			right_panel.add_theme_stylebox_override("panel", box.duplicate())

	var title_left := get_node_or_null("LeftPanel/Margin/LeftVBox/Title") as Label
	var title_right := get_node_or_null("RightPanel/Margin/RightVBox/RightTitle") as Label
	var sep1 := get_node_or_null("LeftPanel/Margin/LeftVBox/Separator") as ColorRect
	var sep2 := get_node_or_null("RightPanel/Margin/RightVBox/Separator2") as ColorRect
	var footer := get_node_or_null("Footer") as Label

	if title_left:
		title_left.add_theme_color_override("font_color", pal.get("title", Color(0, 1, 0, 1)))
		if tm.has_method("get_font"):
			var tf: FontFile = tm.get_font()
			if tf:
				title_left.add_theme_font_override("font", tf)
	if title_right:
		title_right.add_theme_color_override("font_color", pal.get("title", Color(0, 1, 0, 1)))
		if tm.has_method("get_font"):
			var tf2: FontFile = tm.get_font()
			if tf2:
				title_right.add_theme_font_override("font", tf2)
	if sep1:
		sep1.color = pal.get("separator", pal.get("border", Color(0, 0.5, 0, 1)))
	if sep2:
		sep2.color = pal.get("separator", pal.get("border", Color(0, 0.5, 0, 1)))
	if footer:
		footer.add_theme_color_override("font_color", pal.get("dim", Color(1,1,1,1)))
	if _hint:
		_hint.add_theme_color_override("font_color", pal.get("hint", Color(0,1,0,1)))
	if _right_title:
		_right_title.add_theme_color_override("font_color", pal.get("title", Color(0,1,0,1)))

	if tm.has_method("get_soul_texture") and _soul:
		var st: Texture2D = tm.get_soul_texture()
		if st:
			_soul.texture = st

func _sync_from_settings() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	var tm := get_node_or_null("/root/ThemeManager")
	var isrv := get_node_or_null("/root/InputService")

	if sm:
		_tab_rows["GENERAL"][0]["value"] = 0
		_tab_rows["GENERAL"][1]["value"] = sm.get("player_name") if "player_name" in sm else ""
		_tab_rows["AUDIO"][0]["value"] = sm.get("music_volume") if "music_volume" in sm else 1.0
		_tab_rows["AUDIO"][1]["value"] = sm.get("sfx_volume") if "sfx_volume" in sm else 1.0
		_tab_rows["VIDEO"][0]["value"] = sm.get("brightness") if "brightness" in sm else 1.0
		_tab_rows["VIDEO"][1]["value"] = 1 if sm.get("display_mode") == 3 else 0
		_tab_rows["VIDEO"][2]["value"] = sm.get("vhs_enabled") if "vhs_enabled" in sm else true
		var nm := get_node_or_null("/root/NetworkManager")
		var online_avail := false
		if nm and nm.has_method("is_online_available"):
			online_avail = nm.is_online_available()
		elif nm and nm.has_method("is_steam_ready"):
			online_avail = nm.is_steam_ready()
		if online_avail:
			_tab_rows["GENERAL"][2]["options"] = ["LAN", "ONLINE"]
			_tab_rows["GENERAL"][2]["value"] = 1 if sm.get("network_mode") == 1 else 0
		else:
			_tab_rows["GENERAL"][2]["options"] = ["LAN", "ONLINE — No disponible"]
			_tab_rows["GENERAL"][2]["value"] = 0

		if tm and tm.has_method("list_all_ids"):
			var all_ids: PackedStringArray = tm.list_all_ids()
			var theme_row: Dictionary = _tab_rows["GENERAL"][3]
			theme_row["theme_ids"] = all_ids

			var opts: Array = []
			for tid in all_ids:
				var label: String = tid.to_upper()
				if tm.has_method("get_theme"):
					var th = tm.get_theme(str(tid))
					if th is Resource and "label" in th and str(th.label) != "":
						label = str(th.label)
					elif th is Dictionary:
						label = str(th.get("label", label))

				var is_unlocked: bool = sm.has_method("is_theme_unlocked") and sm.is_theme_unlocked(str(tid))
				if not is_unlocked:
					label += " [BLOQUEADO]"
				opts.append(label)

			theme_row["options"] = opts
			var cur_id: String = str(sm.get("menu_theme")).to_lower() if "menu_theme" in sm else "device"
			if cur_id == "green_drone":
				cur_id = "device"

			var cur_idx: int = 0
			for i in all_ids.size():
				if str(all_ids[i]).to_lower() == cur_id:
					cur_idx = i
					break
			theme_row["value"] = cur_idx

	if isrv and "stick_deadzone" in isrv:
		_tab_rows["CONTROLES"][0]["value"] = isrv.stick_deadzone

func _is_lineedit_editing() -> bool:
	if _in_tabs or _content_list.get_child_count() <= _content_idx:
		return false
	var crow := _content_list.get_child(_content_idx) as HBoxContainer
	if crow == null or crow.get_child_count() <= 1:
		return false
	var v := crow.get_child(1)
	return v is LineEdit and v.has_focus()

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return

	var vp := get_viewport()
	if vp == null:
		return

	# Si LineEdit está en edición, bloquear navegación y dejar tipear
	if _is_lineedit_editing() and event is InputEventKey and event.pressed:
		# permitir tipear caracteres imprimibles y navegación de caret
		if event.unicode != 0 and event.keycode != KEY_ENTER and event.keycode != KEY_KP_ENTER and event.keycode != KEY_ESCAPE:
			return
		# mientras edita, ↑↓←→ no deben mover el soul sino caret; bloquear
		if event.is_action_pressed("menu_up") or event.is_action_pressed("menu_down") or event.is_action_pressed("menu_left") or event.is_action_pressed("menu_right"):
			return
		# Esc/X mientras edita: solo salir de edición, no navegar ni cancelar pestaña
		if event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
			var crow_esc := _content_list.get_child(_content_idx) as HBoxContainer
			if crow_esc and crow_esc.get_child_count() > 1:
				var v_esc := crow_esc.get_child(1) as LineEdit
				if v_esc and v_esc.has_focus():
					v_esc.release_focus()
					grab_focus.call_deferred()
					vp.set_input_as_handled()
					return

	if event is InputEventKey and event.pressed and event.keycode == KEY_C and not _in_tabs:
		_reset_current_row()
		vp.set_input_as_handled()
		return

	if event.is_action_pressed("menu_up"):
		if _in_tabs:
			_move_tab(-1)
		else:
			_move_content(-1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		if _in_tabs:
			_move_tab(1)
		else:
			_move_content(1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_left"):
		if not _in_tabs:
			_adjust_content(-1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_right"):
		if not _in_tabs:
			_adjust_content(1)
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_accept") or event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_Z):
		_confirm()
		vp.set_input_as_handled()
	elif event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_X):
		_cancel()
		vp.set_input_as_handled()

func _move_tab(dir: int) -> void:
	var ni := clampi(_tab_idx + dir, 0, _left_labels.size() - 1)
	if ni == _tab_idx:
		return
	_tab_idx = ni
	_highlight_tabs()
	_position_soul_tabs(_tab_idx, false)
	_play_sfx(SfxId.MENU_MOVE)

func _move_content(dir: int) -> void:
	var count := _content_list.get_child_count()
	if count == 0:
		return

	if not _in_tabs and _content_idx < count:
		var crow0 := _content_list.get_child(_content_idx) as HBoxContainer
		if crow0 and crow0.get_child_count() > 1:
			var v0 := crow0.get_child(1)
			if v0 is LineEdit:
				var d0: Dictionary = _tab_rows[TABS[_tab_idx]][_content_idx]
				if str(d0.get("type", "")) == "input":
					d0["value"] = v0.text
					_persist_row(TABS[_tab_idx], _content_idx)
					if v0.has_focus():
						v0.release_focus()
						grab_focus.call_deferred()

	var ni := clampi(_content_idx + dir, 0, count - 1)
	if ni == _content_idx:
		return
	_content_idx = ni
	_highlight_content()
	_position_soul_content(_content_idx, false)
	_ensure_visible(_content_idx)
	_play_sfx(SfxId.MENU_MOVE)

func _adjust_content(dir: int) -> void:
	if _content_list.get_child_count() == 0:
		return
	var row := _content_list.get_child(_content_idx) as HBoxContainer
	if not is_instance_valid(row):
		return

	var tab_name: String = TABS[_tab_idx]
	var rows: Array = _tab_rows.get(tab_name, [])
	if _content_idx >= rows.size():
		return

	var data: Dictionary = rows[_content_idx]
	var t: String = str(data.get("type", ""))

	if t == "slider":
		var v: float = float(data.get("value", 0))
		var step: float = float(data.get("step", 0.05))
		var mn: float = float(data.get("min", 0))
		var mx: float = float(data.get("max", 1))
		v = clampf(v + dir * step, mn, mx)
		data["value"] = v
		_update_row_value(row, data)
		_persist_row(tab_name, _content_idx)
	elif t == "option" or t == "theme_option":
		var opts: Array = data.get("options", [])
		var cur: int = int(data.get("value", 0))
		cur = clampi(cur + dir, 0, max(0, opts.size() - 1))
		data["value"] = cur
		_update_row_value(row, data)
		_persist_row(tab_name, _content_idx)
	elif t == "check":
		var cur_b: bool = bool(data.get("value", false))
		data["value"] = not cur_b
		_update_row_value(row, data)
		_persist_row(tab_name, _content_idx)

	_play_sfx(SfxId.MENU_MOVE)

func _persist_row(tab_name: String, idx: int) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	var isrv := get_node_or_null("/root/InputService")
	if sm == null:
		return

	var data: Dictionary = _tab_rows[tab_name][idx]
	var label: String = str(data.get("label", ""))

	match tab_name:
		"GENERAL":
			if label == "NOMBRE JUGADOR":
				sm.set("player_name", str(data["value"]).strip_edges())
				if sm.has_method("save_settings"): sm.save_settings()
			elif label == "PROVEEDOR ONLINE":
				var nm2 := get_node_or_null("/root/NetworkManager")
				var online_avail2 := false
				if nm2 and nm2.has_method("is_online_available"):
					online_avail2 = nm2.is_online_available()
				elif nm2 and nm2.has_method("is_steam_ready"):
					online_avail2 = nm2.is_steam_ready()
				var cur2: int = int(data.get("value", 0))
				if cur2 == 1 and not online_avail2:
					_play_sfx(SfxId.ERROR)
					if _hint:
						_hint.text = "ONLINE no disponible"
					return
				var want_mode := 1 if cur2 == 1 else 0
				sm.set("network_mode", want_mode)
				if want_mode == 1 and "online_provider" in sm:
					sm.online_provider = "steam"
				if sm.has_method("save_settings"): sm.save_settings()
				if _hint:
					_hint.text = "Modo red: " + ("ONLINE" if want_mode == 1 else "LAN")
			elif label == "TEMA":
				var tids: PackedStringArray = data.get("theme_ids", PackedStringArray())
				var cur: int = int(data.get("value", 0))
				if cur < 0 or cur >= tids.size():
					return
				var want: String = str(tids[cur])
				var unlocked: bool = sm.has_method("is_theme_unlocked") and sm.is_theme_unlocked(want)
				if not unlocked:
					_play_sfx(SfxId.ERROR)
					if _hint:
						_hint.text = "Tema bloqueado: gana con todos los personajes para desbloquear LIGHT"
					return
				if sm.has_method("try_set_theme") and sm.try_set_theme(want):
					if _hint:
						_hint.text = "Tema cambiado a " + want.to_upper()
		"AUDIO":
			if label == "MUSICA":
				sm.set("music_volume", float(data["value"]))
			elif label == "SFX":
				sm.set("sfx_volume", float(data["value"]))
			if sm.has_method("save_settings"): sm.save_settings()
		"VIDEO":
			if label == "BRILLO":
				sm.set("brightness", float(data["value"]))
			elif label == "PANTALLA":
				sm.set("display_mode", 3 if int(data["value"]) == 1 else 0)
			elif label == "VHS":
				sm.set("vhs_enabled", bool(data["value"]))
			if sm.has_method("save_settings"): sm.save_settings()
		"CONTROLES":
			if label == "DEADZONE" and isrv and isrv.has_method("set_stick_deadzone"):
				isrv.set_stick_deadzone(float(data["value"]))

func _update_row_value(row: HBoxContainer, data: Dictionary) -> void:
	var t: String = str(data.get("type", ""))

	if t == "input":
		for c in row.get_children():
			if c is LineEdit and c.name == "Value":
				c.text = str(data.get("value", ""))
				break
		return

	var val_label: Label = row.get_node_or_null("Value") as Label
	if val_label == null:
		return

	if t == "slider":
		var v: float = float(data.get("value", 0))
		var mn: float = float(data.get("min", 0))
		var mx: float = float(data.get("max", 1))
		var pct := int((v - mn) / (mx - mn) * 10)
		var bar := ""
		for i in 10:
			bar += "I" if i < pct else "."
		val_label.text = "< %s > %d%%" % [bar, int(v * 100)] if str(data.get("label")) in ["MUSICA", "SFX", "BRILLO", "DEADZONE"] else "< %s >" % bar
	elif t == "option" or t == "theme_option":
		var opts: Array = data.get("options", [])
		var cur: int = clampi(int(data.get("value", 0)), 0, max(0, opts.size() - 1))
		val_label.text = "< %s >" % str(opts[cur]) if not opts.is_empty() else ""
	elif t == "check":
		var b: bool = bool(data.get("value", false))
		val_label.text = "[X]" if b else "[ ]"

func _confirm() -> void:
	if _in_tabs:
		var tab_name: String = TABS[_tab_idx]
		if tab_name == "VOLVER":
			_play_sfx(SfxId.SELECT)
			get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")
			return

		_play_sfx(SfxId.SELECT)
		_build_content(_tab_idx)
		_in_tabs = false
		_content_idx = 0
		_highlight_content()
		_position_soul_content(_content_idx, false)
	else:
		var tab_name: String = TABS[_tab_idx]
		var rows: Array = _tab_rows.get(tab_name, [])
		if _content_idx >= rows.size():
			return

		var data: Dictionary = rows[_content_idx]
		var t: String = str(data.get("type", ""))

		if t == "input":
			var crow2 := _content_list.get_child(_content_idx) as HBoxContainer
			if crow2 and crow2.get_child_count() > 1:
				var ed := crow2.get_child(1) as LineEdit
				if ed:
					if not ed.has_focus():
						ed.grab_focus()
					else:
						data["value"] = ed.text
						_persist_row(tab_name, _content_idx)
						ed.release_focus()
						grab_focus.call_deferred()
		elif t == "check":
			_adjust_content(0)
		elif t == "button":
			if str(data.get("label", "")) == "RESTABLECER":
				var isrv2 := get_node_or_null("/root/InputService")
				if isrv2 and isrv2.has_method("reset_all"):
					isrv2.reset_all()
					_sync_from_settings()
					_build_content(_tab_idx)
					_highlight_content()
					_position_soul_content(_content_idx, false)
				_play_sfx(SfxId.SELECT)
				if _hint: _hint.text = "Controles restablecidos"

func _cancel() -> void:
	_play_sfx(SfxId.SELECT)
	if _in_tabs:
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")
	else:
		_in_tabs = true
		_highlight_tabs()
		_position_soul_tabs(_tab_idx, false)

func _reset_current_row() -> void:
	if _in_tabs:
		return
	var tab_name: String = TABS[_tab_idx]
	var rows: Array = _tab_rows.get(tab_name, [])
	if _content_idx >= rows.size():
		return

	var data: Dictionary = rows[_content_idx]
	var t: String = str(data.get("type", ""))

	if t == "slider":
		match str(data.get("label")):
			"BRILLO": data["value"] = 1.0
			"DEADZONE": data["value"] = 0.2
			_: data["value"] = 0.8
	elif t == "option":
		data["value"] = 0
	elif t == "check":
		data["value"] = true

	_persist_row(tab_name, _content_idx)
	var row := _content_list.get_child(_content_idx) as HBoxContainer
	if is_instance_valid(row):
		_update_row_value(row, data)
	_highlight_content()

func _build_content(tab_idx: int) -> void:
	var tab_name: String = TABS[tab_idx]
	if _right_title:
		_right_title.text = tab_name

	for c in _content_list.get_children():
		_content_list.remove_child(c)
		c.queue_free()

	var rows: Array = _tab_rows.get(tab_name, []) if tab_name != "VOLVER" else []
	var font_res := preload("res://Fonts/deltarune font.ttf")

	for data in rows:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 36)
		row.add_theme_constant_override("separation", 12)

		var lbl := Label.new()
		lbl.name = "Label"
		lbl.text = str(data.get("label", ""))
		lbl.custom_minimum_size = Vector2(180, 0)
		lbl.add_theme_font_override("font", font_res)
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		if str(data.get("type", "")) == "input":
			var edit := LineEdit.new()
			edit.name = "Value"
			edit.custom_minimum_size = Vector2(260, 32)
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			edit.add_theme_font_override("font", font_res)
			edit.add_theme_font_size_override("font_size", 16)
			edit.placeholder_text = "Nombre"
			edit.text = str(data.get("value", ""))
			edit.focus_mode = Control.FOCUS_ALL
			edit.mouse_filter = Control.MOUSE_FILTER_STOP
			edit.editable = true
			edit.context_menu_enabled = false
			# Enter es consumido por LineEdit → conectar text_submitted para liberar foco
			edit.text_submitted.connect(_on_lineedit_submitted.bind(edit))
			edit.focus_exited.connect(_on_lineedit_focus_exited.bind(edit))
			row.add_child(edit)
		else:
			var val := Label.new()
			val.name = "Value"
			val.custom_minimum_size = Vector2(260, 0)
			val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			val.add_theme_font_override("font", font_res)
			val.add_theme_font_size_override("font_size", 18)
			row.add_child(val)

		_content_list.add_child(row)
		_update_row_value(row, data)

	_content_idx = 0
	_highlight_content()

func _highlight_tabs() -> void:
	var tm := get_node_or_null("/root/ThemeManager")
	var pal: Dictionary = tm.get_palette() if tm and tm.has_method("get_palette") else {}
	var sel: Color = pal.get("selected", Color(0, 1, 0, 1))
	var dim: Color = pal.get("dim", Color(0, 0.50196, 0, 1))

	for i in _left_labels.size():
		var lbl: Label = _left_labels[i]
		lbl.text = TABS[i]
		if _in_tabs:
			lbl.modulate = sel if i == _tab_idx else dim
		else:
			# en contenido, pestaña activa queda sel difuminada 0.5 alpha
			if i == _tab_idx:
				lbl.modulate = Color(sel.r, sel.g, sel.b, 0.5)
			else:
				lbl.modulate = Color(dim.r, dim.g, dim.b, 0.5)

	# solo difuminar bloque derecho cuando estamos en pestañas
	if _in_tabs:
		for j in _content_list.get_child_count():
			var row := _content_list.get_child(j) as HBoxContainer
			if not is_instance_valid(row):
				continue
			for c in row.get_children():
				if c is Label:
					c.modulate = Color(dim.r, dim.g, dim.b, 0.5)

	if _hint and _in_tabs:
		_hint.text = TAB_HINTS[_tab_idx]

func _get_content_hint(tab_name: String, row_idx: int) -> String:
	if tab_name not in _tab_rows:
		return ""
	var rows: Array = _tab_rows[tab_name]
	if row_idx < 0 or row_idx >= rows.size():
		return ""
	var label: String = str(rows[row_idx].get("label", ""))
	match label:
		"IDIOMA": return "Idioma bloqueado en español"
		"NOMBRE JUGADOR":
			var pn: String = str(rows[row_idx].get("value", "")).strip_edges()
			return "Tu alias en lobbies — %s" % (pn if pn != "" else "vacío")
		"PROVEEDOR ONLINE": return "LAN / Online — elige red"
		"TEMA":
			var opts: Array = rows[row_idx].get("options", [])
			var cur: int = int(rows[row_idx].get("value", 0))
			var cur_lbl: String = str(opts[cur]) if cur < opts.size() else ""
			return "Tema — %s" % cur_lbl
		"MUSICA": return "Volumen música — %d%%" % int(float(rows[row_idx].get("value", 1.0)) * 100)
		"SFX": return "Efectos — %d%%" % int(float(rows[row_idx].get("value", 1.0)) * 100)
		"BRILLO": return "Luminosidad — %d%%" % int(float(rows[row_idx].get("value", 1.0)) * 100)
		"PANTALLA":
			var v: int = int(rows[row_idx].get("value", 0))
			return "Pantalla — %s" % ("Completo" if v == 1 else "Ventana")
		"VHS":
			var b: bool = bool(rows[row_idx].get("value", true))
			return "Filtro analógico — %s" % ("ON" if b else "OFF")
		"DEADZONE": return "Zona muerta — %.2f respuesta del stick" % float(rows[row_idx].get("value", 0.2))
		"RESTABLECER": return "Restaura mandos por defecto"
		_: return label

func _highlight_content() -> void:
	if _in_tabs:
		_highlight_tabs()
		return

	# primero difuminar bloque inactivo (pestañas), luego iluminar fila activa
	_highlight_tabs()

	var tm := get_node_or_null("/root/ThemeManager")
	var pal: Dictionary = tm.get_palette() if tm and tm.has_method("get_palette") else {}
	var sel: Color = pal.get("selected", Color(0, 1, 0, 1))
	var dim: Color = pal.get("dim", Color(0, 0.50196, 0, 1))

	for i in _content_list.get_child_count():
		var row := _content_list.get_child(i) as HBoxContainer
		if not is_instance_valid(row):
			continue

		var is_sel := (i == _content_idx)
		for c in row.get_children():
			if c.name == "Label":
				var lbl := c as Label
				# preservar texto base sin prefijo de espacios
				lbl.modulate = sel if is_sel else dim
			elif c.name == "Value":
				c.modulate = sel if is_sel else dim

	if _hint:
		_hint.text = _get_content_hint(TABS[_tab_idx], _content_idx)

func _position_soul_tabs(idx: int, instant: bool) -> void:
	if _soul == null or _left_labels.is_empty():
		return
	if idx < 0 or idx >= _left_labels.size():
		return
	var t := _left_labels[idx]
	if not is_instance_valid(t):
		return
	# esperar layout sin descartar si aún no es visible
	for i in 3:
		if t.is_visible_in_tree() and t.size.y > 0:
			break
		await get_tree().process_frame
	if not is_instance_valid(self) or not is_instance_valid(t) or not is_instance_valid(_soul):
		return
	if not t.is_visible_in_tree():
		return
	var soul_h := _soul.size.y if _soul.size.y > 0 else 20.0
	var dest := t.global_position + Vector2(-28, (t.size.y - soul_h) / 2.0) - global_position
	_animate_soul(dest, instant)

func _position_soul_content(idx: int, instant: bool) -> void:
	if _soul == null or _content_list.get_child_count() == 0:
		return
	if idx < 0 or idx >= _content_list.get_child_count():
		return
	var row := _content_list.get_child(idx) as Control
	if not is_instance_valid(row):
		return
	for i in 3:
		if row.is_visible_in_tree() and row.size.y > 0:
			break
		await get_tree().process_frame
	if not is_instance_valid(self) or not is_instance_valid(row) or not is_instance_valid(_soul):
		return
	if not row.is_visible_in_tree():
		return
	var soul_h := _soul.size.y if _soul.size.y > 0 else 20.0
	var dest := row.global_position + Vector2(-28, (row.size.y - soul_h) / 2.0) - global_position
	_animate_soul(dest, instant)

func _animate_soul(dest: Vector2, instant: bool) -> void:
	if _soul_tween and _soul_tween.is_running():
		_soul_tween.kill()

	if instant:
		_soul.position = dest
	else:
		_soul_tween = create_tween()
		_soul_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_soul_tween.tween_property(_soul, "position", dest, 0.08)

func _ensure_visible(idx: int) -> void:
	if _scroll == null or _content_list.get_child_count() == 0:
		return
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	var row := _content_list.get_child(idx) as Control
	if is_instance_valid(row):
		_scroll.ensure_control_visible(row)

func _on_lineedit_submitted(_text: String, edit: LineEdit) -> void:
	# Enter dentro del LineEdit (consumido por el nodo) → persistir y liberar
	if not is_instance_valid(edit) or _in_tabs:
		return
	# buscar índice de la fila que contiene este edit
	for i in _content_list.get_child_count():
		var crow := _content_list.get_child(i) as HBoxContainer
		if crow and crow.get_child_count() > 1 and crow.get_child(1) == edit:
			var tab_name: String = TABS[_tab_idx]
			var rows: Array = _tab_rows.get(tab_name, [])
			if i < rows.size() and str(rows[i].get("type", "")) == "input":
				rows[i]["value"] = edit.text
				_persist_row(tab_name, i)
			edit.release_focus()
			grab_focus.call_deferred()
			_play_sfx(SfxId.SELECT)
			break

func _on_lineedit_focus_exited(edit: LineEdit) -> void:
	if not is_instance_valid(edit):
		return
	# si salió por click fuera u otro motivo, persistir también
	for i in _content_list.get_child_count():
		var crow := _content_list.get_child(i) as HBoxContainer
		if crow and crow.get_child_count() > 1 and crow.get_child(1) == edit:
			var tab_name: String = TABS[_tab_idx]
			var rows: Array = _tab_rows.get(tab_name, [])
			if i < rows.size() and str(rows[i].get("type", "")) == "input":
				rows[i]["value"] = edit.text
				_persist_row(tab_name, i)
			break
	grab_focus.call_deferred()

func _play_sfx(sfx_id: int) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(sfx_id)
