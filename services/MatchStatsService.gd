# res://services/MatchStatsService.gd
# Rastrea estadísticas de la partida por jugador (server-authoritative).
#
# Alimenta dos sistemas:
#   1. Pantalla de estadísticas finales (snapshot vía GameStateService._go_to_stats).
#   2. Carga del ultimate Rage del killer (progreso por stuns recibidos).
#
# TODO el tracking corre solo en el servidor; los clientes consultan vía RPC/snapshot.
extends Node

signal stuns_received_changed(peer_id: int, total: int)
signal rage_charge_changed(peer_id: int, charged: bool, progress: int, required: int)

## Intervalo del tick que acumula tiempo en peligro (segundos).
const DANGER_TICK_INTERVAL: float = 1.0
## Slot del ultimate Rage en ability_slots del CharacterData del killer.
const RAGE_SLOT_INDEX: int = 4

var _client_relay: Node = null
# Inyectado automáticamente por GameServiceLocator (convención _combat_mediator).
var _combat_mediator: Node = null

# { peer_id: Dictionary de estadísticas } — ver register_player().
var _stats: Dictionary = {}
# Carga del ultimate Rage por killer: { peer_id: { "progress": int, "charged": bool } }
var _rage_charge: Dictionary = {}

var _danger_timer: Timer = null


func set_client_relay(relay: Node) -> void:
	_client_relay = relay


func _ready() -> void:
	if not multiplayer.is_server():
		return
	# La conexión se difiere porque la inyección de dependencias ocurre
	# después de que todos los servicios fueron creados.
	_connect_combat_signals.call_deferred()
	rage_charge_changed.connect(_on_rage_charge_changed)

	_danger_timer = Timer.new()
	_danger_timer.wait_time = DANGER_TICK_INTERVAL
	_danger_timer.autostart = true
	_danger_timer.timeout.connect(_on_danger_tick)
	add_child(_danger_timer)


func _connect_combat_signals() -> void:
	var combat = _combat_mediator
	if not combat:
		combat = GameServiceLocator.combat_mediator
	if not combat:
		push_warning("[MatchStatsService] CombatMediator no disponible; sin tracking de combate.")
		return
	if not combat.damage_dealt.is_connected(_on_damage_dealt):
		combat.damage_dealt.connect(_on_damage_dealt)
	if not combat.stun_applied.is_connected(_on_stun_applied):
		combat.stun_applied.connect(_on_stun_applied)
	if combat.has_signal("stun_applied_by") and not combat.stun_applied_by.is_connected(_on_stun_applied_by):
		combat.stun_applied_by.connect(_on_stun_applied_by)

	var health_svc = GameServiceLocator.health
	if health_svc and health_svc.has_signal("survivor_died_permanently"):
		if not health_svc.survivor_died_permanently.is_connected(_on_survivor_died):
			health_svc.survivor_died_permanently.connect(_on_survivor_died)


# ════════════════════════════════════════════════════════════════════════════
# REGISTRO DE JUGADORES (llamado por PlayerLifecycleManager)
# ════════════════════════════════════════════════════════════════════════════

func register_player(peer_id: int, _data: Resource = null) -> void:
	if not multiplayer.is_server():
		return
	_stats[peer_id] = {
		"kills": 0,
		"damage_dealt": 0,
		"damage_taken": 0,
		"stuns_received": 0,
		"stuns_received_times": [],
		"stuns_applied": 0,
		"time_in_danger": 0.0,
	}
	print("[MatchStatsService] Jugador ", peer_id, " registrado.")


func unregister_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_stats.erase(peer_id)
	_rage_charge.erase(peer_id)


## Limpia todo el estado. Llamar al terminar la partida si se reutiliza el servicio.
func reset() -> void:
	_stats.clear()
	_rage_charge.clear()


# ════════════════════════════════════════════════════════════════════════════
# HANDLERS DE SEÑALES DE COMBATE
# ════════════════════════════════════════════════════════════════════════════

func _on_damage_dealt(attacker_id: int, target_id: int, final_damage: int, _attack_type: String) -> void:
	if attacker_id > 0 and _stats.has(attacker_id):
		_stats[attacker_id]["damage_dealt"] += final_damage
	if _stats.has(target_id):
		_stats[target_id]["damage_taken"] += final_damage


func _on_stun_applied(target_id: int, _duration: float) -> void:
	if not _stats.has(target_id):
		return
	var entry: Dictionary = _stats[target_id]
	entry["stuns_received"] += 1
	entry["stuns_received_times"].append(Time.get_ticks_msec() / 1000.0)
	stuns_received_changed.emit(target_id, entry["stuns_received"])
	_update_rage_progress(target_id)


## Señal opcional con atacante (ver CombatMediator.stun_applied_by).
func _on_stun_applied_by(attacker_id: int, _target_id: int, _duration: float) -> void:
	if attacker_id > 0 and _stats.has(attacker_id):
		_stats[attacker_id]["stuns_applied"] += 1


## Muerte permanente de un survivor → cuenta como kill del killer actual.
func _on_survivor_died(_victim_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var killer_node := _find_killer_node()
	if not is_instance_valid(killer_node):
		return
	var killer_peer: int = killer_node.get_multiplayer_authority()
	if _stats.has(killer_peer):
		_stats[killer_peer]["kills"] = int(_stats[killer_peer].get("kills", 0)) + 1


# ════════════════════════════════════════════════════════════════════════════
# TIEMPO EN PELIGRO (dentro del chase_radius del killer)
# ════════════════════════════════════════════════════════════════════════════

func _on_danger_tick() -> void:
	if not multiplayer.is_server() or not _is_match_playing():
		return

	var killer_node = _find_killer_node()
	if not is_instance_valid(killer_node) or not killer_node.character_data:
		return

	var chase_radius: float = killer_node.character_data.chase_radius
	var relay = GameServiceLocator.get_client_relay()

	for s in get_tree().get_nodes_in_group("survivor"):
		if not is_instance_valid(s):
			continue
		if "health_state" in s and s.health_state != "alive":
			continue
		var pid: int = s.get_multiplayer_authority()
		if relay and relay.has_player_escaped(pid):
			continue
		if s.global_position.distance_to(killer_node.global_position) <= chase_radius:
			if _stats.has(pid):
				_stats[pid]["time_in_danger"] += DANGER_TICK_INTERVAL


func _is_match_playing() -> bool:
	var state = GameServiceLocator.game_state
	return state != null and state.is_in_game()


func _find_killer_node() -> Node:
	for p in get_tree().get_nodes_in_group("killer"):
		return p
	return null


# ════════════════════════════════════════════════════════════════════════════
# CARGA DEL ULTIMATE RAGE
# ════════════════════════════════════════════════════════════════════════════

## Acumula progreso cuando el killer recibe un stun. El umbral se lee de
## ability_slots[RAGE_SLOT_INDEX].rage_stuns_required del CharacterData.
func _update_rage_progress(killer_peer_id: int) -> void:
	var required := _get_rage_stuns_required(killer_peer_id)
	if required <= 0:
		return

	if not _rage_charge.has(killer_peer_id):
		_rage_charge[killer_peer_id] = { "progress": 0, "charged": false }

	var charge: Dictionary = _rage_charge[killer_peer_id]
	if charge["charged"]:
		return

	charge["progress"] = int(charge["progress"]) + 1
	var charged: bool = int(charge["progress"]) >= required
	charge["charged"] = charged
	rage_charge_changed.emit(killer_peer_id, charged, charge["progress"], required)

	if charged:
		print("[MatchStatsService] ¡Ultimate cargado! | peer: ", killer_peer_id,
			  " | stuns: ", charge["progress"], "/", required)


## True si el ultimate está listo para usar.
func has_rage_charge(peer_id: int) -> bool:
	return _rage_charge.get(peer_id, {}).get("charged", false)


## Consume la carga al activar el ultimate. Devuelve false si no había carga.
func consume_rage_charge(peer_id: int) -> bool:
	if not multiplayer.is_server() or not has_rage_charge(peer_id):
		return false
	var required := _get_rage_stuns_required(peer_id)
	_rage_charge[peer_id] = { "progress": 0, "charged": false }
	rage_charge_changed.emit(peer_id, false, 0, required)
	print("[MatchStatsService] Ultimate consumido | peer: ", peer_id)
	return true


## Reenvía el estado de carga del ultimate al cliente dueño (para el HUD).
func _on_rage_charge_changed(peer_id: int, charged: bool, progress: int, required: int) -> void:
	if not _client_relay or not LobbyManager.players.has(peer_id):
		return
	_client_relay.rpc_id(peer_id, "_rpc_rage_state", charged, progress, required)


## Estado actual de carga (para HUD/sync): { "progress": int, "charged": bool, "required": int }
func get_rage_state(peer_id: int) -> Dictionary:
	var required := _get_rage_stuns_required(peer_id)
	var charge: Dictionary = _rage_charge.get(peer_id, { "progress": 0, "charged": false })
	return {
		"progress": int(charge["progress"]),
		"charged": bool(charge["charged"]),
		"required": required,
	}


## DEBUG: fuerza la carga del ultimate sin necesitar stuns reales.
func debug_force_charge(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var required := _get_rage_stuns_required(peer_id)
	if required <= 0:
		required = 1
	_rage_charge[peer_id] = { "progress": required, "charged": true }
	rage_charge_changed.emit(peer_id, true, required, required)
	print("[MatchStatsService] DEBUG: Ultimate forzado | peer: ", peer_id)


## Umbral de stuns para el ultimate del peer. Usa .get() para tolerar
## CharacterData cuyo slot 4 aún no tenga el campo rage_stuns_required.
func _get_rage_stuns_required(peer_id: int) -> int:
	var player = PlayerRegistry.get_player(peer_id)
	if not player or not player.character_data:
		return 0
	var slots: Array = player.character_data.ability_slots
	if slots.size() <= RAGE_SLOT_INDEX:
		return 0
	var rage_data = slots[RAGE_SLOT_INDEX]
	if not rage_data:
		return 0
	var value = rage_data.get("rage_stuns_required")
	return int(value) if value != null else 0


# ════════════════════════════════════════════════════════════════════════════
# SNAPSHOT PARA LA PANTALLA FINAL
# ════════════════════════════════════════════════════════════════════════════

## Diccionario { peer_id: { daño, stuns, tiempo_en_peligro } } para la pantalla
## de estadísticas finales. Se inyecta en stats_data de GameStateService.
func get_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for pid in _stats.keys():
		var e: Dictionary = _stats[pid]
		snapshot[pid] = {
			"kills": e.get("kills", 0),
			"damage_dealt": e["damage_dealt"],
			"damage_taken": e["damage_taken"],
			"stuns_received": e["stuns_received"],
			"stuns_applied": e["stuns_applied"],
			"time_in_danger": snappedf(e["time_in_danger"], 0.1),
		}
	return snapshot


# ════════════════════════════════════════════════════════════════════════════
# STATS IN-GAME (menú de pausa)
# ════════════════════════════════════════════════════════════════════════════

## Pedido del menú de pausa: el servidor responde con las stats del peer que
## pregunta vía ClientRelay._rpc_my_stats.
@rpc("any_peer", "reliable", "call_local")
func request_my_stats() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	_send_stats_to(peer)


func _send_stats_to(peer: int) -> void:
	var relay := _client_relay
	if relay == null:
		relay = GameServiceLocator.get_client_relay()
	if relay == null:
		return
	var stats: Dictionary = get_snapshot().get(peer, {})
	relay.rpc_id(peer, "_rpc_my_stats", stats)
