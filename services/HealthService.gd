# res://services/HealthService.gd
# Gestiona el estado de vida de los survivors.
# Killers son invulnerables — este servicio los ignora.
# Se accede via: GameServiceLocator.get_service("HealthService")
extends Node

signal survivor_died_permanently(peer_id: int)
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


## Aplica daño a un survivor. Ignora killers.
func take_damage(player_node: Node, amount: int, _attacker_id: int, attack_type: String = "normal") -> void:
	if not multiplayer.is_server():
		return

	var peer_id := player_node.get_multiplayer_authority()

	# Killers son invulnerables
	if player_node.character_data and player_node.character_data.team == "killer":
		return

	# Solo survivors vivos reciben daño normal
	if not is_alive(peer_id):
		return

	# Verificar iframes
	var now := Time.get_ticks_msec()
	if now < player_node.invincible_until:
		if player_node.character_data and \
		   not attack_type in player_node.character_data.special_defense_against:
			return

	# Aplicar daño
	player_node.health -= amount
	player_node.invincible_until = now + int(player_node.character_data.invincibility_frames * 1000)

	print("[HealthService] ", peer_id, " recibió ", amount, " daño | vida: ", player_node.health)

	# Cancelar rescate si estaba rescatando a alguien
	var revive_svc := GameServiceLocator.get_service("ReviveService")
	if revive_svc:
		revive_svc.cancel_revive(peer_id)

	# Sincronizar vida a todos los clientes
	player_node.rpc("_sync_health", player_node.health, player_node.invincible_until)

	# ¿Cae?
	if player_node.health <= 0:
		_down(player_node)


## Cura a un survivor. No puede superar max_health.
func heal(player_node: Node, amount: int) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := player_node.get_multiplayer_authority()
	if not is_alive(peer_id):
		return

	var max_hp: int = player_node.character_data.max_health if player_node.character_data else 100
	player_node.health = mini(player_node.health + amount, max_hp)

	print("[HealthService] ", peer_id, " curado | vida: ", player_node.health)
	player_node.rpc("_sync_health", player_node.health, player_node.invincible_until)


## Rescata a un survivor caído.
func revive(player_node: Node) -> void:
	if not multiplayer.is_server():
		return

	var peer_id := player_node.get_multiplayer_authority()
	if not is_downed(peer_id):
		return

	# Cancelar temporizador de desangrado
	_cancel_bleed_timer(peer_id)

	var revive_hp: int = player_node.character_data.revive_health if player_node.character_data else 60
	player_node.health = revive_hp
	_set_state(peer_id, "alive")

	print("[HealthService] ", peer_id, " rescatado | vida: ", revive_hp)
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
	_states[peer_id] = { "state": "alive", "timer": null }
	print("[HealthService] ", peer_id, " registrado.")


## Limpia un jugador al salir.
func unregister(peer_id: int) -> void:
	_cancel_bleed_timer(peer_id) 
	if _states.has(peer_id):
		_states.erase(peer_id) 
	print("[HealthService] Peer ", peer_id, " eliminado de los estados de salud.")

# ── Internos ───────────────────────────────────────────────────────────

func _down(player_node: Node) -> void:
	var peer_id := player_node.get_multiplayer_authority()
	player_node.health = 0
	_set_state(peer_id, "downed")

	print("[HealthService] ", peer_id, " ha caído.")
	player_node.rpc("_sync_state", "downed", 0)

	# Iniciar temporizador de desangrado
	var bleed_time: float = player_node.character_data.bleed_out_time \
		if player_node.character_data else 60.0

	var timer := get_tree().create_timer(bleed_time)
	_states[peer_id]["timer"] = timer
	timer.timeout.connect(func():
		# Verificar que siga caído (puede haber sido rescatado)
		if is_downed(peer_id):
			_kill(player_node)
	)


func _kill(player_node: Node) -> void:
	var peer_id := player_node.get_multiplayer_authority()
	_set_state(peer_id, "dead")

	print("[HealthService] ", peer_id, " ha muerto.")
	player_node.rpc("_sync_state", "dead", 0)

	# NUEVO: Avisamos al Servidor que este superviviente quedó fuera de juego por completo
	survivor_died_permanently.emit(peer_id)

	# Dar un frame para que el RPC llegue antes de queue_free
	await get_tree().process_frame
	if is_instance_valid(player_node):
		player_node.queue_free()


func _cancel_bleed_timer(peer_id: int) -> void:
	if _states.has(peer_id) and _states[peer_id]["timer"] != null:
		# SceneTreeTimer no se puede cancelar directamente,
		# pero al cambiar el estado el callback lo ignora.
		_states[peer_id]["timer"] = null


func _get_state(peer_id: int) -> String:
	if not _states.has(peer_id):
		return "alive"  # default seguro
	return _states[peer_id]["state"]


func _set_state(peer_id: int, state: String) -> void:
	if not _states.has(peer_id):
		_states[peer_id] = { "state": state, "timer": null }
	else:
		_states[peer_id]["state"] = state


func _exit_tree() -> void:
	_states.clear()
	print("[HealthService] Limpiado.")
