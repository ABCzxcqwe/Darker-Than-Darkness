extends Node

signal tp_changed(peer_id: int, current_tp: float, max_tp: float)

var _tp: Dictionary = {} # {peer_id: current_tp}
var _character_data: Dictionary = {} # {peer_id: CharacterData}
var _passive_timer: Timer

func _ready() -> void:
	# Configurar timer de ganancia pasiva (Solo corre en el Servidor)
	if multiplayer.is_server():
		_passive_timer = Timer.new()
		_passive_timer.wait_time = 1.0
		_passive_timer.autostart = true
		_passive_timer.timeout.connect(_on_passive_tick)
		add_child(_passive_timer)
		# print("[TPService] Ganancia pasiva iniciada en el Servidor.")

## Registra a un jugador en el sistema de TP
func register_player(peer_id: int, data: Resource) -> void:
	_tp[peer_id] = 0.0
	_character_data[peer_id] = data
	# print("[TPService] ", _get_log_name(peer_id), " Registrado (", data.resource_path.get_file(), ")")

## Elimina los datos de un jugador (Evita el crash al desconectarse)
func unregister_player(peer_id: int) -> void:
	if _tp.has(peer_id):
		_tp.erase(peer_id)
	if _character_data.has(peer_id):
		_character_data.erase(peer_id)
	# print("[TPService] Datos eliminados para peer: ", peer_id)

## Sincroniza el TP desde el servidor hacia los clientes
@rpc("any_peer", "reliable")
func sync_tp_to_client(peer_id: int, current_tp: float, max_tp: float) -> void:
	# Actualizamos el diccionario local en el cliente para que coincida con el servidor
	_tp[peer_id] = current_tp
	# Emitimos la señal que el TpBar.gd está escuchando
	tp_changed.emit(peer_id, current_tp, max_tp)

## Añade TP a un jugador (Llamar solo desde el Servidor)
func add_tp(peer_id: int, amount_type: String) -> void:
	if not multiplayer.is_server(): return
	if not _tp.has(peer_id): return

	var data = _character_data[peer_id]
	var amount = 0.0

	match amount_type:
		"time": amount = data.tp_gain_time
		"hit": amount = data.tp_gain_hit
		"damage": amount = data.tp_gain_damage
		"custom": amount = 15.0 # Valor de ejemplo para habilidades especiales

	var old_tp = _tp[peer_id]
	_tp[peer_id] = clamp(old_tp + amount, 0.0, data.tp_max)
	
	var current_tp = _tp[peer_id]
	var max_tp = data.tp_max

	# 1. Emitir localmente para el Host
	tp_changed.emit(peer_id, current_tp, max_tp)
	
	# 2. Sincronizar con todos los clientes vía RPC
	sync_tp_to_client.rpc(peer_id, current_tp, max_tp)
	
	# Log para debug
	# print("[TPService] ", _get_log_name(peer_id), " +", amount, " TP (", amount_type, ") | Total: ", current_tp)

func _on_passive_tick() -> void:
	for peer_id in _tp.keys():
		add_tp(peer_id, "time")

func get_tp_for_peer(peer_id: int) -> float:
	return _tp.get(peer_id, 0.0)

func _get_log_name(id: int) -> String:
	if id == multiplayer.get_unique_id():
		return "[LOCAL:%d]" % id
	return "[REMOTE:%d]" % id

## Limpia todo al volver al menú
func reset() -> void:
	_tp.clear()
	_character_data.clear()
	if _passive_timer:
		_passive_timer.stop()
	# print("[TPService] Sistema reiniciado por completo.")

## Función puente para evitar el error de "Nonexistent function"
func start_passive_gain() -> void:
	if not multiplayer.is_server(): 
		return
		
	if _passive_timer == null:
		# Si por alguna razón el timer no se creó en _ready, lo creamos aquí
		_passive_timer = Timer.new()
		_passive_timer.wait_time = 1.0
		_passive_timer.autostart = true
		_passive_timer.timeout.connect(_on_passive_tick)
		add_child(_passive_timer)
		# print("[TPService] Ganancia pasiva forzada por comando externo.")
	else:
		_passive_timer.start()
		# print("[TPService] Timer de ganancia pasiva reanudado.")
		
## Función puente para habilidades que usan el nombre antiguo
func add_tp_custom(peer_id: int, amount: float = 15.0) -> void:
	# Simplemente redirigimos a la función principal
	# Si quieres usar el 'amount' específico que viene de la habilidad:
	if not multiplayer.is_server(): return
	if not _tp.has(peer_id): return

	var data = _character_data[peer_id]
	var old_tp = _tp[peer_id]
	_tp[peer_id] = clamp(old_tp + amount, 0.0, data.tp_max)
	
	# Sincronizamos con los clientes
	tp_changed.emit(peer_id, _tp[peer_id], data.tp_max)
	sync_tp_to_client.rpc(peer_id, _tp[peer_id], data.tp_max)
	
	# print("[TPService] TP Custom añadido: ", amount, " para peer: ", peer_id)
