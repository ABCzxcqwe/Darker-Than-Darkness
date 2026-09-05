# res://core/PlayerLifecycleManager.gd (Autoload)
# Punto único para registrar y desregistrar jugadores de todos los servicios.
# Elimina la duplicación de register/unregister en Player.gd, MultiplayerManager.gd, GameStateService.gd.
extends Node

func register_player(player_node: Node, peer_id: int, character_data: Resource) -> void:
	PlayerRegistry.register(peer_id, player_node)

	# Si el dueño del nodo es el propio servidor, no hay race condition posible:
	# otorgamos la visibilidad ya mismo. Si el dueño es un cliente remoto, esperamos
	# a que confirme (_notify_player_node_ready) que su copia local ya existe,
	# porque el RPC de visibilidad se perdería si le llega antes de que exista el nodo.
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


## Otorga visibilidad de sincronización en ambas direcciones:
## 1) El jugador recién registrado se hace visible para todos los peers ya conectados.
## 2) Todos los jugadores ya existentes se hacen visibles para este peer nuevo.
func _grant_synchronizer_visibility(new_player_node: Node, new_peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var viewers: Array = [1]
	for pid in multiplayer.get_peers():
		if pid not in viewers:
			viewers.append(pid)

	# 1) Nuevo jugador -> visible para todos los peers ya conectados (incluido el propio servidor)
	for viewer_id in viewers:
		grant_player_visibility_to_peer(new_player_node, viewer_id)
	print("[PlayerLifecycleManager] Visibilidad de peer ", new_peer_id, " despachada hacia: ", viewers)

	# 2) Jugadores ya existentes -> visibles para el peer nuevo
	var count := 0
	for existing_peer_id in PlayerRegistry.get_all_peer_ids():
		if existing_peer_id == new_peer_id:
			continue
		var existing_node := PlayerRegistry.get_player(existing_peer_id)
		if not existing_node or not is_instance_valid(existing_node):
			continue
		grant_player_visibility_to_peer(existing_node, new_peer_id)
		count += 1
	print("[PlayerLifecycleManager] Peer nuevo ", new_peer_id, " recibió visibilidad de ", count, " jugador(es) existentes.")


## API pública: otorga (o quita) la visibilidad del Synchronizer de 'player_node' hacia 'viewer_peer_id'.
## Despacha la llamada a la máquina que realmente es la autoridad de 'player_node' (server-side call
## si el dueño es el servidor, RPC dirigido si el dueño es un cliente remoto), porque
## MultiplayerSynchronizer.set_visibility_for solo tiene efecto si corre en esa máquina.
## Usado también por World.gd para el catch-up de espectadores que se unen tarde.
func grant_player_visibility_to_peer(player_node: Node, viewer_peer_id: int, is_visible: bool = true) -> void:
	if not multiplayer.is_server():
		return
	if not is_instance_valid(player_node):
		return

	var owner_peer_id: int = player_node.get_multiplayer_authority()
	if owner_peer_id == viewer_peer_id:
		return  # no tiene sentido volverse visible a uno mismo

	if owner_peer_id == multiplayer.get_unique_id():
		var sync := player_node.get_node_or_null("Synchronizer") as MultiplayerSynchronizer
		if sync:
			sync.set_visibility_for(viewer_peer_id, is_visible)
			if is_visible:
				sync.update_visibility(viewer_peer_id)
		else:
			push_warning("[PlayerLifecycleManager] Jugador ", owner_peer_id, " sin nodo 'Synchronizer'.")
		return

	if player_node.has_method("_rpc_set_synchronizer_visibility"):
		player_node.rpc_id(owner_peer_id, "_rpc_set_synchronizer_visibility", viewer_peer_id, is_visible)
	else:
		push_warning("[PlayerLifecycleManager] Jugador ", owner_peer_id, " no tiene el RPC de visibilidad (actualizá Player.gd).")


## Llamado por el propio cliente dueño de un jugador, una vez que su copia local
## del nodo (recibida vía MultiplayerSpawner) ya terminó de instanciarse. Recién acá
## es seguro pedirle que modifique la visibilidad de su Synchronizer.
@rpc("any_peer", "reliable")
func _notify_player_node_ready(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id:
		push_warning("[PlayerLifecycleManager] Peer ", sender, " intentó confirmar el nodo de otro peer (", peer_id, "). Ignorado.")
		return

	var player_node := PlayerRegistry.get_player(peer_id)
	if not player_node or not is_instance_valid(player_node):
		push_warning("[PlayerLifecycleManager] _notify_player_node_ready: nodo de peer ", peer_id, " no encontrado en el registro.")
		return

	print("[PlayerLifecycleManager] Peer ", peer_id, " confirmó que su nodo local está listo. Otorgando visibilidad.")
	_grant_synchronizer_visibility(player_node, peer_id)


func unregister_player(peer_id: int, player_node: Node) -> void:
	PlayerRegistry.unregister(peer_id)

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
