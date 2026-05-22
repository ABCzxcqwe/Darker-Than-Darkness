# res://services/HealthService.gd
# Gestiona el estado de vida de los survivors.
# Killers son invulnerables — este servicio los ignora.
# Se accede via: GameServiceLocator.get_service("HealthService")
extends Node

signal survivor_died_permanently(peer_id: int)
## Emitida cada vez que cambia la vida de un survivor (daño o curación).
signal health_changed(peer_id: int, current_hp: int, max_hp: int)
## Emitida cuando cambia el estado (alive / downed / dead).
signal player_state_changed(peer_id: int, state: String)

# Estado de vida por peer_id
# { peer_id: { "state": "alive"/"downed"/"dead", "timer": SceneTreeTimer } }
var _states: Dictionary = {}

# ── API pública ────────────────────────────────────────────────────────

func is_alive(peer_id: int) -> bool:
	return _get_state(peer_id) == "alive"

func is_downed(peer_id: int) -> bool:
	return _get_state(peer_id) == "downed"

func is_dead(peer_id: int) -> bool:
	return _get_state(peer_id) == "dead"

func get_player_state(peer_id: int) -> String:
	return _get_state(peer_id)


## Aplica daño a un survivor. Ignora killers.
func take_damage(player_node: Node, amount: int, _attacker_id: int, attack_type: String = "normal") -> void:
	if not multiplayer.is_server():
		return

	var peer_id := player_node.get_multiplayer_authority()

	# Killers son invulnerables
	if player_node.character_data and player_node.character_data.team == "killer":
		return

	if not is_alive(peer_id):
		return

	var now := Time.get_ticks_msec()
	if now < player_node.invincible_until:
		if player_node.character_data and \
		   not attack_type in player_node.character_data.special_defense_against:
			return

	player_node.health -= amount
	player_node.invincible_until = now + int(player_node.character_data.invincibility_frames * 1000)

	print("[HealthService] ", peer_id, " recibió ", amount, " daño | vida: ", player_node.health)

	var revive_svc := GameServiceLocator.get_service("ReviveService")
	if revive_svc:
		revive_svc.cancel_revive(peer_id)

	var max_hp: int = player_node.character_data.max_health if player_node.character_data else 100

	if player_node.health <= 0:
		player_node.health = 0
		_broadcast_health_update(peer_id, 0, max_hp, "downed")
		_down(player_node)
	else:
		_broadcast_health_update(peer_id, player_node.health, max_hp, "alive")
		player_node.rpc("_sync_health", player_node.health, player_node.invincible_until)


## Cura a un survivor. No puede superar max_health.
func heal(player_node: Node, amount: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := player_node.get_multiplayer_authority()
	if not is_alive(peer_id):
		return

	var max_hp: int = player_node.character_data.max_health if player_node.character_data else 100
	var _old_health = player_node.health
	player_node.health = mini(player_node.health + amount, max_hp)

	print("[HealthService] ", peer_id, " curado | vida: ", player_node.health)
	
	_broadcast_health_update(peer_id, player_node.health, max_hp, "alive")
	player_node.rpc("_sync_health", player_node.health, player_node.invincible_until)


## Rescata a un survivor caído.
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
	
	_broadcast_health_update(peer_id, revive_hp, max_hp, "alive")
	player_node.rpc("_sync_state", "alive", revive_hp)


## Remata a un survivor caído instantáneamente.
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


## Registra un jugador al entrar a la partida.
func register(player_node: Node) -> void:
	var peer_id := player_node.get_multiplayer_authority()
	_states[peer_id] = { "state": "alive", "timer": null, "down_count": 0 }
	print("[HealthService] ", peer_id, " registrado con 0 caídas.")


## Limpia un jugador al salir.
func unregister(peer_id: int) -> void:
	_cancel_bleed_timer(peer_id) 
	if _states.has(peer_id):
		_states.erase(peer_id) 
	print("[HealthService] Peer ", peer_id, " eliminado de los estados de salud.")


# ── Internos ───────────────────────────────────────────────────────────

func _down(player_node: Node) -> void:
	var peer_id := player_node.get_multiplayer_authority()
	var max_hp: int = player_node.character_data.max_health if player_node.character_data else 100
	
	# Sumar una caída al historial del jugador
	if _states.has(peer_id):
		_states[peer_id]["down_count"] += 1
	
	# REGLA DE MUERTE AUTOMÁTICA: Si es su segunda caída, muere al instante
	if _states.has(peer_id) and _states[peer_id]["down_count"] >= 2:
		print("[HealthService] 💀 ", peer_id, " cayó por segunda vez. Muerte automática aplicada.")
		_kill(player_node)
		return

	# Si es su primera caída, pasa al estado downed normal (gatear y sangrar)
	player_node.health = 0
	_set_state(peer_id, "downed")

	print("[HealthService] ⚠️ ", peer_id, " ha caído por primera vez!")
	
	_broadcast_health_update(peer_id, 0, max_hp, "downed")
	player_node.rpc("_sync_state", "downed", 0)

	# Notificar al StatusEffectService para reducir su velocidad un 80%
	var fx_svc = GameServiceLocator.get_service("StatusEffectService")
	if fx_svc and fx_svc.has_method("_recalculate_speed"):
		fx_svc._recalculate_speed(peer_id)

	# Iniciar temporizador de desangrado
	var bleed_time: float = player_node.character_data.bleed_out_time \
		if player_node.character_data else 60.0

	var timer := get_tree().create_timer(bleed_time)
	_states[peer_id]["timer"] = timer
	timer.timeout.connect(func():
		if is_downed(peer_id):
			_kill(player_node)
	)
	if multiplayer.is_server():
		var game_state_svc = GameServiceLocator.get_service("GameStateService")
		if game_state_svc:
			game_state_svc.evaluate_sudden_death_condition()


func _kill(player_node: Node) -> void:
	var peer_id := player_node.get_multiplayer_authority()
	var max_hp: int = player_node.character_data.max_health if player_node.character_data else 100
	
	_set_state(peer_id, "dead")

	print("[HealthService] 💀 ", peer_id, " ha muerto.")
	
	_broadcast_health_update(peer_id, 0, max_hp, "dead")
	player_node.rpc("_sync_state", "dead", 0)
	survivor_died_permanently.emit(peer_id)

	await get_tree().process_frame
	if is_instance_valid(player_node):
		player_node.queue_free()


func _cancel_bleed_timer(peer_id: int) -> void:
	if _states.has(peer_id) and _states[peer_id]["timer"] != null:
		_states[peer_id]["timer"] = null


func _get_state(peer_id: int) -> String:
	if not _states.has(peer_id):
		return "alive"
	return _states[peer_id]["state"]


func _set_state(peer_id: int, state: String) -> void:
	if not _states.has(peer_id):
		_states[peer_id] = { "state": state, "timer": null, "down_count": 0 }
	else:
		_states[peer_id]["state"] = state


func _exit_tree() -> void:
	_states.clear()
	print("[HealthService] Limpiado.")


# ── Sincronización para todos los clientes ─────────────────────────────

func _broadcast_health_update(peer_id: int, current_hp: int, max_hp: int, state: String) -> void:
	# Emitir señal local para el HUD del servidor
	health_changed.emit(peer_id, current_hp, max_hp)
	player_state_changed.emit(peer_id, state)
	
	# Enviar RPC a TODOS los clientes para actualizar sus paneles
	rpc("_sync_global_health", peer_id, current_hp, max_hp, state)


@rpc("authority", "reliable", "call_local")
func _sync_global_health(peer_id: int, current_hp: int, max_hp: int, state: String) -> void:
	# Esto se ejecuta en TODOS los clientes
	print("[Global Sync] Jugador %d: HP=%d/%d, Estado=%s" % [peer_id, current_hp, max_hp, state])
	
	# Emitir señales locales para que los HUDs se actualicen
	health_changed.emit(peer_id, current_hp, max_hp)
	player_state_changed.emit(peer_id, state)
	

func check_all_survivors_incapacitated() -> bool:
	if not multiplayer.is_server():
		return false
	var total_survivors := 0
	var incapacitated_survivors := 0
	for peer_id in NetworkManager.players.keys():
		var player_data = NetworkManager.players[peer_id]
		# Corregido: Usamos "assigned_role" para coincidir con tu GameStateService
		if player_data.get("assigned_role") == "survivor":
			total_survivors += 1
			
			var downed: bool = is_downed(peer_id)
			var dead_state: bool = is_dead(peer_id)
			
			# Doble verificación por si el nodo ya fue purgado del árbol
			var player_node = get_tree().root.find_child(str(peer_id), true, false)
			var permanent_death: bool = dead_state or not is_instance_valid(player_node)
			if downed or permanent_death:
				incapacitated_survivors += 1
	return total_survivors > 0 and incapacitated_survivors == total_survivors
