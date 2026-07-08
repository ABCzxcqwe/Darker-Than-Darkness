# res://core/GameServiceLocator.gd (Autoload)
# Directorio global de servicios. Siempre vivo, pero vacío fuera de partida.
# El World llama a register_all() al iniciar y clear() al terminar.
extends Node

const CLIENT_RELAY_CLASS := preload("res://core/ClientRelay.gd")

var _registry: Dictionary = {}
var _client_relay: Node = null


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

	for entry in config.get_entries():
		_register(entry)

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
