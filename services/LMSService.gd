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
var _audio_manager = null  # AudioManager autoload


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
		return 
	
	if is_active:
		if not active_survivor or not _is_survivor_valid(active_survivor):
			_deactivate_lms()
		return
	
	if alive_survivors.size() == 1:
		# ESCUDO: Si ya hay un timer corriendo, salimos inmediatamente
		if _activation_timer != null:
			return
			
		var survivor = alive_survivors[0]
		print("[LMSService] Posible LMS para ", survivor.name, " esperando ", ACTIVATION_DELAY, "s")
		_activation_timer = get_tree().create_timer(ACTIVATION_DELAY)
		_activation_timer.timeout.connect(_on_activation_timeout.bind(survivor))
	
	elif alive_survivors.size() != 1 and _activation_timer:
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
	
	# 1. Obtener de forma segura el Peer ID del sobreviviente
	var survivor_peer_id: int = survivor.name.to_int()
	
	# 2. CORRECCIÓN: Extraer la data directamente desde el componente/variable del personaje
	var char_data = survivor.character_data if "character_data" in survivor else null
	
	# Si no la encuentra en el nodo, intentamos ver si está dentro de un componente de estadísticas
	if not char_data and survivor.has_node("CharacterStats"):
		char_data = survivor.get_node("CharacterStats").character_data

	var lms_duration = char_data.lms_duration if char_data and "lms_duration" in char_data else 140.0
	var heal_amount = char_data.lms_heal_amount if char_data and "lms_heal_amount" in char_data else 60
	var _damage_resist = char_data.lms_damage_resistance if char_data and "lms_damage_resistance" in char_data else 0.0
	var lms_music = char_data.lms_music if char_data and "lms_music" in char_data else null

	print("[LMSService] 🎵 LMS activado para ", survivor.name)

	# Registrar la música LMS en el AudioManager local del Servidor
	if lms_music and _audio_manager:
		if _audio_manager.lms_music_player:
			_audio_manager.lms_music_player.stream = lms_music
			print("[LMSService] Música LMS registrada en AudioManager local")
	
	# Curar al survivor
	if _health_service:
		print("[LMSService] Curación LMS de ", heal_amount, " HP")
		_health_service.heal(survivor, heal_amount)
	
	# 3. Sincronizar Audio de forma segura por RPC mediante el AudioManager
	if _audio_manager and multiplayer.is_server():
		print("[LMSService] Enviando RPC seguro de audio para Peer: ", survivor_peer_id)
		# Llamamos al RPC que ya tienes en el AudioManager pasándole el ID limpio
		_audio_manager.rpc("_rpc_activate_lms_audio", survivor_peer_id)
	
	# 4. Ajustar el temporizador del juego
	var timer_svc = GameServiceLocator.get_service("TimerService")
	if timer_svc:
		print("[LMSService] Ajustando TimerService a la duración del LMS: ", lms_duration, "s")
		timer_svc.start_timer(lms_duration)
		
		if not timer_svc.timeout.is_connected(_on_timer_service_timeout):
			timer_svc.timeout.connect(_on_timer_service_timeout)
	
	lms_activated.emit(survivor, lms_duration)

func _on_timer_service_timeout() -> void:
	if is_active:
		print("[LMSService] El tiempo del TimerService expiró durante el LMS.")
		_deactivate_lms()

func _deactivate_lms() -> void:
	if not is_active:
		return
	print("[LMSService] LMS desactivado")
	
	# Desconectarse del servicio de tiempo de forma segura
	var timer_svc = GameServiceLocator.get_service("TimerService")
	if timer_svc and timer_svc.timeout.is_connected(_on_timer_service_timeout):
		timer_svc.timeout.disconnect(_on_timer_service_timeout)
	
	# Desactivar audio LMS
	if _audio_manager and multiplayer.is_server():
		print("[LMSService] Enviando RPC para desactivar LMS audio")
		_audio_manager.rpc("_rpc_deactivate_lms_audio")
	
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
		
	# Si el survivor activo del LMS murió, desactivar LMS de inmediato
	if is_active and active_survivor and active_survivor.get_multiplayer_authority() == peer_id:
		_deactivate_lms()
		return
		
	# Si no hay LMS activo, calculamos si esta muerte gatilla el inicio del modo
	if not is_active:
		# Forzamos un frame de espera (await) para asegurar que los estados de salud
		# y los grupos de Godot se hayan actualizado completamente tras la baja.
		await get_tree().process_frame
		
		var alive = _get_alive_survivor_nodes()
		update_survivors_count(alive)


# Función de utilidad pública para saber si el LMS está activo
func is_lms_active() -> bool:
	return is_active


# Obtener el survivor activo (útil para buffos)
func get_active_survivor() -> Node:
	return active_survivor
