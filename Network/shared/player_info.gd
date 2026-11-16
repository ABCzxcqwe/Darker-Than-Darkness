class_name PlayerInfo
extends RefCounted
## Esquema único de las entradas de `LobbyManager.players`.
##
## Se mantiene como Dictionary para que viaje sin problemas por RPC. Las claves
## que empiezan con `_` son internas del servidor y nunca se envían al cliente.

const ROLE_SURVIVOR := "survivor"
const ROLE_KILLER := "killer"
const ROLE_SPECTATOR := "spectator"

const PRESENCE_HUB := "hub"
const PRESENCE_MATCH := "match"
const PRESENCE_SPECTATE := "spectate"


static func make(player_name: String, is_host: bool, is_spectator: bool = false) -> Dictionary:
	return {
		"name": sanitize_name(player_name),
		"is_host": is_host,
		"character_id": -1,
		"killer_points": 0,
		"assigned_role": ROLE_SPECTATOR if is_spectator else ROLE_SURVIVOR,
		"is_spectator": is_spectator,
		"afk": false,
		"presence": PRESENCE_HUB,
	}


static func sanitize_name(raw: String, fallback: String = "Player") -> String:
	var clean := raw.strip_edges()
	clean = clean.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	while clean.contains("  "):
		clean = clean.replace("  ", " ")
	clean = clean.strip_edges()
	if clean.length() > NetConfig.NAME_MAX_LENGTH:
		clean = clean.left(NetConfig.NAME_MAX_LENGTH).strip_edges()
	return clean if clean != "" else fallback


static func public_entry(entry: Dictionary) -> Dictionary:
	var copy: Dictionary = {}
	for key in entry:
		if str(key).begins_with("_"):
			continue
		copy[key] = entry[key]
	return copy


static func public_copy(players: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for peer_id in players:
		out[peer_id] = public_entry(players[peer_id])
	return out
