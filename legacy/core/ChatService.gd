# core/ChatService.gd (Autoload)
# Sirve como relay de chat: clientes envían, servidor reenvía a todos.
extends Node

signal chat_message_received(sender_id: int, sender_name: String, message: String)

const MAX_MESSAGE_LENGTH := 200


# Llamado por la UI cuando el jugador quiere enviar un mensaje
func send_message(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	if text.length() > MAX_MESSAGE_LENGTH:
		text = text.left(MAX_MESSAGE_LENGTH)

	if multiplayer.is_server():
		_on_chat_received(multiplayer.get_unique_id(), LobbyManager.local_player_name, text)
	else:
		send_chat.rpc(text)


# Cliente -> Servidor
@rpc("any_peer", "reliable")
func send_chat(message: String) -> void:
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	var sender_name = LobbyManager.players.get(sender_id, {}).get("name", "Desconocido")
	_on_chat_received(sender_id, sender_name, message)


func _on_chat_received(sender_id: int, sender_name: String, message: String) -> void:
	if not multiplayer.is_server():
		return

	message = message.strip_edges()
	if message.is_empty():
		return

	rpc("broadcast_chat", sender_id, sender_name, message)


# Servidor -> Todos
@rpc("authority", "reliable", "call_local")
func broadcast_chat(sender_id: int, sender_name: String, message: String) -> void:
	chat_message_received.emit(sender_id, sender_name, message)
