# res://Network/autoload/ChatService.gd
extends Node
## Relay de chat: los clientes envían al servidor y el servidor reenvía a todos.
##
## Validaciones server-side:
## - El emisor debe estar registrado en LobbyManager.players.
## - El mensaje se recorta a NetConfig.CHAT_MAX_LENGTH.
## - Token bucket por peer para evitar flood.

signal chat_message_received(sender_id: int, sender_name: String, message: String)

const TAG := "ChatService"
const MAX_MESSAGE_LENGTH := NetConfig.CHAT_MAX_LENGTH

var _buckets: Dictionary = {}  # peer_id -> {tokens: float, last: float}


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


## Llamado por la UI cuando el jugador quiere enviar un mensaje.
func send_message(text: String) -> void:
	var clean := _sanitize(text)
	if clean.is_empty():
		return
	if multiplayer.is_server():
		_on_chat_received(multiplayer.get_unique_id(), LobbyManager.local_player_name, clean)
	else:
		rpc_id(LobbyManager.server_peer_id, "send_chat", clean)


## Cliente -> Servidor. Solo el servidor lo procesa.
@rpc("any_peer", "reliable")
func send_chat(message: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	if not LobbyManager.players.has(sender_id):
		NetLog.debug(TAG, "Mensaje ignorado de peer no registrado %d" % sender_id)
		return
	if not _allow_message(sender_id):
		NetLog.debug(TAG, "Rate limit de chat para peer %d" % sender_id)
		return

	var clean := _sanitize(message)
	if clean.is_empty():
		return
	var sender_name := String(LobbyManager.players[sender_id].get("name", "Desconocido"))
	_on_chat_received(sender_id, sender_name, clean)


func _on_chat_received(sender_id: int, sender_name: String, message: String) -> void:
	if not multiplayer.is_server():
		return
	var clean := _sanitize(message)
	if clean.is_empty():
		return
	rpc("broadcast_chat", sender_id, sender_name, clean)


## Servidor -> Todos.
@rpc("authority", "reliable", "call_local")
func broadcast_chat(sender_id: int, sender_name: String, message: String) -> void:
	chat_message_received.emit(sender_id, sender_name, message)


func _sanitize(text: String) -> String:
	var out := text.strip_edges()
	out = out.replace("\r", "")
	out = out.replace("\t", " ")
	if out.length() > MAX_MESSAGE_LENGTH:
		out = out.left(MAX_MESSAGE_LENGTH)
	return out.strip_edges()


func _allow_message(peer_id: int) -> bool:
	var now := float(Time.get_ticks_msec()) / 1000.0
	var bucket: Dictionary = _buckets.get(peer_id, {"tokens": NetConfig.CHAT_BURST, "last": now})
	var elapsed: float = max(0.0, now - float(bucket["last"]))
	bucket["tokens"] = min(
		NetConfig.CHAT_BURST,
		float(bucket["tokens"]) + elapsed * NetConfig.CHAT_REFILL_PER_SEC
	)
	bucket["last"] = now
	if float(bucket["tokens"]) < 1.0:
		_buckets[peer_id] = bucket
		return false
	bucket["tokens"] = float(bucket["tokens"]) - 1.0
	_buckets[peer_id] = bucket
	return true


func _on_peer_disconnected(peer_id: int) -> void:
	_buckets.erase(peer_id)
