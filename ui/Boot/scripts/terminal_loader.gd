extends Control
## TerminalLoader — secuencial per-recurso inline |####----------------|20%/100% (n/total) > Name
## Barra muta la misma línea (wget-style) siguiendo la línea, no abajo. +1s entre recursos/sistemas.

const TYPEWRITER_DELAY := 0.015
const MIN_DISPLAY_MS := 800
const BAR_WIDTH := 20
const ORDER := ["DATABASE", "MAPS", "CHARACTERS", "AUDIO", "FONTS"]
const PAUSE_PER_RESOURCE := 1.0
const PAUSE_PER_SYSTEM := 1.0
const TRANSITION_DELAY := 1.5

var _grouped: Dictionary = {}
var _targets: Array[String] = [] # compat fallback
var _start_ms: int = 0
var _finished := false
var _bar_line_idx: int = -1
var _bar_template: String = ""
var _bar_cat: String = ""
var _bar_cur: int = 1
var _bar_total: int = 1
var _bar_sub: String = ""

@onready var _output: RichTextLabel = $Margin/VBox/Output

func _ready() -> void:
	if _output:
		_output.text = ""
		_output.scroll_active = true

## Nuevo API agrupado — preferido por boot.gd
func run_with_real_progress_grouped(grouped: Dictionary, min_display_ms: int = MIN_DISPLAY_MS) -> void:
	if not is_inside_tree():
		await ready
		if not is_inside_tree():
			return
	_grouped = grouped
	_targets = _flatten(grouped)
	_start_ms = Time.get_ticks_msec()
	var player_name: String = "anon"
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null and Engine.has_singleton("SettingsManager"):
		sm = Engine.get_singleton("SettingsManager")
	if sm and "player_name" in sm and str(sm.player_name) != "":
		player_name = str(sm.player_name)
	var prompt := "DARKER:\\Users\\%s>" % player_name
	_append_line(prompt + " ./darker_than_darkness --init", false)
	_append_line("Inicializando subsistemas [GREEN_DRONE]...", true)
	if get_tree() == null:
		return
	await get_tree().create_timer(0.12).timeout
	await _poll_grouped_sequential()
	var elapsed := Time.get_ticks_msec() - _start_ms
	var remain := min_display_ms - elapsed
	if remain > 0 and get_tree():
		await get_tree().create_timer(remain / 1000.0).timeout
	_append_line("OK. Lanzando menu...", true)
	if get_tree():
		await get_tree().create_timer(0.3).timeout
	# Pausa suave antes de transición abrupta
	if get_tree():
		await get_tree().create_timer(TRANSITION_DELAY).timeout
	_finished = true

## Fallback compat — Array plano
func run_with_real_progress(targets: Array[String], min_display_ms: int = MIN_DISPLAY_MS) -> void:
	var grouped: Dictionary = {"SYSTEM": []}
	for p in targets:
		(grouped["SYSTEM"] as Array).append({"path": p, "name": p.get_file()})
	await run_with_real_progress_grouped(grouped, min_display_ms)

func is_finished() -> bool:
	return _finished

func _poll_grouped_sequential() -> void:
	var order := _ordered_keys(_grouped)
	if order.is_empty():
		_update_bar_inline("SYSTEM", 1.0, 1, 1, "SYSTEM")
		return
	for cat in order:
		if get_tree() == null or not is_inside_tree():
			break
		var entries: Array = _grouped[cat]
		if entries.is_empty():
			continue
		_append_line("> CARGANDO %s..." % cat, true)
		for idx in entries.size():
			if get_tree() == null or not is_inside_tree():
				break
			var e: Variant = entries[idx]
			var path: String = str(e.get("path", "")) if e is Dictionary else str(e)
			var subname: String = str(e.get("name", path.get_file())) if e is Dictionary else path.get_file()
			subname = subname.substr(0, 18)
			var cur := idx + 1
			var total := entries.size()
			# Reservar línea con template estable; barra mutará solo interior y %
			_reserve_bar_line(cat, cur, total, subname)
			# Poll 1x1 este recurso, barra muta misma línea slice interno
			await _poll_single_inline(path, cat, cur, total, subname)
			# Verificación explícita 1x1
			var ok := ResourceLoader.load_threaded_get(path) != null
			# Si es INVALID/FAILED pero marcado como ok arriba, ya se trató como 100%
			# Fijar barra en 100% y liberar línea
			_update_bar_inline(cat, 1.0, cur, total, subname)
			_commit_bar_line()
			if ok:
				_append_line("  [OK] %s > %s verificado" % [cat, subname], false)
			else:
				_append_line("  [FAIL] %s > %s" % [cat, subname], false)
			# 1s entre recursos
			if get_tree():
				await get_tree().create_timer(PAUSE_PER_RESOURCE).timeout
		_append_line("  [OK] %s (%d/%d)" % [cat, entries.size(), entries.size()], false)
		if get_tree():
			await get_tree().create_timer(PAUSE_PER_SYSTEM).timeout

func _poll_single_inline(path: String, cat: String, cur: int, total: int, subname: String) -> void:
	if path == "":
		_update_bar_inline(cat, 1.0, cur, total, subname)
		return
	while true:
		if get_tree() == null or not is_inside_tree():
			break
		var prog_arr: Array = []
		var status := ResourceLoader.load_threaded_get_status(path, prog_arr)
		var prog := 0.0
		if prog_arr.size() > 0:
			prog = clampf(float(prog_arr[0]), 0.0, 1.0)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			if ResourceLoader.load_threaded_get(path) != null:
				prog = 1.0
				_update_bar_inline(cat, prog, cur, total, subname)
				break
			else:
				_update_bar_inline(cat, prog, cur, total, subname)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			prog = 1.0
			_update_bar_inline(cat, prog, cur, total, subname)
			break
		else:
			_update_bar_inline(cat, prog, cur, total, subname)
		if prog >= 1.0 and status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		await get_tree().process_frame
		if not is_inside_tree():
			break
	_update_bar_inline(cat, 1.0, cur, total, subname)

func _ordered_keys(grouped: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in ORDER:
		if grouped.has(k):
			out.append(k)
	for k in grouped.keys():
		if not out.has(k):
			out.append(str(k))
	return out

func _flatten(grouped: Dictionary) -> Array[String]:
	var flat: Array[String] = []
	for k in grouped.keys():
		for e in grouped[k]:
			var p: String = str(e.get("path", "")) if e is Dictionary else str(e)
			if p != "" and not flat.has(p):
				flat.append(p)
	return flat

func _reserve_bar_line(cat: String, cur: int, total: int, subname: String) -> void:
	if not is_instance_valid(_output):
		return
	_bar_cat = cat
	_bar_cur = cur
	_bar_total = total
	_bar_sub = subname
	var bar_init := "|" + "-".repeat(BAR_WIDTH) + "|"
	var template := "%-10s %s0%%/100%% (%d/%d) > %s" % [cat, bar_init, cur, total, subname]
	_bar_template = template
	if _output.text != "" and not _output.text.ends_with("\n"):
		_output.text += "\n"
	_output.text += template
	_bar_line_idx = _output.text.split("\n").size() - 1
	_scroll_bottom()

func _commit_bar_line() -> void:
	_bar_line_idx = -1
	_bar_template = ""
	if is_instance_valid(_output) and not _output.text.ends_with("\n"):
		_output.text += "\n"
	_scroll_bottom()

func _scroll_bottom() -> void:
	if not is_instance_valid(_output):
		return
	# RichTextLabel con scroll_active: forzar al final cada vez que añadimos/mutamos línea
	var vbar := _output.get_v_scroll_bar()
	if vbar:
		# deferred para que layout se actualice tras asignar text
		vbar.value = vbar.max_value
		# fallback: asegurar línea visible si hay muchas
		var line_count := _output.get_line_count()
		if line_count > 0:
			_output.scroll_to_line(line_count - 1)

func _update_bar_inline(cat: String, progress: float, cur: int, total: int, subname: String) -> void:
	if not is_instance_valid(_output):
		return
	progress = clampf(progress, 0.0, 1.0)
	var filled := int(progress * BAR_WIDTH)
	var inner := ""
	for i in BAR_WIDTH:
		inner += "#" if i < filled else "-"
	var pct := int(progress * 100)
	var pct_str := "%d%%/100%%" % pct
	var lines: PackedStringArray = _output.text.split("\n")
	var target_line: String = ""
	if _bar_line_idx >= 0 and _bar_line_idx < lines.size():
		target_line = lines[_bar_line_idx]
	else:
		_reserve_bar_line(cat, cur, total, subname)
		lines = _output.text.split("\n")
		target_line = lines[_bar_line_idx]
	var first_pipe := target_line.find("|")
	var second_pipe := target_line.find("|", first_pipe + 1)
	if first_pipe != -1 and second_pipe != -1:
		var prefix := target_line.substr(0, first_pipe + 1)
		var suffix := target_line.substr(second_pipe)
		var pct_marker := "%/100%"
		var pct_pos := suffix.find(pct_marker)
		if pct_pos != -1:
			var pct_start := suffix.rfind(" ", pct_pos) + 1
			if pct_start < 0:
				pct_start = 1
			var before_pct := suffix.substr(0, pct_start)
			var after_pct := suffix.substr(pct_pos + pct_marker.length())
			suffix = before_pct + pct_str + after_pct
		var new_line := prefix + inner + suffix
		lines[_bar_line_idx] = new_line
		_output.text = "\n".join(lines)
		_scroll_bottom()
	else:
		var bar := "|" + inner + "|"
		var line := "%-10s %s%d%%/100%% (%d/%d) > %s" % [cat, bar, pct, cur, total, subname]
		lines[_bar_line_idx] = line
		_output.text = "\n".join(lines)
		_scroll_bottom()

func _append_line(text: String, typewriter: bool) -> void:
	if not is_instance_valid(_output):
		return
	if _bar_line_idx >= 0:
		_commit_bar_line()
	if not typewriter:
		_output.text += text + "\n"
		_scroll_bottom()
		return
	_output.text += ""
	for i in text.length():
		if not is_instance_valid(_output) or get_tree() == null:
			return
		_output.text += text[i]
		_scroll_bottom()
		await get_tree().create_timer(TYPEWRITER_DELAY).timeout
	if is_instance_valid(_output):
		_output.text += "\n"
		_scroll_bottom()
