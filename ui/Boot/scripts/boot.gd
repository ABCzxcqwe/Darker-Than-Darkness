extends Node

const THRESHOLD_MS := 0
const MIN_DISPLAY_MS := 800
const TERMINAL_SCENE := "res://ui/Boot/scenes/TerminalLoader.tscn"

func _ready() -> void:
	var grouped: Dictionary = _collect_grouped()
	var flat: Array[String] = _flatten_grouped(grouped)
	for p in flat:
		if ResourceLoader.exists(p):
			ResourceLoader.load_threaded_request(p)
	# Test: THRESHOLD 0 fuerza TerminalLoader siempre (ver 800ms). Restaurar a 300 para anti-flash SSD.
	if THRESHOLD_MS > 0:
		await get_tree().create_timer(THRESHOLD_MS / 1000.0).timeout
		if _all_loaded(flat):
			_go_next()
			return
	if not ResourceLoader.exists(TERMINAL_SCENE) and not FileAccess.file_exists(TERMINAL_SCENE):
		await _wait_until_loaded(flat)
		_go_next()
		return
	var loader_scene: PackedScene = load(TERMINAL_SCENE) as PackedScene
	if loader_scene == null:
		await _wait_until_loaded(flat)
		_go_next()
		return
	var loader := loader_scene.instantiate()
	get_tree().root.add_child.call_deferred(loader)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(loader) or not loader.is_inside_tree():
		await _wait_until_loaded(flat)
		_go_next()
		return
	if loader.has_method("run_with_real_progress_grouped"):
		await loader.run_with_real_progress_grouped(grouped, MIN_DISPLAY_MS)
	elif loader.has_method("run_with_real_progress"):
		await loader.run_with_real_progress(flat, MIN_DISPLAY_MS)
	else:
		await _wait_until_loaded(flat)
	if is_instance_valid(loader):
		# Transición suave: desvanecer terminal antes de cambiar escena
		var tween := loader.create_tween()
		tween.tween_property(loader, "modulate:a", 0.0, 0.4)
		await tween.finished
		loader.queue_free()
	_go_next()

func _collect_grouped() -> Dictionary:
	var grouped: Dictionary = {}
	# DATABASE
	grouped["DATABASE"] = [{"path": "res://Maps/WorldDatabase.tres", "name": "WorldDatabase"}]
	# MAPS con display_name
	var map_entries: Array = _get_map_entries()
	if map_entries.size() > 0:
		grouped["MAPS"] = map_entries
	# CHARACTERS
	var char_count := _get_character_count()
	var char_label := "CharacterDatabase (%d)" % char_count if char_count > 0 else "CharacterDatabase"
	grouped["CHARACTERS"] = [{"path": "res://Characters/CharacterDatabase.tres", "name": char_label}]
	# AUDIO
	var tm := get_node_or_null("/root/ThemeManager")
	var music_path := "res://ui/Boot/scenes/AUDIO_DRONE.wav"
	if tm and tm.has_method("get_music_path"):
		music_path = tm.get_music_path()
	var audio_name := music_path.get_file() if music_path != "" else "AUDIO"
	grouped["AUDIO"] = [{"path": music_path, "name": audio_name}]
	# FONTS
	grouped["FONTS"] = [{"path": "res://Fonts/deltarune font.ttf", "name": "deltarune font"}]
	return grouped

func _flatten_grouped(grouped: Dictionary) -> Array[String]:
	var flat: Array[String] = []
	for cat in ["DATABASE", "MAPS", "CHARACTERS", "AUDIO", "FONTS"]:
		if not grouped.has(cat):
			continue
		for e in grouped[cat]:
			var p: String = str(e.get("path", "")) if e is Dictionary else str(e)
			if p != "" and not flat.has(p):
				flat.append(p)
	for k in grouped.keys():
		if k in ["DATABASE", "MAPS", "CHARACTERS", "AUDIO", "FONTS"]:
			continue
		for e in grouped[k]:
			var p2: String = str(e.get("path", "")) if e is Dictionary else str(e)
			if p2 != "" and not flat.has(p2):
				flat.append(p2)
	return flat

func _collect_targets() -> Array[String]:
	return _flatten_grouped(_collect_grouped())

func _get_map_entries() -> Array:
	var arr: Array = []
	var db_path := "res://Maps/WorldDatabase.tres"
	if not ResourceLoader.exists(db_path):
		return arr
	var res: Resource = load(db_path)
	if res == null:
		return arr
	if "map_list" in res:
		var ml: Array = res.map_list
		for md in ml:
			if md == null:
				continue
			var path: String = ""
			var dname: String = ""
			if "map_scene" in md and md.map_scene:
				var ps: PackedScene = md.map_scene
				if ps and ps.resource_path != "":
					path = ps.resource_path
			if path == "":
				continue
			if "display_name" in md and str(md.display_name) != "":
				dname = str(md.display_name)
			elif "id" in md and str(md.id) != "":
				dname = str(md.id)
			else:
				dname = path.get_file().get_basename()
			dname = dname.substr(0, 18)
			arr.append({"path": path, "name": dname})
	return arr

func _get_character_count() -> int:
	var cpath := "res://Characters/CharacterDatabase.tres"
	if not ResourceLoader.exists(cpath):
		return 0
	var res: Resource = load(cpath)
	if res and "character_list" in res:
		return (res.character_list as Array).size()
	return 0

func _get_map_scene_paths() -> Array[String]:
	var arr: Array[String] = []
	for e in _get_map_entries():
		arr.append(str(e["path"]))
	return arr

func _all_loaded(targets: Array[String]) -> bool:
	for p in targets:
		var prog: Array = []
		var st := ResourceLoader.load_threaded_get_status(p, prog)
		if st != ResourceLoader.THREAD_LOAD_LOADED:
			if st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE or st == ResourceLoader.THREAD_LOAD_FAILED:
				continue
			return false
		if ResourceLoader.load_threaded_get(p) == null:
			return false
	return true

func _wait_until_loaded(targets: Array[String]) -> void:
	while not _all_loaded(targets):
		await get_tree().process_frame
		if not is_inside_tree():
			break

func _go_next() -> void:
	if not is_inside_tree():
		return
	if SettingsManager.is_first_launch():
		get_tree().change_scene_to_file.call_deferred("res://ui/Boot/scenes/FirstTime.tscn")
	else:
		get_tree().change_scene_to_file.call_deferred("res://ui/Boot/scenes/Intro.tscn")
