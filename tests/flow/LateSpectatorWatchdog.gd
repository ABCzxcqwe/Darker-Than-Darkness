# res://tests/flow/LateSpectatorWatchdog.gd
# Verifica que un peer conectado a mitad de partida, en modo espectador, reciba
# el delta continuo de posición (net_position) del Synchronizer del servidor.
extends Node

const SAMPLE_SECONDS := 8.0
const SAMPLE_INTERVAL := 0.5


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	if not await _wait_until(func() -> bool:
		return _scene_name() == "Session", 20.0):
		_fail("no llegó a la escena Session (late join)")
		return
	if not await _wait_until(func() -> bool:
		return LobbyManager.current_phase == LobbyManager.GamePhase.PLAYING, 20.0):
		_fail("el cliente tardío no entró en fase PLAYING")
		return

	var my_id := multiplayer.get_unique_id()
	print("[LateSpec] conectado en partida. peer=", my_id,
			" rol=", LobbyManager.players.get(my_id, {}).get("assigned_role", "?"))

	# Esperar un rato en el hub antes de espectar (flujo real: el jugador se une
	# a mitad de partida y se queda mirando el hub hasta que pulsa ESPECTAR).
	# Esto expone la race condition: el servidor ya otorgó visibilidad al peer
	# cuando todavía no existía su World.
	var hub_wait := float(OS.get_environment("LATE_HUB_WAIT")) if OS.has_environment("LATE_HUB_WAIT") else 6.0
	if hub_wait > 0.0:
		print("[LateSpec] esperando %.1fs en el hub antes de espectar" % hub_wait)
		await get_tree().create_timer(hub_wait).timeout

	# request_spectate() puede devolver false mientras llega el snapshot del roster.
	var spectating := false
	var waited := 0.0
	while not spectating and waited < 12.0:
		spectating = MatchCoordinator.request_spectate()
		if not spectating:
			await get_tree().create_timer(0.25).timeout
			waited += 0.25
	if not spectating:
		_fail("request_spectate() nunca devolvió true")
		return
	print("[LateSpec] espectando")

	var world := _world()
	if world == null:
		_fail("no hay World tras espectar")
		return

	# Nodos de jugador del World (cada hijo directo es un peer).
	var targets: Array = []
	var spawn_wait := 0.0
	while targets.is_empty() and spawn_wait < 8.0:
		for child in world.get_children():
			if child is CharacterBody2D and child.has_method("get_multiplayer_authority"):
				targets.append(child)
		if targets.is_empty():
			await get_tree().create_timer(0.1).timeout
			spawn_wait += 0.1
	if targets.is_empty():
		_fail("el World no tiene nodos de jugador")
		return
	var desc := []
	for t in targets:
		desc.append("%s(owner=%d)" % [t.name, t.get_multiplayer_authority()])
	print("[LateSpec] objetivos: ", ", ".join(desc))

	# Esperar a que llegue el primer estado (snap inicial) antes de muestrear.
	await get_tree().create_timer(0.6).timeout

	var samples := {}
	for t in targets:
		samples[t.name] = []
	var elapsed := 0.0
	while elapsed < SAMPLE_SECONDS:
		await get_tree().create_timer(SAMPLE_INTERVAL).timeout
		elapsed += SAMPLE_INTERVAL
		for t in targets:
			if is_instance_valid(t):
				samples[t.name].append(t.net_position)
		print("[LateSpec] t=%.1f %s" % [elapsed, _summary(targets)])

	var ok := true
	for name in samples:
		var distinct := {}
		for s in samples[name]:
			distinct[str(s)] = true
		print("[LateSpec] peer=%s muestras=%d distintas=%d" % [
			name, samples[name].size(), distinct.size()
		])
		if distinct.size() < 3:
			ok = false

	if not ok:
		_fail("net_position NO se replicó para algún jugador: el Synchronizer no manda delta")
		return

	print("[LateSpec] LATE SPECTATOR SYNC OK")
	get_tree().quit(0)


func _summary(targets: Array) -> String:
	var parts := []
	for t in targets:
		if is_instance_valid(t):
			parts.append("%s=%s" % [t.name, str(t.net_position)])
	return " ".join(parts)


func _world() -> Node:
	if MatchCoordinator.current_game_manager == null \
			or not is_instance_valid(MatchCoordinator.current_game_manager):
		return null
	if not MatchCoordinator.current_game_manager.has_method("get_world_instance"):
		return null
	return MatchCoordinator.current_game_manager.get_world_instance()


func _scene_name() -> String:
	var scene := get_tree().current_scene
	return scene.name if scene else ""


func _wait_until(condition: Callable, timeout: float) -> bool:
	var elapsed := 0.0
	while not condition.call():
		if elapsed >= timeout:
			return false
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return true


func _fail(message: String) -> void:
	push_error("[LateSpec] FAIL: " + message)
	get_tree().quit(1)
