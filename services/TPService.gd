# TPService.gd
# Servicio de Tension Points — se registra en GameServices.tres como ServiceEntry.
# Se accede via: GameServiceLocator.get_service("TPService")
#
# Fuentes de TP:
#   "attack" → ataque/habilidad acertada
#   "dodge"  → esquivar un ataque enemigo
#   "time"   → ganancia pasiva por segundo
extends Node

# { peer_id: float }
var _tp: Dictionary = {}

# { peer_id: CharacterData }
var _character_data: Dictionary = {}

# Timer para ganancia pasiva por tiempo
var _passive_timer: Timer

# Emitida cuando un slot alcanza su tp_cost — EvolutionService escucha esto
signal slot_ready_to_evolve(peer_id: int, slot_index: int)

# =========================================================
# INICIALIZACIÓN
# =========================================================
func _ready() -> void:
	_passive_timer = Timer.new()
	_passive_timer.wait_time = 1.0
	_passive_timer.autostart = false
	_passive_timer.timeout.connect(_on_passive_tick)
	add_child(_passive_timer)

# =========================================================
# REGISTRO DE JUGADORES
# =========================================================

## Llamar desde World cuando se conoce el CharacterData de cada jugador
func register_player(peer_id: int, data: CharacterData) -> void:
	_tp[peer_id] = 0.0
	_character_data[peer_id] = data

func unregister_player(peer_id: int) -> void:
	_tp.erase(peer_id)
	_character_data.erase(peer_id)

func start_passive_gain() -> void:
	_passive_timer.start()

func stop_passive_gain() -> void:
	_passive_timer.stop()

# =========================================================
# GANANCIA DE TP
# =========================================================

## source: "attack", "dodge", "time"
func add_tp(peer_id: int, source: String) -> void:
	if not _tp.has(peer_id):
		return
	var data: CharacterData = _character_data[peer_id]
	var gain := _get_gain(data, source)
	if gain <= 0.0:
		return
	_tp[peer_id] = minf(_tp[peer_id] + gain, data.tp_max)
	_check_evolution(peer_id)

func add_tp_custom(peer_id: int, amount: float) -> void:
	if not _tp.has(peer_id):
		return
	var data: CharacterData = _character_data[peer_id]
	_tp[peer_id] = minf(_tp[peer_id] + amount, data.tp_max)
	_check_evolution(peer_id)

func get_tp(peer_id: int) -> float:
	return _tp.get(peer_id, 0.0)

func reset_tp(peer_id: int) -> void:
	if _tp.has(peer_id):
		_tp[peer_id] = 0.0

# =========================================================
# VERIFICACIÓN DE EVOLUCIÓN
# =========================================================
func _check_evolution(peer_id: int) -> void:
	var data: CharacterData = _character_data.get(peer_id)
	if not data:
		return

	var evolution_service = GameServiceLocator.get_service("EvolutionService")
	if not evolution_service:
		return

	for i in data.ability_slots.size():
		var ability: AbilityData = data.ability_slots[i]
		if ability == null:
			continue
		if ability.evolved_version == null or ability.tp_cost <= 0.0:
			continue
		if _tp[peer_id] >= ability.tp_cost and not evolution_service.is_evolved(peer_id, i):
			slot_ready_to_evolve.emit(peer_id, i)
			evolution_service.evolve_slot(peer_id, i)

# =========================================================
# TICK PASIVO
# =========================================================
func _on_passive_tick() -> void:
	for peer_id in _tp.keys():
		add_tp(peer_id, "time")

# =========================================================
# HELPERS
# =========================================================
func _get_gain(data: CharacterData, source: String) -> float:
	match source:
		"on_hit": return data.tp_gain_on_hit   # renombrado
		"dodge":  return data.tp_gain_dodge
		"time":   return data.tp_gain_time
	return 0.0
