# res://tests/dev_mode/DevModeSmoke.gd
# Smoke test del catálogo dev y del panel F8 del selector.
# Ejecutar desde el editor (DevMode está activo en el editor):
#   godot --headless --path . res://tests/dev_mode/DevModeSmoke.tscn
extends Node


class FakeTimer extends Node:
	var duration := 0.0
	var stopped := false

	func start_timer(d: float) -> void:
		duration = d

	func stop_timer() -> void:
		stopped = true


class FakeHealth extends Node:
	func check_all_survivors_incapacitated() -> bool:
		return true


func _ready() -> void:
	await get_tree().process_frame

	var failures: Array[String] = []

	var normal_count := CharacterRegistry.get_all().size()
	var dev_count := CharacterRegistry.get_all_dev().size()
	if normal_count != 5:
		failures.append("Se esperaban 5 personajes normales, hay %d" % normal_count)
	if dev_count != 4:
		failures.append("Se esperaban 4 personajes dev, hay %d" % dev_count)

	for data in CharacterRegistry.get_all():
		if data.dev_only:
			failures.append("Personaje dev en get_all(): %s" % data.display_name)

	var fallback := CharacterRegistry.get_fallback("killer")
	if fallback == null:
		failures.append("get_fallback('killer') devolvió null")
	elif fallback.dev_only:
		failures.append("get_fallback('killer') devolvió un personaje dev")

	var jevil_test := CharacterRegistry.get_character(8)
	if jevil_test == null or not jevil_test.dev_only:
		failures.append("Jevil_Test (id 8) no está marcado como dev_only")

	if not DevMode.is_enabled():
		failures.append("DevMode debería estar activo en el editor")

	# ── Validación de servidor ──
	LobbyManager.players = {
		1: {"name": "Dev", "assigned_role": "survivor", "character_id": -1},
		2: {"name": "Normal", "assigned_role": "survivor", "character_id": -1},
	}
	LobbyManager.dev_peers.clear()

	var v_normal := LobbyManager._validate_character_selection(2, 2)
	if not v_normal["ok"]:
		failures.append("Un personaje normal del rol debería aceptarse: %s" % v_normal)

	var v_dev_nondev := LobbyManager._validate_character_selection(2, 6)
	if v_dev_nondev["ok"] or v_dev_nondev["reason"] != "not_dev":
		failures.append("Un peer no dev no debería poder elegir Susie_LMS: %s" % v_dev_nondev)

	var v_team := LobbyManager._validate_character_selection(1, 4)
	if v_team["ok"] or v_team["reason"] != "team":
		failures.append("Jevil (killer normal) no debería aceptarse en rol survivor: %s" % v_team)

	# Un peer dev puede elegir un personaje test del otro bando: el rol se ajusta.
	var v_switch_killer := LobbyManager._validate_character_selection(1, 8)
	if not v_switch_killer["ok"]:
		failures.append("Un peer dev debería poder elegir Jevil_Test (killer) desde survivor: %s" % v_switch_killer)
	elif String(LobbyManager.players[1].get("assigned_role", "")) != "killer":
		failures.append("El rol no se ajustó a killer al elegir Jevil_Test")

	var v_switch_survivor := LobbyManager._validate_character_selection(1, 6)
	if not v_switch_survivor["ok"]:
		failures.append("Un peer dev debería poder elegir Susie_LMS (survivor) desde killer: %s" % v_switch_survivor)
	elif String(LobbyManager.players[1].get("assigned_role", "")) != "survivor":
		failures.append("El rol no se ajustó a survivor al elegir Susie_LMS")

	LobbyManager.players = {
		1: {"name": "Dev", "assigned_role": "survivor", "character_id": -1},
	}
	var v_solo := LobbyManager._validate_character_selection(1, 8)
	if not v_solo["ok"]:
		failures.append("En dev solo debería permitirse cambiar a killer: %s" % v_solo)
	elif String(LobbyManager.players[1].get("assigned_role", "")) != "killer":
		failures.append("El rol solo dev no se ajustó a killer")

	LobbyManager.players.clear()
	LobbyManager.dev_peers.clear()

	# Regresión: resolve_emote_slot no debe acceder a .echo en eventos de mando.
	var input_component := PlayerInputComponent.new()
	add_child(input_component)
	var pad_back := InputEventJoypadButton.new()
	pad_back.pressed = true
	pad_back.button_index = JOY_BUTTON_BACK
	if input_component.resolve_emote_slot(pad_back) != -1:
		failures.append("Select/Back no debería resolver un slot de emote")
	var pad_up := InputEventJoypadButton.new()
	pad_up.pressed = true
	pad_up.button_index = JOY_BUTTON_DPAD_UP
	if input_component.resolve_emote_slot(pad_up) != 0:
		failures.append("DPAD arriba debería resolver el slot de emote 0")
	input_component.queue_free()

	# ── Sandbox dev solo (GameStateService) ──
	var gs = load("res://services/GameStateService.gd").new()
	add_child(gs)
	var fake_timer := FakeTimer.new()
	gs._timer_service = fake_timer

	LobbyManager.players = {
		1: {"name": "Dev", "assigned_role": "killer", "character_id": -1, "is_spectator": false},
	}
	if not gs._is_dev_solo():
		failures.append("_is_dev_solo debería ser true con 1 jugador")
	gs._start_timer()
	if not is_equal_approx(fake_timer.duration, 600.0):
		failures.append("El temporizador dev solo debería ser 600s, es %.1f" % fake_timer.duration)
	gs._evaluate_match()
	if fake_timer.stopped:
		failures.append("_evaluate_match no debería cerrar la partida en dev solo")

	var fake_health := FakeHealth.new()
	gs._health_service = fake_health
	gs._ending_sequence_started = false
	gs.evaluate_sudden_death_condition()
	if gs._ending_sequence_started:
		failures.append("Sudden death no debería activarse en dev solo")
	gs._health_service = null
	fake_health.free()

	LobbyManager.players[2] = {"name": "Otro", "assigned_role": "survivor", "character_id": -1, "is_spectator": false}
	if gs._is_dev_solo():
		failures.append("_is_dev_solo debería ser false con 2 jugadores")

	LobbyManager.players = {
		1: {"name": "Dev", "assigned_role": "killer", "character_id": -1, "is_spectator": false},
		2: {"name": "Spec", "assigned_role": "spectator", "character_id": -1, "is_spectator": true},
	}
	if not gs._is_dev_solo():
		failures.append("_is_dev_solo debería ser true con 1 jugador + 1 espectador")

	gs._timer_service = null
	gs.queue_free()
	fake_timer.free()
	LobbyManager.players.clear()

	# ── Clamps de TP y stamina para el DevMenu ──
	var test_char: CharacterData = CharacterRegistry.get_character(8)
	var tp_test = load("res://services/TPService.gd").new()
	add_child(tp_test)
	tp_test._tp[1] = 10.0
	tp_test._character_data[1] = test_char
	tp_test.dev_set_tp(1, 99999.0)
	if not is_equal_approx(tp_test.get_tp_for_peer(1), test_char.tp_max):
		failures.append("dev_set_tp no clampeó al máximo")
	tp_test.queue_free()

	var stam_test = load("res://services/StaminaService.gd").new()
	add_child(stam_test)
	stam_test._stamina[1] = 10.0
	stam_test._character_data[1] = test_char
	stam_test._exhausted[1] = 0.0
	stam_test.dev_set_stamina(1, 99999.0)
	if not is_equal_approx(stam_test.get_stamina(1), test_char.stamina_max):
		failures.append("dev_set_stamina no clampeó al máximo")
	stam_test.queue_free()

	var packed := load("res://ui/GameUI/Scenes/CharacterSelect.tscn") as PackedScene
	if packed == null:
		failures.append("No se pudo cargar CharacterSelect.tscn")
	else:
		var screen := packed.instantiate()
		add_child(screen)
		await get_tree().process_frame
		await get_tree().process_frame

		var dev_panel: Control = screen.get("_dev_panel")
		if dev_panel == null:
			failures.append("El panel dev (L1 + Select) no se creó")
		if screen.get("_dev_list") == null:
			failures.append("La lista dev no se creó")

		var available: Array = screen.get("available_char_ids")
		for id in available:
			if CharacterRegistry.is_dev_only(int(id)):
				failures.append("ID dev %d presente en el carrusel normal" % int(id))

		var dev_ids: Array = screen.get("_dev_char_ids")
		# El panel dev muestra ambos bandos: los 4 personajes test.
		if dev_ids.size() != 4:
			failures.append("El panel dev debería listar 4 personajes, lista %d" % dev_ids.size())
		if not dev_ids.has(6) or not dev_ids.has(8):
			failures.append("El panel dev no está mostrando ambos bandos: %s" % str(dev_ids))

		# Combo L1 + Select. Simulamos los eventos del mando de PS3.
		if dev_panel:
			var l1 := InputEventJoypadButton.new()
			l1.button_index = JOY_BUTTON_LEFT_SHOULDER
			l1.device = 0
			l1.pressed = true
			screen._input(l1)
			if dev_panel.visible:
				failures.append("L1 solo no debería abrir el panel dev")

			var sel := InputEventJoypadButton.new()
			sel.button_index = JOY_BUTTON_BACK
			sel.device = 0
			sel.pressed = true
			screen._input(sel)
			if not dev_panel.visible:
				failures.append("L1 + Select no abrió el panel dev")

			# Soltar ambos y repetir el combo para cerrarlo.
			l1.pressed = false
			screen._input(l1)
			sel.pressed = false
			screen._input(sel)

			l1.pressed = true
			screen._input(l1)
			sel.pressed = true
			screen._input(sel)
			if dev_panel.visible:
				failures.append("L1 + Select no cerró el panel dev")

			l1.pressed = false
			screen._input(l1)
			sel.pressed = false
			screen._input(sel)

		screen.queue_free()

	# ── DevMenu host-only: construcción y combo ──
	LobbyManager.players = {
		1: {"name": "HostDev", "assigned_role": "killer", "character_id": 8, "is_spectator": false},
	}
	var dev_packed := load("res://ui/InGameMenu/DevMenu.tscn") as PackedScene
	if dev_packed == null:
		failures.append("No se pudo cargar DevMenu.tscn")
	else:
		var dev_menu := dev_packed.instantiate()
		add_child(dev_menu)
		await get_tree().process_frame
		dev_menu.setup(null)

		if dev_menu.is_open():
			failures.append("El DevMenu no debería empezar abierto")
		if not dev_menu.is_in_group(GroupNames.GAME_MENU):
			failures.append("El DevMenu no está en el grupo GAME_MENU")
		if not dev_menu.is_in_group(GroupNames.DEV_MENU):
			failures.append("El DevMenu no está en el grupo DEV_MENU")

		var l1_dev := InputEventJoypadButton.new()
		l1_dev.button_index = JOY_BUTTON_LEFT_SHOULDER
		l1_dev.device = 0
		l1_dev.pressed = true
		dev_menu._input(l1_dev)
		var sel_dev := InputEventJoypadButton.new()
		sel_dev.button_index = JOY_BUTTON_BACK
		sel_dev.device = 0
		sel_dev.pressed = true
		dev_menu._input(sel_dev)
		if not dev_menu.is_open():
			failures.append("L1 + Select no abrió el DevMenu")

		var dev_panel: Control = dev_menu.get("_panel")
		if dev_panel == null or not dev_panel.visible:
			failures.append("El panel del DevMenu no se hizo visible")
		var dev_rows: Array = dev_menu.get("_rows")
		if dev_rows.size() != 8:
			failures.append("El DevMenu debería tener 8 filas, tiene %d" % dev_rows.size())
		var dev_target_label: Label = dev_menu.get("_target_label")
		if dev_target_label == null or not dev_target_label.text.contains("HostDev"):
			failures.append("El DevMenu no listó como objetivo al host")

		l1_dev.pressed = false
		dev_menu._input(l1_dev)
		sel_dev.pressed = false
		dev_menu._input(sel_dev)

		l1_dev.pressed = true
		dev_menu._input(l1_dev)
		sel_dev.pressed = true
		dev_menu._input(sel_dev)
		if dev_menu.is_open():
			failures.append("L1 + Select no cerró el DevMenu")

		l1_dev.pressed = false
		dev_menu._input(l1_dev)
		sel_dev.pressed = false
		dev_menu._input(sel_dev)
		dev_menu.queue_free()
	LobbyManager.players.clear()

	if failures.is_empty():
		print("[DEV SMOKE] OK | normales=%d dev=%d fallback=%s" % [
			normal_count, dev_count, fallback.display_name if fallback else "null"
		])
		get_tree().quit(0)
	else:
		for f in failures:
			push_error("[DEV SMOKE] " + f)
		get_tree().quit(1)
