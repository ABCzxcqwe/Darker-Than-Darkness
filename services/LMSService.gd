# res://services/LMSService.gd
# Servicio que activa el modo LMS (Last Man Standing) cuando queda un solo survivor.
# Proporciona música especial, curación, resistencia y duración configurable.
extends Node

signal lms_activated(survivor_node: Node, duration: float)
signal lms_ended()

const ACTIVATION_DELAY: float = 3.0

var is_active: bool = false
var active_survivor: Node = null
var _activation_timer: SceneTreeTimer = null
var _duration_timer: SceneTreeTimer = null

# Referencias a servicios (se obtienen al iniciar)
var _health_service: Node = null
var _status_service: Node = null
var _audio_manager: AudioManager = null


func _ready() -> void:
	# Conectar servicios después de que GameServiceLocator los registre
	call_deferred("_connect_services")


func _connect_services() -> void:
	_health_service = GameServiceLocator.get_service("HealthService")
	_status_service = GameServiceLocator.get_service("StatusEffectService")
	_audio_manager = AudioManager  # autoload
	
	if not _health_service:
		push_error("[LMSService] HealthService no disponible")
	if not _status_service:
		push_error("[LMSService] StatusEffectService no disponible")
	if not _audio_manager:
		push_error("[LMSService] AudioManager no disponible")


# Llamado por GameStateService cuando cambia el número de survivors vivos
# Recibe una lista de nodos (players) que están vivos (no dead)
func update_survivors_count(alive_survivors: Array) -> void:
	if not multiplayer.is_server():
		return  # solo el servidor gestiona LMS
	
	if is_active:
		# Si el LMS ya está activo, verificar que el survivor siga vivo
		if not active_survivor or not _is_survivor_valid(active_survivor):
			_deactivate_lms()
		return
	
	if alive_survivors.size() == 1 and not _activation_timer:
		var survivor = alive_survivors[0]
		print("[LMSService] Posible LMS para ", survivor.name, " esperando ", ACTIVATION_DELAY, "s")
		_activation_timer = get_tree().create_timer(ACTIVATION_DELAY)
		_activation_timer.timeout.connect(_on_activation_timeout.bind(survivor))
	elif alive_survivors.size() != 1 and _activation_timer:
		# Cancelar activación pendiente
		_cancel_activation()


func _on_activation_timeout(survivor: Node) -> void:
	_activation_timer = null
	# Re-verificar que sigue siendo el único survivor vivo
	if not _is_survivor_valid(survivor):
		print("[LMSService] LMS cancelado: survivor ya no es válido")
		return
	
	var alive = _get_alive_survivor_nodes()
	if alive.size() != 1 or alive[0] != survivor:
		print("[LMSService] LMS cancelado: ya no es el único survivor")
		return
	
	_activate_lms(survivor)


func _activate_lms(survivor: Node) -> void:
	is_active = true
	active_survivor = survivor
	var char_data = survivor.character_data
	# Usar get() para evitar errores si la propiedad no existe
	var lms_duration = char_data.lms_duration if char_data else 140.0
	var heal_amount = char_data.lms_heal_amount if char_data else 60
	var damage_resist = char_data.lms_damage_resistance if char_data else 0.0

	print("[LMSService] LMS activado para ", survivor.name, " duración: ", lms_duration, "s")

	if damage_resist > 0 and _status_service:
		_status_service.apply_modifier(survivor, "lms_damage_resistance", damage_resist)
	
	if _health_service:
		_health_service.heal(survivor, heal_amount)
	
	_duration_timer = get_tree().create_timer(lms_duration)
	_duration_timer.timeout.connect(_deactivate_lms)
	
	if _audio_manager:
		_audio_manager.set_global_music_state("lms")
	
	lms_activated.emit(survivor, lms_duration)


func _deactivate_lms() -> void:
	if not is_active:
		return
	print("[LMSService] LMS desactivado")
	
	# Limpiar temporizadores
	if _duration_timer:
		_duration_timer.timeout.disconnect(_deactivate_lms)
		_duration_timer = null
	
	# Remover efectos especiales
	if active_survivor and is_instance_valid(active_survivor) and _status_service:
		_status_service.remove_modifier(active_survivor, "lms_damage_resistance")
	
	# Restaurar música normal
	if _audio_manager:
		_audio_manager.exit_lms()
	
	is_active = false
	active_survivor = null
	lms_ended.emit()


func _cancel_activation() -> void:
	if _activation_timer:
		_activation_timer.timeout.disconnect(_on_activation_timeout)
		_activation_timer = null
		print("[LMSService] Activación LMS cancelada")


# Verifica si un survivor sigue siendo válido (no muerto, nodo existe)
func _is_survivor_valid(survivor: Node) -> bool:
	if not is_instance_valid(survivor):
		return false
	var peer_id = survivor.get_multiplayer_authority()
	return _health_service and not _health_service.is_dead(peer_id)


# Obtiene los nodos de survivors vivos (no dead) en la escena actual
func _get_alive_survivor_nodes() -> Array:
	var result = []
	for player in get_tree().get_nodes_in_group("players"):
		if player.character_data and player.character_data.team == "survivor":
			var peer_id = player.get_multiplayer_authority()
			if _health_service and not _health_service.is_dead(peer_id):
				result.append(player)
	return result


# Llamado desde GameStateService cuando un survivor muere permanentemente (señal)
func on_survivor_permanent_death(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Si el survivor activo del LMS murió, desactivar LMS
	if is_active and active_survivor and active_survivor.get_multiplayer_authority() == peer_id:
		_deactivate_lms()
	# También cancelar cualquier activación pendiente si el único survivor murió durante el delay
	elif _activation_timer:
		# Verificar si el único survivor restante es el que murió
		var alive = _get_alive_survivor_nodes()
		if alive.size() != 1:
			_cancel_activation()


# Función de utilidad pública para saber si el LMS está activo
func is_lms_active() -> bool:
	return is_active


# Obtener el survivor activo (útil para buffos)
func get_active_survivor() -> Node:
	return active_survivor
