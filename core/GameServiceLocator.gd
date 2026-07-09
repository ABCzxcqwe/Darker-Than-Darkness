# res://core/GameServiceLocator.gd (Autoload)
# Directorio global de servicios. Siempre vivo, pero vacío fuera de partida.
# El World llama a register_all() al iniciar y clear() al terminar.
extends Node

const CLIENT_RELAY_CLASS := preload("res://core/ClientRelay.gd")
const _GameStateService := preload("res://services/GameStateService.gd")
const _TimerService := preload("res://services/TimerService.gd")
const _CooldownService := preload("res://services/CooldownService.gd")
const _HitboxService := preload("res://services/HitboxService.gd")
const _HealthService := preload("res://services/HealthService.gd")
const _AbilityStateService := preload("res://services/AbilityStateService.gd")
const _ReviveService := preload("res://services/ReviveService.gd")
const _StatusEffectService := preload("res://services/StatusEffectService.gd")
const _TPService := preload("res://services/TPService.gd")
const _EvolutionService := preload("res://services/EvolutionService.gd")
const _LMSService := preload("res://services/LMSService.gd")
const _CombatMediator := preload("res://services/CombatMediator.gd")
const _StaminaService := preload("res://services/StaminaService.gd")
const _RadarService := preload("res://services/RadarService.gd")
const _MapEventCoordinator := preload("res://services/MapEventCoordinator.gd")

var _registry: Dictionary = {}
var _client_relay: Node = null

var game_state: _GameStateService:
	get: return _registry.get(ServiceNames.GAME_STATE) as _GameStateService
var timer: _TimerService:
	get: return _registry.get(ServiceNames.TIMER) as _TimerService
var cooldown: _CooldownService:
	get: return _registry.get(ServiceNames.COOLDOWN) as _CooldownService
var hitbox: _HitboxService:
	get: return _registry.get(ServiceNames.HITBOX) as _HitboxService
var health: _HealthService:
	get: return _registry.get(ServiceNames.HEALTH) as _HealthService
var ability_state: _AbilityStateService:
	get: return _registry.get(ServiceNames.ABILITY_STATE) as _AbilityStateService
var revive: _ReviveService:
	get: return _registry.get(ServiceNames.REVIVE) as _ReviveService
var status_effect: _StatusEffectService:
	get: return _registry.get(ServiceNames.STATUS_EFFECT) as _StatusEffectService
var tp: _TPService:
	get: return _registry.get(ServiceNames.TP) as _TPService
var evolution: _EvolutionService:
	get: return _registry.get(ServiceNames.EVOLUTION) as _EvolutionService
var lms: _LMSService:
	get: return _registry.get(ServiceNames.LMS) as _LMSService
var combat_mediator: _CombatMediator:
	get: return _registry.get(ServiceNames.COMBAT_MEDIATOR) as _CombatMediator
var stamina: _StaminaService:
	get: return _registry.get(ServiceNames.STAMINA) as _StaminaService
var radar: _RadarService:
	get: return _registry.get(ServiceNames.RADAR) as _RadarService
var map_event_coordinator: _MapEventCoordinator:
	get: return _registry.get(ServiceNames.MAP_EVENT_COORDINATOR) as _MapEventCoordinator


func _ready() -> void:
	# ClientRelay existe siempre en todos los peers
	_client_relay = CLIENT_RELAY_CLASS.new()
	_client_relay.name = "ClientRelay"
	add_child(_client_relay)


# ── Llamado por el World al iniciar la partida ─────────────────────────
func register_all(config: GameServicesConfig) -> void:
	if not config:
		push_error("[GameServiceLocator] Config nula.")
		return

	# Fase 1: crear todos los servicios
	for entry in config.get_entries():
		_register(entry)

	# Fase 2: inyectar dependencias por convención de nombres (soporta grafos cíclicos)
	for service_node in _registry.values():
		_auto_inject(service_node)

	print("[GameServiceLocator] Servicios activos: ", _registry.keys())


func _register(entry: ServiceEntry) -> void:
	if not entry or entry.service_name == "" or not entry.service_script:
		push_warning("[GameServiceLocator] ServiceEntry inválida, ignorando.")
		return
	if _registry.has(entry.service_name):
		push_warning("[GameServiceLocator] '", entry.service_name, "' ya registrado.")
		return

	var node: Node = entry.service_script.new()
	node.name = entry.service_name
	# Inyectar referencia al ClientRelay
	if node.has_method("set_client_relay"):
		node.set_client_relay(_client_relay)
	add_child(node)
	_registry[entry.service_name] = node
	print("[GameServiceLocator] ✓ ", entry.service_name, " registrado.")


func _auto_inject(service: Node) -> void:
	var prop_names := {}
	for p in service.get_property_list():
		prop_names[p.name] = true
	for svc_name in _registry:
		var expected_prop := "_" + _to_snake_case(svc_name)
		if expected_prop in prop_names:
			service.set(expected_prop, _registry[svc_name])
			print("[GameServiceLocator]  ", service.name, " ← ", svc_name)


func _to_snake_case(name: String) -> String:
	var result := ""
	for i in range(name.length()):
		var c := name[i]
		if i > 0 and c >= 'A' and c <= 'Z':
			var prev := name[i - 1]
			if prev >= 'a' and prev <= 'z':
				result += "_"
			elif i + 1 < name.length() and name[i + 1] >= 'a' and name[i + 1] <= 'z':
				result += "_"
		result += c.to_lower()
	return result


# ── Llamado por el World al terminar la partida ────────────────────────
func clear() -> void:
	for node in _registry.values():
		if is_instance_valid(node):
			node.queue_free()
	_registry.clear()
	if is_instance_valid(_client_relay):
		_client_relay.reset_state()
	print("[GameServiceLocator] Todos los servicios eliminados.")


# ── API pública ────────────────────────────────────────────────────────
func get_service(service_name: String) -> Node:
	if not _registry.has(service_name):
		push_warning("[GameServiceLocator] Servicio '", service_name, "' no encontrado.")
		return null
	return _registry[service_name]


func has_service(service_name: String) -> bool:
	return _registry.has(service_name)


func get_client_relay() -> Node:
	return _client_relay
