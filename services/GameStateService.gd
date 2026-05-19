# res://services/GameStateService.gd
# Servicio que indica si hay una partida activa y controla sus condiciones de fin.
# La lógica de LMS (último superviviente) ha sido delegada a LMSService.
extends Node

var _in_game: bool = false

# Configuración del reloj dinámico
const BASE_TIME := 90.0         # 1:30 de base
const TIME_PER_SURVIVOR := 30.0 # +30 segundos por survivor

var time_left: float = 0.0
var is_match_active: bool = false

# Referencia al servicio LMS (se obtiene al iniciar)
var _lms_service: Node = null


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
		
		# Conectar servicios (HealthService y LMSService)
		call_deferred("_connect_services")


func _process(delta: float) -> void:
	if not is_match_active: return
	
	if multiplayer.is_server():
		time_left -= delta
		if time_left <= 0:
			time_left = 0
			is_match_active = false
			_end_match("survivors_escaped")
			return
		
		# Enviar tiempo actualizado a todos
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


## Conecta servicios necesarios (HealthService y LMSService)
func _connect_services() -> void:
	# HealthService
	var health_svc = GameServiceLocator.get_service("HealthService")
	if health_svc:
		health_svc.survivor_died_permanently.connect(_on_survivor_died)
		print("[GameStateService] Enlazado exitosamente al HealthService.")
	else:
		push_error("[GameStateService] No se pudo encontrar HealthService.")
	
	# LMSService
	_lms_service = GameServiceLocator.get_service("LMSService")
	if not _lms_service:
		push_warning("[GameStateService] LMSService no disponible — la música de último superviviente no funcionará.")
	else:
		# Conectar la señal de muerte permanente también al LMS
		if health_svc:
			health_svc.survivor_died_permanently.connect(_lms_service.on_survivor_permanent_death)


## Se dispara cuando HealthService ejecuta o desangra a un survivor (muerte definitiva)
func _on_survivor_died(_dead_peer_id: int) -> void:
	if not is_match_active or not multiplayer.is_server(): return
	
	print("[GameStateService] Reporte de baja recibido. Comprobando supervivientes restantes...")
	_check_survivor_deaths()


## Comprobación de supervivientes vivos y fin de partida.
## Además notifica a LMSService sobre el estado actual.
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

	# 2. Contamos cuántos personajes supervivientes quedan VIVOS en el mapa
	var players_in_scene = get_tree().get_nodes_in_group("players")
	var alive_survivors_in_map := 0
	var alive_survivor_nodes: Array = []   # guardamos los nodos para pasarlos al LMS
	
	for player in players_in_scene:
		if is_instance_valid(player) and "character_data" in player and player.character_data:
			if player.character_data.team == "survivor":
				var health_svc = GameServiceLocator.get_service("HealthService")
				if health_svc:
					var peer_id = player.get_multiplayer_authority()
					if not health_svc.is_dead(peer_id):
						alive_survivors_in_map += 1
						alive_survivor_nodes.append(player)

	print("[GameStateService] Supervivientes vivos en mapa actual: ", alive_survivors_in_map)

	# ── NOTIFICAR AL SERVICIO LMS ──
	if _lms_service and _lms_service.has_method("update_survivors_count"):
		_lms_service.update_survivors_count(alive_survivor_nodes)
	
	# ── DETECTAR FIN DE PARTIDA POR ELIMINACIÓN TOTAL ──
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


# ── FUNCIONES AUXILIARES PARA DESCONEXIÓN ──────────────────────────────────────
func handle_player_disconnect(peer_id: int, abandoned_role: String) -> void:
	if not multiplayer.is_server():
		return
	
	print("[GameStateService] Jugador ", peer_id, " (", abandoned_role, ") se desconectó.")
	
	# Si el que se fue era el killer, la partida termina (victoria para survivors)
	if abandoned_role == "killer":
		print("[GameStateService] El killer abandonó. Fin de partida.")
		is_match_active = false
		_end_match("killer_disconnected")
		return
	
	# Si era un survivor, verificamos si aún quedan survivors vivos en el mapa
	if abandoned_role == "survivor":
		# Esperar un frame para que el nodo del survivor se elimine correctamente
		await get_tree().process_frame
		_check_survivor_deaths()
