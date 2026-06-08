extends Node

signal survivor_died_permanently(peer_id: int)
signal health_changed(peer_id: int, current_hp: int, max_hp: int)
signal player_state_changed(peer_id: int, state: String)

var _states: Dictionary = {}
var _permanently_dead: Dictionary = {}

func is_alive(peer_id: int) -> bool:
	return _get_state(peer_id) == "alive"

func is_downed(peer_id: int) -> bool:
	return _get_state(peer_id) == "downed"

func is_dead(peer_id: int) -> bool:
	return _get_state(peer_id) == "dead"

func get_player_state(peer_id: int) -> String:
	return _get_state(peer_id)

func take_damage(player_node: Node, amount: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := player_node.get_multiplayer_authority()
	if not is_alive(peer_id):
		return

	if player_node.character_data and player_node.character_data.team == "killer":
		return

	player_node.health -= amount

	print("[HealthService] ", peer_id, " recibió ", amount, " daño | vida: ", player_node.health)

	var revive_svc = GameServiceLocator.get_service("ReviveService")
	if revive_svc:
		revive_svc.cancel_revive(peer_id)

	if player_node.state != 0:
		var combat = GameServiceLocator.get_service("CombatMediator")
		if combat:
			combat.remove_root(player_node)
		player_node.reset_ability_state()
		if is_instance_valid(player_node):
			player_node.rpc("_sync_cancel_ability")
		print("[HealthService] Habilidad cancelada en peer ", peer_id, " por recibir daño.")

	var max_hp: int = player_node.character_data.max_health if player_node.character_data else 100

	if player_node.health <= 0:
		player_node.health = 0
		broadcast_health_update(peer_id, 0, max_hp, "downed")
		_down(player_node)
	else:
		broadcast_health_update(peer_id, player_node.health, max_hp, "alive")
		if is_instance_valid(player_node):
			player_node.rpc("_sync_health", player_node.health, player_node.invincible_until)


func heal(player_node: Node, amount: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := player_node.get_multiplayer_authority()
	if not is_alive(peer_id):
		return

	var max_hp: int = player_node.character_data.max_health if player_node.character_data else 100
	player_node.health = mini(player_node.health + amount, max_hp)

	print("[HealthService] ", peer_id, " curado | vida: ", player_node.health)

	broadcast_health_update(peer_id, player_node.health, max_hp, "alive")
	if is_instance_valid(player_node):
		player_node.rpc("_sync_health", player_node.health, player_node.invincible_until)


func revive(player_node: Node) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := player_node.get_multiplayer_authority()
	if not is_downed(peer_id):
		return

	_cancel_bleed_timer(peer_id)

	var revive_hp: int = player_node.character_data.revive_health if player_node.character_data else 60
	var max_hp: int = player_node.character_data.max_health if player_node.character_data else 100

	player_node.health = revive_hp
	_set_state(peer_id, "alive")

	print("[HealthService] ", peer_id, " rescatado | vida: ", revive_hp)

	broadcast_health_update(peer_id, revive_hp, max_hp, "alive")
	if is_instance_valid(player_node):
		player_node.rpc("_sync_state", "alive", revive_hp)


func execute(player_node: Node) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := player_node.get_multiplayer_authority()
	if not is_downed(peer_id):
		return

	if player_node.character_data and not player_node.character_data.can_be_executed:
		return

	_cancel_bleed_timer(peer_id)
	_kill(player_node)


func register(player_node: Node) -> void:
	var peer_id := player_node.get_multiplayer_authority()
	_states[peer_id] = { "state": "alive", "timer": null, "down_count": 0 }
	print("[HealthService] ", peer_id, " registrado con 0 caídas.")


func unregister(peer_id: int) -> void:
	_cancel_bleed_timer(peer_id)
	_permanently_dead.erase(peer_id)
	if _states.has(peer_id):
		_states.erase(peer_id)
	print("[HealthService] Peer ", peer_id, " eliminado de los estados de salud.")


func _down(player_node: Node) -> void:
	var peer_id := player_node.get_multiplayer_authority()
	var max_hp: int = player_node.character_data.max_health if player_node.character_data else 100

	if _states.has(peer_id):
		_states[peer_id]["down_count"] += 1

	if _states.has(peer_id) and _states[peer_id]["down_count"] >= 2:
		print("[HealthService] Peer ", peer_id, " cayó por segunda vez. Muerte automática aplicada.")
		_kill(player_node)
		return

	var alive_survivor_count := 0
	for pid in NetworkManager.players.keys():
		if NetworkManager.players[pid].get("assigned_role") == "survivor" and is_alive(pid):
			alive_survivor_count += 1

	if alive_survivor_count <= 1:
		print("[HealthService] Último sobreviviente caído — nadie puede revivirlo. Fin del juego.")
		_kill(player_node)
		return

	player_node.health = 0
	_set_state(peer_id, "downed")

	print("[HealthService] ", peer_id, " ha caído por primera vez!")

	broadcast_health_update(peer_id, 0, max_hp, "downed")
	if is_instance_valid(player_node):
		player_node.rpc("_sync_state", "downed", 0)

	var fx_svc = GameServiceLocator.get_service("StatusEffectService")
	if fx_svc and fx_svc.has_method("_recalculate_speed"):
		fx_svc._recalculate_speed(peer_id)

	var bleed_time: float = player_node.character_data.bleed_out_time \
		if player_node.character_data else 60.0

	var timer := Timer.new()
	timer.wait_time = bleed_time
	timer.one_shot = true
	timer.timeout.connect(func():
		if is_downed(peer_id):
			_kill(player_node)
	)
	add_child(timer)
	timer.start()
	_states[peer_id]["timer"] = timer

	var game_state_svc = GameServiceLocator.get_service("GameStateService")
	if game_state_svc:
		game_state_svc.evaluate_sudden_death_condition()


func _kill(player_node: Node) -> void:
	var peer_id := player_node.get_multiplayer_authority()
	var max_hp: int = player_node.character_data.max_health if player_node.character_data else 100

	_set_state(peer_id, "dead")
	_permanently_dead[peer_id] = true

	print("[HealthService] ", peer_id, " ha muerto.")

	broadcast_health_update(peer_id, 0, max_hp, "dead")
	survivor_died_permanently.emit(peer_id)

	var cd = GameServiceLocator.get_service("CooldownService")
	if cd and cd.has_method("clear_player"):
		cd.clear_player(peer_id)
		print("[HealthService] Cooldowns limpiados para peer ", peer_id, " al morir.")

	await get_tree().process_frame
	if is_instance_valid(player_node):
		player_node.rpc("_sync_state", "dead", 0)
		player_node.queue_free()


func _cancel_bleed_timer(peer_id: int) -> void:
	if _states.has(peer_id) and _states[peer_id]["timer"] != null:
		var timer := _states[peer_id]["timer"] as Timer
		if timer:
			timer.stop()
			timer.queue_free()
		_states[peer_id]["timer"] = null


func _get_state(peer_id: int) -> String:
	if _permanently_dead.has(peer_id):
		return "dead"
	if not _states.has(peer_id):
		return "alive"
	return _states[peer_id]["state"]


func _set_state(peer_id: int, state: String) -> void:
	if not _states.has(peer_id):
		_states[peer_id] = { "state": state, "timer": null, "down_count": 0 }
	else:
		_states[peer_id]["state"] = state


func broadcast_health_update(peer_id: int, current_hp: int, max_hp: int, state: String) -> void:
	health_changed.emit(peer_id, current_hp, max_hp)
	player_state_changed.emit(peer_id, state)
	rpc("_sync_global_health", peer_id, current_hp, max_hp, state)


@rpc("authority", "reliable", "call_local")
func _sync_global_health(peer_id: int, current_hp: int, max_hp: int, state: String) -> void:
	print("[Global Sync] Jugador %d: HP=%d/%d, Estado=%s" % [peer_id, current_hp, max_hp, state])
	health_changed.emit(peer_id, current_hp, max_hp)
	player_state_changed.emit(peer_id, state)


func check_all_survivors_incapacitated() -> bool:
	if not multiplayer.is_server():
		return false
	var total_survivors := 0
	var incapacitated_survivors := 0
	for peer_id in NetworkManager.players.keys():
		var player_data = NetworkManager.players[peer_id]
		if player_data.get("assigned_role") == "survivor":
			total_survivors += 1
			var downed: bool = is_downed(peer_id)
			var dead_state: bool = is_dead(peer_id)
			var player_node = get_tree().root.find_child(str(peer_id), true, false)
			var permanent_death: bool = dead_state or not is_instance_valid(player_node)
			if downed or permanent_death:
				incapacitated_survivors += 1
	return total_survivors > 0 and incapacitated_survivors == total_survivors


func _exit_tree() -> void:
	_states.clear()
	print("[HealthService] Limpiado.")
