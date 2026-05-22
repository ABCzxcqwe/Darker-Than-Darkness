# res://services/GameStateService.gd
# Servicio central que controla el estado macro de la partida y sus reglas de fin.
# Delega el tiempo a TimerService y las bajas a LMSService.
extends Node

var _in_game: bool = false
var is_match_active: bool = false

const BASE_TIME := 90.0         
const TIME_PER_SURVIVOR := 30.0 

var _ending_sequence_started := false
var _lms_service: Node = null


func _ready() -> void:
	_in_game = true
	print("[GameStateService] Partida activa.")
	
	if multiplayer.is_server():
		if NetworkManager.has_signal("player_left"):
			NetworkManager.player_left.connect(_on_network_player_left)

		# 1. Calcular tiempo inicial según sobrevivientes
		var survivor_count := 0
		for pid in NetworkManager.players:
			if NetworkManager.players[pid]["assigned_role"] == "survivor":
				survivor_count += 1
		
		var calculated_time = BASE_TIME + (survivor_count * TIME_PER_SURVIVOR)
		is_match_active = true
		
		# 2. Registrar y encender el TimerService de forma diferida
		call_deferred("_initialize_game_match", calculated_time)


func is_in_game() -> bool:
	return _in_game


func _initialize_game_match(initial_time: float) -> void:
	_connect_services()
	
	# Obtener el nuevo servicio de tiempo e iniciar la cuenta regresiva
	var timer_svc = GameServiceLocator.get_service("TimerService")
	if timer_svc:
		if not timer_svc.timeout.is_connected(_on_timer_timeout):
			timer_svc.timeout.connect(_on_timer_timeout)
		timer_svc.start_timer(initial_time)


func _connect_services() -> void:
	var health_svc = GameServiceLocator.get_service("HealthService")
	_lms_service = GameServiceLocator.get_service("LMSService")
	
	if health_svc:
		if not health_svc.survivor_died_permanently.is_connected(_on_survivor_permanent_death):
			health_svc.survivor_died_permanently.connect(_on_survivor_permanent_death)
			


# REACCIÓN AL TIEMPO: El GameStateService solo actúa cuando el Timer le avisa
func _on_timer_timeout() -> void:
	if not multiplayer.is_server() or not is_match_active:
		return
	print("[GameStateService] El tiempo se ha agotado de forma natural.")
	is_match_active = false
	_end_match("survivors_escaped")


func _on_survivor_permanent_death(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
		
	# 1. Aumentar 15 segundos al reloj de la partida por la baja
	var timer_svc = GameServiceLocator.get_service("TimerService")
	if timer_svc and is_match_active:
		timer_svc.modify_time(15.0)
		print("[GameStateService] Tiempo de partida extendido por muerte de: ", peer_id)
		
	# 2. Contabilizar cuántos quedan para las reglas macro de fin de juego
	var survivors_alive := 0
	for pid in NetworkManager.players:
		if NetworkManager.players[pid]["assigned_role"] == "survivor":
			var health_svc = GameServiceLocator.get_service("HealthService")
			if health_svc and not health_svc.is_dead(pid):
				survivors_alive += 1
				
	if survivors_alive == 0:
		print("[GameStateService] Todos los survivors han muerto. Fin de la partida.")
		if timer_svc:
			timer_svc.stop_timer()
		is_match_active = false
		_end_match("killer_elimination")
	else:
		# SOLUCCIÓN: Avisamos una sola vez. El LMS sabrá qué hacer internamente.
		if _lms_service and _lms_service.has_method("on_survivor_permanent_death"):
			_lms_service.on_survivor_permanent_death(peer_id)


func _on_network_player_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
		
	var abandoned_role := "unknown"
	if NetworkManager.players.has(peer_id):
		abandoned_role = NetworkManager.players[peer_id].get("assigned_role", "unknown")
		
	var tp_service = GameServiceLocator.get_service("TPService")
	if tp_service and tp_service.has_method("unregister_player"):
		tp_service.unregister_player(peer_id)
		
	var evo_service = GameServiceLocator.get_service("EvolutionService")
	if evo_service and evo_service.has_method("unregister_player"):
		evo_service.unregister_player(peer_id)
		
	var cd_service = GameServiceLocator.get_service("CooldownService")
	if cd_service and cd_service.has_method("clear_player"):
		cd_service.clear_player(peer_id)
		
	handle_player_disconnect(peer_id, abandoned_role)


func handle_player_disconnect(peer_id: int, abandoned_role: String) -> void:
	if not multiplayer.is_server():
		return
	
	if abandoned_role == "killer":
		var timer_svc = GameServiceLocator.get_service("TimerService")
		if timer_svc:
			timer_svc.stop_timer()
		is_match_active = false
		_end_match("killer_disconnected")
		return
	
	if abandoned_role == "survivor":
		print("[GameStateService] Survivor (", peer_id, ") se desconectó. Procesando penalización...")
		
		# 1. Notificar al LMSService de la baja por desconexión para limpiar registros
		if _lms_service and _lms_service.has_method("on_survivor_permanent_death"):
			_lms_service.on_survivor_permanent_death(peer_id)
		
		# 2. Modificar el temporizador de la ronda (+10s por abandono)
		var timer_svc = GameServiceLocator.get_service("TimerService")
		if timer_svc and is_match_active:
			timer_svc.modify_time(10.0)
			print("[GameStateService] Tiempo aumentado +10s debido al abandono de ", peer_id)
		
		# 3. Evaluar si quedan sobrevivientes activos en la partida
		var survivors_left := 0
		for pid in NetworkManager.players:
			if pid == peer_id: 
				continue
			if NetworkManager.players[pid]["assigned_role"] == "survivor":
				var health_svc = GameServiceLocator.get_service("HealthService")
				if health_svc and not health_svc.is_dead(pid):
					survivors_left += 1
		
		# 4. Resolver el destino de la partida
		if survivors_left == 0:
			print("[GameStateService] No quedan survivors activos en la partida. Fin por abandono masivo.")
			if timer_svc:
				timer_svc.stop_timer()
			is_match_active = false
			_end_match("killer_elimination")
		else:
			# Actualizar la UI de los jugadores restantes
			if _lms_service:
				var alive_nodes = _lms_service._get_alive_survivor_nodes()
				_lms_service.update_survivors_count(alive_nodes)


func _end_match(reason: String) -> void:
	print("[GameStateService] Terminar partida por razón: ", reason)
	_in_game = false
	is_match_active = false
	
	_calculate_next_killer_points(reason)
	
	# Obtenemos el tiempo final que quedó registrado en el TimerService
	var final_time := 0.0
	var timer_svc = GameServiceLocator.get_service("TimerService")
	if timer_svc:
		final_time = timer_svc.time_left
	
	var stats_data := {
		"end_reason": reason,
		"time_left": final_time,
		"players_snapshot": NetworkManager.players.duplicate(true)
	}
	
	NetworkManager.rpc("_go_to_stats_screen", stats_data)


func _calculate_next_killer_points(reason: String) -> void:
	for pid in NetworkManager.players:
		if not NetworkManager.players.has(pid): continue
		var role = NetworkManager.players[pid]["assigned_role"]
		
		if reason == "survivors_escaped":
			if role == "survivor":
				NetworkManager.players[pid]["killer_points"] += 10
			else:
				NetworkManager.players[pid]["killer_points"] += 40
		
		elif reason == "killer_elimination":
			if role == "killer":
				NetworkManager.players[pid]["killer_points"] += 5
			else:
				NetworkManager.players[pid]["killer_points"] += 25

func evaluate_sudden_death_condition() -> void:
	if not multiplayer.is_server() or _ending_sequence_started:
		return

	var health_svc = GameServiceLocator.get_service("HealthService")
	if health_svc and health_svc.check_all_survivors_incapacitated():
		_ending_sequence_started = true
		print("[GameStateService] ¡Todos los survivors están caídos! Iniciando temporizador de 3s...")
		
		# Creamos un timer de 3 segundos directo en el árbol de escenas
		await get_tree().create_timer(3.0).timeout
		
		# Volvemos a verificar después de la espera
		if health_svc.check_all_survivors_incapacitated():
			print("[GameStateService] Condición cumplida. Terminando partida por K.O. Total.")
			# Corregido: Usamos tu función nativa y detenemos el reloj global
			var timer_svc = GameServiceLocator.get_service("TimerService")
			if timer_svc:
				timer_svc.stop_timer()
			is_match_active = false
			_end_match("killer_elimination")
		else:
			print("[GameStateService] Secuencia cancelada: Un survivor se levantó o revivió.")
			_ending_sequence_started = false
