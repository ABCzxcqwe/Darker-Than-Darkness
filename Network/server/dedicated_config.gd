class_name DedicatedConfig
extends RefCounted
## Configuración del servidor dedicado resuelta desde la línea de comandos.
##
## Uso:
##   godot --headless -- --server --port=4300 --max=10 --map=<id> \
##     --mode=Escape --name="Mi Server" [--room-id=... --room-token=... --coordinator=...]

var is_dedicated := false
var port := NetConfig.PORT
var max_players := NetConfig.MAX_PLAYERS
var map_id := ""
var mode := NetConfig.DEFAULT_MODE
var room_name := "Servidor Dedicado"
var room_id := ""
var room_token := ""
var coordinator_url := ""


static func detect() -> bool:
	if "--server" in OS.get_cmdline_args():
		return true
	if "--server" in OS.get_cmdline_user_args():
		return true
	return false


static func from_cmdline() -> DedicatedConfig:
	var merged: Array = []
	merged.append_array(OS.get_cmdline_args())
	merged.append_array(OS.get_cmdline_user_args())
	return from_args(merged)


## Parseo puro, separado de la CLI para poder testearlo.
static func from_args(args: Array) -> DedicatedConfig:
	var cfg := DedicatedConfig.new()
	cfg.is_dedicated = "--server" in args

	for arg in args:
		if not arg.begins_with("--"):
			continue
		var eq: int = arg.find("=")
		if eq <= 2:
			continue
		var key: String = arg.substr(2, eq - 2)
		var value: String = arg.substr(eq + 1)
		match key:
			"port":
				cfg.port = int(value)
			"max", "max_players":
				cfg.max_players = clampi(int(value), NetConfig.MIN_PLAYERS, NetConfig.MAX_PLAYERS)
			"map":
				cfg.map_id = value
			"mode":
				cfg.mode = value
			"name":
				cfg.room_name = value
			"room-id":
				cfg.room_id = value
			"room-token":
				cfg.room_token = value
			"coordinator":
				cfg.coordinator_url = NetworkSettings.normalize_url(value)

	if cfg.coordinator_url == "" and cfg.room_id != "":
		cfg.coordinator_url = NetworkSettings.get_coordinator_url()

	cfg.max_players = clampi(cfg.max_players, NetConfig.MIN_PLAYERS, NetConfig.MAX_PLAYERS)
	return cfg


func to_dict() -> Dictionary:
	return {
		"port": port,
		"max_players": max_players,
		"map": map_id,
		"mode": mode,
		"name": room_name,
		"room_id": room_id,
		"room_token": room_token,
		"coordinator": coordinator_url,
	}
