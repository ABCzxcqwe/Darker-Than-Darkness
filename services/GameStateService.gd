# res://services/GameStateService.gd
# Servicio que indica si hay una partida activa y controla sus condiciones de fin.
extends Node

var _in_game: bool = false

# Configuración del reloj dinámico
const BASE_TIME := 90.0         # 1:30 de base
const TIME_PER_SURVIVOR := 30.0 # +30 segundos por survivor

var time_left: float = 0.0
var is_match_active: bool = false


func _ready() -> void:
	_in_game = true
	print("[GameStateService] Partida activa.")
	
	if multiplayer.is_server():
		# 1. Calcular tiempo inicial según los supervivientes en red
		var survivor_count := 0
		for pid in NetworkManager.players:
			if NetworkManager.players[pid]["assigned_role"] == "survivor":
				survivor_count += 1
		
		time_left = BASE_TIME + (survivor_count * TIME_PER_SURVIVOR)
		is_match_active = true
		
		print("[GameStateService] Survivors detectados: ", survivor_count)
		print("[GameStateService] Tiempo de ronda calculado: ", time_left, " segundos.")
		
		# Conectamos diferido al HealthService
		call_deferred("_connect_to_health_service")


func _process(delta: float) -> void:
	if not is_match_active: return
	
	if multiplayer.is_server():
		# El servidor procesa el tiempo
		time_left -= delta
		if time_left <= 0:
			time_left = 0
			is_match_active = false
			_end_match("survivors_escaped")
			return
			
		# Enviamos el tiempo actualizado a todos
		_sync_match_timer.rpc(time_left)


## CORRECCIÓN DEL HOST: Añadimos "call_local" para que el Servidor también ejecute esta función
@rpc("authority", "call_local", "unreliable")
func _sync_match_timer(server_time: float) -> void:
	time_left = server_time
	# Buscamos el HUD en la escena actual para actualizar el texto
	var hud = get_tree().get_first_node_in_group("game_hud")
	if hud and hud.has_method("update_timer_display"):
		hud.update_timer_display(time_left)


func _exit_tree() -> void:
	_in_game = false
	is_match_active = false
	print("[GameStateService] Partida terminada (World destruido).")


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
	
	print("[GameStateService] Reporte de baja recibido. Comprobando supervivientes restantes...")
	_check_survivor_deaths()


## CORRECCIÓN DE ELIMINACIÓN TOTAL: Comprobación física infalible de nodos vivos en escena
func _check_survivor_deaths() -> void:
	# 1. Primero, revisamos si queda algún survivor físicamente conectado en los datos de red
	var survivors_connected := 0
	for pid in NetworkManager.players:
		if NetworkManager.players[pid]["assigned_role"] == "survivor":
			survivors_connected += 1
			
	if survivors_connected == 0:
		print("[GameStateService] Victoria para el Killer: Todos los supervivientes abandonaron.")
		is_match_active = false
		_end_match("killer_elimination")
		return

	# 2. Si hay gente conectada, contamos cuántos personajes supervivientes quedan VIVOS en el mapa
	var players_in_scene = get_tree().get_nodes_in_group("players")
	var alive_survivors_in_map := 0
	
	for player in players_in_scene:
		# Verificamos que sea una instancia válida y que tenga los datos de personaje
		if is_instance_valid(player) and "character_data" in player and player.character_data:
			if player.character_data.team == "survivor":
				# Usamos el HealthService para asegurar que su estado no sea "dead"
				var health_svc = GameServiceLocator.get_service("HealthService")
				if health_svc:
					var peer_id = player.get_multiplayer_authority()
					if not health_svc.is_dead(peer_id):
						alive_survivors_in_map += 1

	print("[GameStateService] Supervivientes vivos en mapa actual: ", alive_survivors_in_map)

	# ── DISPARADOR RPC DE MÚSICA LMS ──
	# Si queda exactamente uno solo, el servidor da la orden de encender el LMS BGM
	if alive_survivors_in_map == 1 and is_match_active:
		AudioManager.rpc("set_global_music_state", "lms")

	# Si ya no queda NINGÚN superviviente vivo caminando en el mapa, el Killer gana la partida
	if alive_survivors_in_map == 0:
		print("[GameStateService] Todos los supervivientes en mapa han sido eliminados. Fin de partida.")
		is_match_active = false
		_end_match("killer_elimination")


## Detiene el juego y ordena la migración a la pantalla de estadísticas finales
func _end_match(reason: String) -> void:
	print("[GameStateService] Fin de la partida determinado por el Servidor: ", reason)
	
	# ── LIMPIEZA DE AUDIO GLOBAL ──
	AudioManager.rpc("set_global_music_state", "menu")
	
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
