# res://Gameplay/services/TimerService.gd
# Servicio de tiempo de ronda: pausas lógicas, modificaciones y sincronización.
extends Node

signal timer_changed(current_time: float)
signal timeout()

const TAG := "TimerService"

var time_left: float = 0.0
var is_active: bool = false
var is_paused: bool = false

var _sync_accumulator: float = 0.0
var _client_relay: Node


func set_client_relay(relay: Node) -> void:
	_client_relay = relay


func _process(delta: float) -> void:
	if not is_active or is_paused:
		return
	if not multiplayer.is_server():
		return

	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		is_active = false
		timeout.emit()

	timer_changed.emit(time_left)

	# Sincronizar con clientes cada 1 segundo.
	_sync_accumulator += delta
	if _sync_accumulator >= 1.0:
		_sync_accumulator = 0.0
		if _client_relay:
			_client_relay.rpc("_sync_time_client", time_left)


func start_timer(duration: float) -> void:
	if not multiplayer.is_server():
		return
	time_left = duration
	is_active = true
	is_paused = false
	NetLog.debug(TAG, "Reloj iniciado con %ss." % duration)


func stop_timer() -> void:
	if not multiplayer.is_server():
		return
	is_active = false
	NetLog.debug(TAG, "Reloj detenido.")


func set_paused(paused: bool) -> void:
	if not multiplayer.is_server():
		return
	is_paused = paused
	NetLog.debug(TAG, "Pausa cambiada a %s." % str(paused))


@rpc("authority", "call_local", "reliable")
func _rpc_set_paused(paused: bool) -> void:
	is_paused = paused


func modify_time(seconds: float) -> void:
	if not multiplayer.is_server() or not is_active:
		return
	time_left = maxf(time_left + seconds, 0.0)
	NetLog.debug(TAG, "Tiempo modificado en %ss. Restante: %ss." % [seconds, time_left])
