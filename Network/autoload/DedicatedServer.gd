# res://Network/autoload/DedicatedServer.gd
extends Node
## Bootstrap del servidor dedicado (headless).
##
## Detecta `--server`, delega la configuración a DedicatedConfig y el heartbeat
## a CoordinatorHeartbeat. No registra jugador local ni muestra UI.

const TAG := "DedicatedServer"

var is_dedicated := false
## Diccionario por compatibilidad/debug; la fuente tipada es `dedicated_config`.
var config: Dictionary = {}
var dedicated_config: DedicatedConfig = null
var room_id := ""
var room_token := ""
var coordinator_url := ""
var _heartbeat: CoordinatorHeartbeat = null


func _ready() -> void:
	dedicated_config = DedicatedConfig.from_cmdline()
	is_dedicated = dedicated_config.is_dedicated
	if not is_dedicated:
		return
	config = dedicated_config.to_dict()
	NetLog.info(TAG, "Boot headless | puerto=%d max=%d mapa='%s' modo='%s' sala='%s'" % [
		dedicated_config.port,
		dedicated_config.max_players,
		dedicated_config.map_id,
		dedicated_config.mode,
		dedicated_config.room_name,
	])
	call_deferred("_boot_dedicated")


func _boot_dedicated() -> void:
	var nm := get_node_or_null("/root/NetworkManager")
	if nm == null:
		NetLog.error(TAG, "NetworkManager no disponible; abortando boot dedicado.")
		get_tree().quit(1)
		return

	var ok := false
	if nm.has_method("start_dedicated_server"):
		ok = nm.start_dedicated_server(
			dedicated_config.room_name,
			dedicated_config.map_id,
			dedicated_config.mode,
			dedicated_config.max_players,
			dedicated_config.port
		)
	else:
		NetLog.error(TAG, "NetworkManager no implementa start_dedicated_server().")

	if not ok:
		NetLog.error(TAG, "No se pudo iniciar el servidor dedicado. Abortando proceso.")
		get_tree().quit(1)
		return

	room_id = dedicated_config.room_id
	room_token = dedicated_config.room_token
	coordinator_url = dedicated_config.coordinator_url
	if room_id != "" and coordinator_url != "":
		_heartbeat = CoordinatorHeartbeat.new()
		_heartbeat.name = "CoordinatorHeartbeat"
		add_child(_heartbeat)
		_heartbeat.setup(room_id, room_token, coordinator_url)

	NetLog.info(TAG, "Servidor dedicado listo.")
	# Cargar el hub también en headless: recibe/retransmite el estado de avatares.
	get_tree().change_scene_to_file.call_deferred(NetScenes.SESSION)


func _exit_tree() -> void:
	if _heartbeat and is_instance_valid(_heartbeat):
		_heartbeat.stop()
