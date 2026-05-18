# res://services/GameStateService.gd
# Servicio que indica si hay una partida activa y controla sus condiciones de fin.
extends Node

var _in_game: bool = false

# Reloj de la partida (Solo procesamiento de Servidor)
var round_duration: float = 120.0 # 2 minutos por partida
var time_left: float = 0.0
var is_match_active: bool = false


func _ready() -> void:
	_in_game = true
	print("[GameStateService] Partida activa.")
	
	if multiplayer.is_server():
		time_left = round_duration
		is_match_active = true
		print("[GameStateService] Servidor iniciando cronómetro de juego.")
		
		# Conectamos diferido para asegurar que HealthService ya esté registrado en el ServiceLocator
		call_deferred("_connect_to_health_service")


func _process(delta: float) -> void:
	if not is_match_active or not multiplayer.is_server(): 
		return
	
	# CONDICIÓN 1: El tiempo se agota (Survivors Escapan)
	time_left -= delta
	if time_left <= 0:
		time_left = 0
		_end_match("survivors_escaped")


func _exit_tree() -> void:
	_in_game = false
	is_match_active = false
	print("[GameStateService] Partida terminada (World destruido).")


## Devuelve true si hay una partida en curso.
func is_in_game() -> bool:
	return _in_game


## Intenta conectarse a la señal de muerte definitiva del HealthService
func _connect_to_health_service() -> void:
	var health_svc = GameServiceLocator.get_service("HealthService")
	if health_svc:
		health_svc.survivor_died_permanently.connect(_on_survivor_died)
		print("[GameStateService] Enlazado exitosamente al HealthService.")
	else:
		push_error("[GameStateService] No se pudo encontrar HealthService para monitorear muertes.")


## Se dispara inmediatamente cuando HealthService ejecuta/desangra a un survivor
func _on_survivor_died(_dead_peer_id: int) -> void:
	if not is_match_active or not multiplayer.is_server(): return
	
	print("[GameStateService] Reporte de baja recibido. Comprobando sobrevivientes restantes...")
	_check_survivor_deaths()


## Verifica si el equipo de supervivientes ha caído por completo basándose en el diccionario de red
func _check_survivor_deaths() -> void:
	var health_svc = GameServiceLocator.get_service("HealthService")
	if not health_svc: return
	
	var active_survivors := 0
	var dead_survivors := 0
	
	# Contamos cuántos supervivientes quedan en los datos de red del NetworkManager
	for pid in NetworkManager.players:
		var role = NetworkManager.players[pid]["assigned_role"]
		if role == "survivor":
			active_survivors += 1
			# Consultamos si el servicio de salud ya lo tiene registrado como muerto definitivo
			if health_svc.is_dead(pid):
				dead_survivors += 1

	print("[GameStateService] Conteo actual -> Survivors Conectados: %d | Muertos: %d" % [active_survivors, dead_survivors])

	# CORRECCIÓN: CASO A - Si había supervivientes en la sala pero TODOS se desconectaron de golpe
	if active_survivors == 0:
		print("[GameStateService] No quedan supervivientes en la partida. Victoria para el Killer por abandono.")
		_end_match("killer_elimination") # El Killer gana porque se quedó solo
		return

	# CASO B - Si quedan supervivientes conectados, pero todos ellos están muertos en el mapa
	if active_survivors > 0 and dead_survivors == active_survivors:
		print("[GameStateService] Todos los supervivientes conectados han sido eliminados.")
		_end_match("killer_elimination")


## Detiene el juego y ordena la migración a la pantalla de estadísticas finales
func _end_match(reason: String) -> void:
	is_match_active = false
	print("[GameStateService] Fin de la partida determinado por el Servidor: ", reason)
	
	_calculate_next_killer_points(reason)
	
	var stats_data := {
		"reason": reason,
		"winner": "survivors" if reason == "survivors_escaped" else "killer"
	}
	
	NetworkManager.rpc("_go_to_stats_screen", stats_data)


## Modifica los killer_points de la sesión de juego según el resultado de la ronda
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

func handle_player_disconnect(abandoned_peer_id: int, role: String) -> void:
	if not is_match_active or not multiplayer.is_server(): return
	
	print("[GameStateService] Alerta: El Peer %d (%s) abandonó la partida en curso." % [abandoned_peer_id, role])
	
	# CASO 1: Se salió el Killer -> Fin de partida inmediato (Ganan Survivors)
	if role == "killer":
		print("[GameStateService] El Killer abandonó. Cerrando partida por abandono.")
		_end_match("killer_disconnected")
		return
		
	# CASO 2: Se salió un Survivor -> Reajustamos el HealthService y recalculamos
	var health_svc = GameServiceLocator.get_service("HealthService")
	if health_svc:
		health_svc.unregister(abandoned_peer_id) # Lo quitamos del sistema de salud 
		
	# Comprobamos si el abandono de este jugador altera las condiciones de victoria del mapa
	_check_survivor_deaths()
