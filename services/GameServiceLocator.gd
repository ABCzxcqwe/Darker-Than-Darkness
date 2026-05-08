# GameServiceLocator.gd  (Autoload)
# Directorio global de servicios. Siempre vivo, pero vacío fuera de partida.
# El World llama a register_all() al iniciar y clear() al terminar.
extends Node

var _registry: Dictionary = {}


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
	add_child(node)
	_registry[entry.service_name] = node
	print("[GameServiceLocator] ✓ ", entry.service_name, " registrado.")


# ── Llamado por el World al terminar la partida ────────────────────────
func clear() -> void:
	for node in _registry.values():
		if is_instance_valid(node):
			node.queue_free()
	_registry.clear()
	print("[GameServiceLocator] Todos los servicios eliminados.")


# ── API pública ────────────────────────────────────────────────────────
func get_service(service_name: String) -> Node:
	if not _registry.has(service_name):
		push_warning("[GameServiceLocator] Servicio '", service_name, "' no encontrado.")
		return null
	return _registry[service_name]


func has_service(service_name: String) -> bool:
	return _registry.has(service_name)
