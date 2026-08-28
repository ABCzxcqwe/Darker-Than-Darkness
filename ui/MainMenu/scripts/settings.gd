extends Control
## Mock Settings lateral — pestañas izquierda General/Audio/Video/Red/Controles/Volver
## Derecha lista única scroll, teclado-only Z/X/C, soul rojo, #008000/#00FF00

const TABS := ["GENERAL", "AUDIO", "VIDEO", "CONTROLES", "VOLVER"]
const TAB_HINTS := ["Perfil LAN", "Volumen", "Brillo y pantalla", "Mando y teclado", "Volver"]

var _tab_idx := 0
var _content_idx := 0
var _in_tabs := true
var _busy := false

# Definición de filas por pestaña: cada fila {label, type, ...}
var _tab_rows := {
	"GENERAL": [
		{"label": "IDIOMA", "type": "option", "options": ["Español [Bloqueado]"], "value": 0},
		{"label": "NOMBRE JUGADOR", "type": "input", "value": ""},
		{"label": "PROVEEDOR ONLINE", "type": "option", "options": ["LAN"], "value": 0},
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
	var am0 := get_node_or_null("/root/AudioManager")
	if am0 and am0.has_method("play_menu_drone") and am0.current_global_state != "menu_drone":
		am0.play_menu_drone()
	var tabs_vbox := $LeftPanel/Margin/LeftVBox/Tabs
	for c in tabs_vbox.get_children():
		if c is Label:
			_left_labels.append(c)
	_sync_from_settings()
	_build_content(_tab_idx)
	_highlight_tabs()
	_position_soul_tabs(_tab_idx, true)
	grab_focus()

func _sync_from_settings() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	var isrv := get_node_or_null("/root/InputService")
	if sm:
		_tab_rows["GENERAL"][0]["value"] = 0
		_tab_rows["GENERAL"][1]["value"] = sm.player_name
		_tab_rows["AUDIO"][0]["value"] = sm.music_volume
		_tab_rows["AUDIO"][1]["value"] = sm.sfx_volume
		_tab_rows["VIDEO"][0]["value"] = sm.brightness
		_tab_rows["VIDEO"][1]["value"] = 1 if sm.display_mode == 3 else 0
		_tab_rows["VIDEO"][2]["value"] = sm.vhs_enabled
		# LAN-only: proveedor bloqueado, idioma bloqueado
		_tab_rows["GENERAL"][2]["options"] = ["LAN"]
		_tab_rows["GENERAL"][2]["value"] = 0
	if isrv:
		_tab_rows["CONTROLES"][0]["value"] = isrv.stick_deadzone

func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	var vp := get_viewport()
	if vp == null:
		return
	# Si está editando un LineEdit (NOMBRE JUGADOR), dejar escribir
	if not _in_tabs and _content_list.get_child_count() > _content_idx:
		var crow := _content_list.get_child(_content_idx) as HBoxContainer
		if crow and crow.get_child_count() > 1:
			var v := crow.get_child(1)
			if v is LineEdit and v.has_focus() and event is InputEventKey and event.pressed and event.unicode != 0 and event.keycode != KEY_ENTER and event.keycode != KEY_KP_ENTER:
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
		else:
			# En pestañas, izquierda no hace nada (podrÁ­a volver a MainMenu)
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
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)

func _move_content(dir: int) -> void:
	var count := _content_list.get_child_count()
	if count == 0:
		return
	# Guardar valor del LineEdit antes de salir
	if not _in_tabs and _content_idx < count:
		var crow0 := _content_list.get_child(_content_idx) as HBoxContainer
		if crow0 and crow0.get_child_count() > 1:
			var v0 := crow0.get_child(1)
			if v0 is LineEdit:
				var d0: Dictionary = _tab_rows[TABS[_tab_idx]][_content_idx]
				if str(d0.get("type","")) == "input":
					d0["value"] = v0.text
					_persist_row(TABS[_tab_idx], _content_idx)
					if v0.has_focus():
						v0.release_focus()
	var ni := clampi(_content_idx + dir, 0, count - 1)
	if ni == _content_idx:
		return
	_content_idx = ni
	_highlight_content()
	_position_soul_content(_content_idx, false)
	_ensure_visible(_content_idx)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)

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
	elif t == "option":
		var opts: Array = data.get("options", [])
		var cur: int = int(data.get("value", 0))
		cur = clampi(cur, 0, max(0, opts.size() - 1))
		cur = clampi(cur + dir, 0, max(0, opts.size() - 1))
		data["value"] = cur
		_update_row_value(row, data)
		_persist_row(tab_name, _content_idx)
	elif t == "check":
		var cur_b: bool = bool(data.get("value", false))
		data["value"] = not cur_b
		_update_row_value(row, data)
		_persist_row(tab_name, _content_idx)
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(SfxId.MENU_MOVE)

func _persist_row(tab_name: String, idx: int) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	var isrv := get_node_or_null("/root/InputService")
	if sm == null:
		return
	var data: Dictionary = _tab_rows[tab_name][idx]
	var label: String = str(data.get("label", ""))
	match tab_name:
		"GENERAL":
			if label == "IDIOMA":
				return
			elif label == "NOMBRE JUGADOR":
				sm.player_name = str(data["value"]).strip_edges()
				sm.save_settings()
			elif label == "PROVEEDOR ONLINE":
				return
		"AUDIO":
			if label == "MUSICA":
				sm.music_volume = float(data["value"])
				sm.save_settings()
			elif label == "SFX":
				sm.sfx_volume = float(data["value"])
				sm.save_settings()
		"VIDEO":
			if label == "BRILLO":
				sm.brightness = float(data["value"])
				sm.save_settings()
			elif label == "PANTALLA":
				sm.display_mode = 3 if int(data["value"]) == 1 else 0
				sm.save_settings()
			elif label == "VHS":
				sm.vhs_enabled = bool(data["value"])
				sm.save_settings()
		"CONTROLES":
			if label == "DEADZONE":
				if isrv:
					isrv.set_stick_deadzone(float(data["value"]))

func _update_row_value(row: HBoxContainer, data: Dictionary) -> void:
	var t: String = str(data.get("type", ""))
	if t == "input":
		for c in row.get_children():
			if c is LineEdit and c.name == "Value":
				c.text = str(data.get("value", ""))
				break
		return
	var val_label: Label = null
	for c in row.get_children():
		if c is Label and c.name == "Value":
			val_label = c
			break
	if val_label == null:
		return
	if t == "slider":
		var v: float = float(data.get("value", 0))
		var pct := int((v - float(data.get("min",0))) / (float(data.get("max",1)) - float(data.get("min",0))) * 10)
		var bar := ""
		for i in 10:
			bar += "I" if i < pct else "."
		val_label.text = "< %s > %d%%" % [bar, int(v*100)] if str(data.get("label")) in ["MUSICA","SFX","BRILLO","DEADZONE"] else "< %s >" % bar
	elif t == "option":
		var opts: Array = data.get("options", [])
		var cur: int = clampi(int(data.get("value", 0)), 0, max(0, opts.size() - 1))
		val_label.text = "< %s >" % str(opts[cur]) if opts.size() > 0 else ""
	elif t == "check":
		var b: bool = bool(data.get("value", false))
		val_label.text = "[X]" if b else "[ ]"

func _confirm() -> void:
	if _in_tabs:
		var tab_name: String = TABS[_tab_idx]
		if tab_name == "VOLVER":
			var am := get_node_or_null("/root/AudioManager")
			if am and am.has_method("play_sfx_ui"):
				am.play_sfx_ui(SfxId.SELECT)
			get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")
			return
		var am2 := get_node_or_null("/root/AudioManager")
		if am2 and am2.has_method("play_sfx_ui"):
			am2.play_sfx_ui(SfxId.SELECT)
		_build_content(_tab_idx)
		_in_tabs = false
		_content_idx = 0
		_highlight_content()
		_position_soul_content(_content_idx, true)
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
						var d2: Dictionary = rows[_content_idx]
						d2["value"] = ed.text
						_persist_row(tab_name, _content_idx)
						ed.release_focus()
			return
		elif t == "check":
			_adjust_content(0)
		elif t == "button":
			if str(data.get("label", "")) == "RESTABLECER":
				var isrv2 := get_node_or_null("/root/InputService")
				if isrv2:
					isrv2.reset_all()
					_sync_from_settings()
					_build_content(_tab_idx)
					_highlight_content()
					_position_soul_content(_content_idx, true)
				var am := get_node_or_null("/root/AudioManager")
				if am and am.has_method("play_sfx_ui"):
					am.play_sfx_ui(SfxId.SELECT)
				_hint.text = "Controles restablecidos"
			else:
				_adjust_content(0)
		elif t == "slider" or t == "option":
			pass

func _cancel() -> void:
	if _in_tabs:
		var am := get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.SELECT)
		get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")
	else:
		# Volver a pestañas
		var am := get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_sfx_ui"):
			am.play_sfx_ui(SfxId.SELECT)
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
		if str(data.get("label")) == "BRILLO":
			data["value"] = 1.0
		elif str(data.get("label")) == "DEADZONE":
			data["value"] = 0.2
		else:
			data["value"] = 0.8
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
	_right_title.text = tab_name
	for c in _content_list.get_children():
		if is_instance_valid(c):
			c.free()
	var rows: Array = _tab_rows.get(tab_name, [])
	if tab_name == "VOLVER":
		rows = []
	for data in rows:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 36)
		row.add_theme_constant_override("separation", 12)
		var lbl := Label.new()
		lbl.name = "Label"
		lbl.text = "" + str(data.get("label", ""))
		lbl.custom_minimum_size = Vector2(180, 0)
		lbl.add_theme_font_override("font", preload("res://Fonts/deltarune font.ttf"))
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		if str(data.get("type", "")) == "input":
			var edit := LineEdit.new()
			edit.name = "Value"
			edit.custom_minimum_size = Vector2(260, 32)
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			edit.add_theme_font_override("font", preload("res://Fonts/deltarune font.ttf"))
			edit.add_theme_font_size_override("font_size", 16)
			edit.placeholder_text = "Nombre"
			edit.text = str(data.get("value", ""))
			edit.focus_mode = Control.FOCUS_ALL
			edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(edit)
		else:
			var val := Label.new()
			val.name = "Value"
			val.custom_minimum_size = Vector2(260, 0)
			val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			val.add_theme_font_override("font", preload("res://Fonts/deltarune font.ttf"))
			val.add_theme_font_size_override("font_size", 18)
			row.add_child(val)
		_content_list.add_child(row)
		_update_row_value(row, data)
	_content_idx = 0
	_highlight_content()

func _highlight_tabs() -> void:
	for i in _left_labels.size():
		var lbl: Label = _left_labels[i]
		if i == _tab_idx:
			lbl.modulate = Color(0, 1, 0, 1) if _in_tabs else Color(0, 0.50196081, 0, 1)
			if _in_tabs:
				lbl.text = "    " + TABS[i]
			else:
				lbl.text = "" + TABS[i]
		else:
			lbl.modulate = Color(0, 0.50196081, 0, 1)
			lbl.text = "" + TABS[i]
	# Contenido atenuado cuando foco está en pestañas
	for j in _content_list.get_child_count():
		var row := _content_list.get_child(j) as HBoxContainer
		if not is_instance_valid(row):
			continue
		for c in row.get_children():
			if c is Label:
				c.modulate = Color(0, 0.50196081, 0, 0.5) if _in_tabs else Color(0, 0.50196081, 0, 1)
	if _hint:
		_hint.text = TAB_HINTS[_tab_idx] if _in_tabs else "[←] [→] ajustar  Z confirmar  X volver  C reset"

func _highlight_content() -> void:
	if _in_tabs:
		_highlight_tabs()
		return
	# Resaltar fila activa en verde claro
	for i in _content_list.get_child_count():
		var row := _content_list.get_child(i) as HBoxContainer
		if not is_instance_valid(row):
			continue
		var is_sel := i == _content_idx
		for c in row.get_children():
			if c.name == "Label":
				var lbl := c as Label
				c.modulate = Color(0, 1, 0, 1) if is_sel else Color(0, 0.50196081, 0, 1)
				var base_txt: String = lbl.text.trim_prefix("").trim_prefix("    ").strip_edges()
				lbl.text = ("    " + base_txt) if is_sel else ("" + base_txt)
			elif c.name == "Value":
				c.modulate = Color(0, 1, 0, 1) if is_sel else Color(0, 0.50196081, 0, 1)
				if c is LineEdit:
					if is_sel:
						c.grab_focus()
					elif c.has_focus():
						c.release_focus()
	_highlight_tabs()

func _position_soul_tabs(idx: int, instant: bool) -> void:
	if _soul == null or _left_labels.is_empty():
		return
	await get_tree().process_frame
	if idx < 0 or idx >= _left_labels.size():
		return
	var t := _left_labels[idx]
	if not is_instance_valid(t):
		return
	var dest := t.global_position + Vector2(-28, (t.size.y - _soul.size.y)/2.0) - global_position
	if instant:
		_soul.position = dest
	else:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_soul, "position", dest, 0.08)

func _position_soul_content(idx: int, instant: bool) -> void:
	if _soul == null or _content_list.get_child_count()==0:
		return
	await get_tree().process_frame
	if idx < 0 or idx >= _content_list.get_child_count():
		return
	var row := _content_list.get_child(idx) as Control
	if not is_instance_valid(row):
		return
	var dest := row.global_position + Vector2(-28, (row.size.y - _soul.size.y)/2.0) - global_position
	if instant:
		_soul.position = dest
	else:
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_soul, "position", dest, 0.08)

func _ensure_visible(idx: int) -> void:
	if _scroll == null or _content_list.get_child_count()==0:
		return
	await get_tree().process_frame
	var row := _content_list.get_child(idx) as Control
	if is_instance_valid(row):
		_scroll.ensure_control_visible(row)
