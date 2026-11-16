# res://Network/autoload/PlayerLifecycleManager.gd
extends Node
## Punto único de registro/desregistro de jugadores y visibilidad de
## RollbackSynchronizer (netfox).
##
## Reemplaza a `PlayerRegistry`: el mapa `peer_id -> Node` vive acá. Los
## consumidores deben usar `PlayerLifecycleManager.get_player()` /
## `get_all_peer_ids()` directamente. La identidad lógica del jugador se obtiene
## con `get_owner_peer_id()` (el Player pertenece al servidor).

const TAG := "PlayerLifecycleManager"

## Peers que ya confirmaron tener su World local creado (y por lo tanto sus
## nodos de jugador instanciados). Solo a ellos se les puede otorgar visibilidad
## del RollbackSynchronizer de netfox.
##
## Por qué: netfox envía estados por RPC al nodo del jugador. Si el peer todavía
## no creó ese nodo, el RPC falla. El gate de "_world_ready" evita enviar estados
## a rutas inexistentes y sirve para late join/espectadores.
var _world_ready_peers: Dictionary = {}
var _players: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _on_peer_disconnected(peer_id: int) -> void:
	# Si vuelve a conectarse, tiene que reconfirmar su World antes de recibir
	# visibilidad otra vez.
	_world_ready_peers.erase(peer_id)
	_players.erase(peer_id)


# ── Registro de nodos ──

## Registro básico, válido en todos los peers. El servidor además llama a
## `register_player()` para registrar servicios y visibilidad.
func register_node(peer_id: int, node: Node) -> void:
	if node == null:
		return
	_players[peer_id] = node


func get_player(peer_id: int) -> Node:
	return _players.get(peer_id, null) as Node


## Identidad lógica de un nodo de jugador. Con netfox el Player está autorizado
## por el servidor (peer 1) y el dueño real vive en `owner_peer_id`. Los nodos
## que no son Player (avatares del hub, hitboxes) siguen usando su autoridad.
func get_owner_peer_id(node: Node) -> int:
	if node == null:
		return 0
	if node.has_method("get_owner_peer_id"):
		return int(node.get_owner_peer_id())
	return node.get_multiplayer_authority()


func get_all_peer_ids() -> Array:
	return _players.keys()


func get_all_players() -> Array:
	return _players.values()


func has_player(peer_id: int) -> bool:
	return _players.has(peer_id)


## El servidor marca a un peer como "World listo". A partir de acá es seguro
## otorgarle visibilidad de Synchronizer (sus nodos ya existen en su escena).
func mark_peer_world_ready(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_world_ready_peers[peer_id] = true


## Registro completo, solo en el servidor: nodo + servicios + visibilidad.
func register_player(player_node: Node, peer_id: int, character_data: Resource) -> void:
	register_node(peer_id, player_node)

	# Si el dueño del nodo es el propio servidor, no hay race condition posible:
	# otorgamos la visibilidad ya mismo. Si el dueño es un cliente remoto,
	# esperamos a que confirme (_notify_player_node_ready) que su copia local ya
	# existe, porque el RPC de visibilidad se perdería si llega antes.
	if peer_id == multiplayer.get_unique_id():
		_grant_synchronizer_visibility(player_node, peer_id)

	var hs = GameServiceLocator.health
	if hs:
		if hs.has_method("register"):
			hs.register(player_node)
		elif hs.has_method("register_survivor"):
			hs.call("register_survivor", player_node)

	var ss = GameServiceLocator.status_effect
	if ss and ss.has_method("register"):
		ss.register(player_node)

	var es = GameServiceLocator.evolution
	if es and es.has_method("register_player"):
		es.register_player(peer_id)

	var abs_svc = GameServiceLocator.ability_state
	if abs_svc and abs_svc.has_method("register_player"):
		abs_svc.register_player(peer_id, character_data)

	var stam_svc = GameServiceLocator.stamina
	if stam_svc and stam_svc.has_method("register_player"):
		stam_svc.register_player(peer_id, character_data)

	var tp = GameServiceLocator.tp
	if tp and tp.has_method("register_player"):
		tp.register_player(peer_id, character_data)

	var ms_svc = GameServiceLocator.match_stats
	if ms_svc and ms_svc.has_method("register_player"):
		ms_svc.register_player(peer_id, character_data)


func unregister_player(peer_id: int, player_node: Node) -> void:
	_players.erase(peer_id)

	var hs = GameServiceLocator.health
	if hs and hs.has_method("unregister"):
		hs.unregister(peer_id)

	var ss = GameServiceLocator.status_effect
	if ss and ss.has_method("unregister") and is_instance_valid(player_node):
		ss.unregister(player_node)

	var tp = GameServiceLocator.tp
	if tp and tp.has_method("unregister_player"):
		tp.unregister_player(peer_id)

	var es = GameServiceLocator.evolution
	if es and es.has_method("unregister_player"):
		es.unregister_player(peer_id)

	var abs_svc = GameServiceLocator.ability_state
	if abs_svc and abs_svc.has_method("unregister_player"):
		abs_svc.unregister_player(peer_id)

	var stam_svc = GameServiceLocator.stamina
	if stam_svc and stam_svc.has_method("unregister_player"):
		stam_svc.unregister_player(peer_id)

	var ms_svc = GameServiceLocator.match_stats
	if ms_svc and ms_svc.has_method("unregister_player"):
		ms_svc.unregister_player(peer_id)

	var cd = GameServiceLocator.cooldown
	if cd and cd.has_method("clear_player"):
		cd.clear_player(peer_id)


# ── Visibilidad de Synchronizer ──

## Otorga visibilidad de sincronización en ambas direcciones, pero SOLO a/desde
## peers que ya confirmaron tener su World creado (ver _world_ready_peers).
func _grant_synchronizer_visibility(new_player_node: Node, new_peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var server_id := multiplayer.get_unique_id()
	var viewers: Array = [server_id]
	for pid in _world_ready_peers:
		if pid not in viewers:
			viewers.append(pid)

	# 1) Nuevo jugador -> visible para los peers que ya tienen su World listo.
	for viewer_id in viewers:
		grant_player_visibility_to_peer(new_player_node, viewer_id)

	# 2) Jugadores ya existentes -> visibles para el peer nuevo, si confirmó.
	if not _world_ready_peers.has(new_peer_id):
		return
	var count := 0
	for existing_peer_id in get_all_peer_ids():
		if existing_peer_id == new_peer_id:
			continue
		var existing_node := get_player(existing_peer_id)
		if not existing_node or not is_instance_valid(existing_node):
			continue
		grant_player_visibility_to_peer(existing_node, new_peer_id)
		count += 1
	NetLog.debug(TAG, "Peer %d recibió visibilidad de %d jugador(es) existentes." % [new_peer_id, count])


## Otorga (o quita) la visibilidad del RollbackSynchronizer de `player_node`
## hacia `viewer_peer_id`. Usado también por World.gd para espectadores.
func grant_player_visibility_to_peer(player_node: Node, viewer_peer_id: int, is_visible: bool = true) -> void:
	if not multiplayer.is_server():
		return
	if not is_instance_valid(player_node):
		return

	var owner_peer_id: int = PlayerLifecycleManager.get_owner_peer_id(player_node)
	var rbs := player_node.get_node_or_null("RollbackSynchronizer")
	if rbs == null:
		NetLog.warn(TAG, "Jugador %d sin nodo 'RollbackSynchronizer'." % owner_peer_id)
		return
	var filter = rbs.get("visibility_filter")
	if filter == null:
		NetLog.warn(TAG, "Jugador %d sin visibility_filter de netfox." % owner_peer_id)
		return
	filter.set_visibility_for(viewer_peer_id, is_visible)
	if is_visible:
		filter.update_visibility()


## Llamado por el cliente dueño de un jugador cuando su copia local del nodo ya
## terminó de instanciarse.
@rpc("any_peer", "reliable")
func _notify_player_node_ready(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id:
		NetLog.warn(TAG, "Peer %d intentó confirmar el nodo de otro peer (%d). Ignorado." % [sender, peer_id])
		return

	var player_node := get_player(peer_id)
	if not player_node or not is_instance_valid(player_node):
		NetLog.warn(TAG, "_notify_player_node_ready: nodo de peer %d no encontrado." % peer_id)
		return

	NetLog.debug(TAG, "Peer %d confirmó su nodo local. Otorgando visibilidad." % peer_id)
	_grant_synchronizer_visibility(player_node, peer_id)
