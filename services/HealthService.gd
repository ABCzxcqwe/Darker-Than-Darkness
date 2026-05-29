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

## Tipos de protección genérica.
enum ProtectionType {
	DAMAGE_SHARE,    # Divide el daño entre dos jugadores
	DAMAGE_REDUCE,   # Reduce daño por porcentaje
	DEATH_SHIELD     # Una vez: evita muerte, deja en 1 HP
}

# Estado de vida por peer_id
# { peer_id: { "state": "alive"/"downed"/"dead", "timer": SceneTreeTimer } }
var _states: Dictionary = {}

# Protecciones registradas
# { protected_peer_id: [{ protector_id, type: ProtectionType, params: Dictionary }] }
var _protections: Dictionary = {}

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
 
	# ── Protecciones genéricas ──────────────────────────────────────────
	# Procesa daño compartido, reducción y escudos anti-muerte.
	amount = _apply_protections(peer_id, player_node, amount)
 
	player_node.health -= amount
	player_node.invincible_until = now + int(player_node.character_data.invincibility_frames * 1000)
 
	print("[HealthService] ", peer_id, " recibió ", amount, " daño | vida: ", player_node.health)
 
	var revive_svc = GameServiceLocator.get_service("ReviveService")
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
		var timer := _states[peer_id]["timer"] as Timer
		if timer:
			timer.stop()
			timer.queue_free()
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

# ── API de protecciones genéricas ─────────────────────────────────────

## Registra una protección para un jugador.
## @param protected_id: quien recibe el beneficio
## @param protector_id: quien provee la protección (puede ser el mismo)
## @param type: ProtectionType
## @param params: { "share_pct": 0.5 } para DAMAGE_SHARE,
##                { "reduction_pct": 0.5 } para DAMAGE_REDUCE,
##                {} para DEATH_SHIELD
func register_protection(protected_id: int, protector_id: int, type: int, params: Dictionary = {}) -> void:
	if not _protections.has(protected_id):
		_protections[protected_id] = []
	_protections[protected_id].append({
		"protector_id": protector_id,
		"type": type,
		"params": params
	})


## Elimina una protección específica.
func unregister_protection(protected_id: int, protector_id: int, type: int) -> void:
	if not _protections.has(protected_id):
		return
	_protections[protected_id] = _protections[protected_id].filter(
		func(p): return not (p.protector_id == protector_id and p.type == type)
	)
	if _protections[protected_id].is_empty():
		_protections.erase(protected_id)


## Elimina todas las protecciones de un protector (ej. al expirar duración).
func unregister_all_for_protector(protector_id: int) -> void:
	for protected_id in _protections.keys():
		_protections[protected_id] = _protections[protected_id].filter(
			func(p): return p.protector_id != protector_id
		)
		if _protections[protected_id].is_empty():
			_protections.erase(protected_id)


## Procesa todas las protecciones activas para un jugador.
## Retorna el monto de daño modificado después de aplicar protecciones.
func _apply_protections(peer_id: int, player_node: Node, amount: int) -> int:
	if not _protections.has(peer_id):
		return amount

	var current_hp: int = player_node.health

	# Si ya está en 1 HP, las protecciones no aplican
	if current_hp <= 1:
		_protections.erase(peer_id)
		return amount

	var final_amount: int = amount
	var has_death_shield: bool = false

	for p in _protections[peer_id]:
		match p.type:
			ProtectionType.DEATH_SHIELD:
				has_death_shield = true

			ProtectionType.DAMAGE_REDUCE:
				var reduction: float = p.params.get("reduction_pct", 0.5)
				final_amount = ceil(final_amount * (1.0 - reduction))

			ProtectionType.DAMAGE_SHARE:
				var share_pct: float = p.params.get("share_pct", 0.5)
				var shared: int = ceil(final_amount * share_pct)

				var protector: Node = _find_player_node_by_peer_id(p.protector_id)
				if not is_instance_valid(protector) or not is_alive(p.protector_id):
					continue

				var protector_hp: int = protector.health
				if protector_hp <= 1:
					continue

				# Aplicar daño compartido al protector (mínimo 1 HP)
				var new_hp: int = max(1, protector_hp - shared)
				protector.health = new_hp

				var max_hp_p: int = protector.character_data.max_health \
					if protector.character_data else 100
				_broadcast_health_update(p.protector_id, new_hp, max_hp_p, "alive")

				final_amount = max(0, final_amount - shared)

	# Escudo anti-muerte al final (después de reducciones)
	if has_death_shield and current_hp - final_amount <= 0 and current_hp > 1:
		return current_hp - 1

	return final_amount


func _find_player_node_by_peer_id(peer_id: int) -> Node:
	return get_tree().root.find_child(str(peer_id), true, false)

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
