# res://services/TimerService.gd
# Servicio independiente encargado de la gestión, cálculo y sincronización del tiempo de juego.
# Controla pausas lógicas y modificaciones directas al reloj de la ronda.
extends Node

signal timer_changed(current_time: float)
signal timeout()

var time_left: float = 0.0
var is_active: bool = false
var is_paused: bool = false


func _process(delta: float) -> void:
	if not is_active or is_paused:
		return
		
	if multiplayer.is_server():
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			is_active = false
			timeout.emit() # Avisa que el tiempo se agotó
			
		# Sincronización periódica o emisión local en el servidor
		timer_changed.emit(time_left)
		# Nota: Para optimizar red, puedes enviar un RPC cada 1 segundo 
		# o dejar que el Synchronizer/RPC actualice el HUD según tu preferencia.
		rpc_id(0, "_sync_time_client", time_left)
		


## Inicializa y arranca el reloj con una duración específica
func start_timer(duration: float) -> void:
	if not multiplayer.is_server():
		return
	time_left = duration
	is_active = true
	is_paused = false
	print("[TimerService] Reloj iniciado con: ", duration, "s")


## Detiene por completo el reloj
func stop_timer() -> void:
	if not multiplayer.is_server():
		return
	is_active = false
	print("[TimerService] Reloj detenido.")


## Pausa o reanuda el avance del tiempo de forma lógica
func set_paused(paused: bool) -> void:
	if not multiplayer.is_server():
		return
	is_paused = paused
	print("[TimerService] Estado de pausa cambiado a: ", paused)


## Añade o resta segundos al tiempo actual de la ronda
func modify_time(seconds: float) -> void:
	if not multiplayer.is_server() or not is_active:
		return
	time_left = maxf(time_left + seconds, 0.0)
	print("[TimerService] Tiempo modificado en ", seconds, "s. Restante: ", time_left)


@rpc("any_peer", "unreliable")
func _sync_time_client(server_time: float) -> void:
	if not multiplayer.is_server():
		time_left = server_time
		timer_changed.emit(time_left)
