# res://core/PlayerLifecycleManager.gd (Autoload)
# Punto único para registrar y desregistrar jugadores de todos los servicios.
# Elimina la duplicación de register/unregister en Player.gd, MultiplayerManager.gd, GameStateService.gd.
extends Node

func register_player(player_node: Node, peer_id: int, character_data: Resource) -> void:
	PlayerRegistry.register(peer_id, player_node)

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

	var cd = GameServiceLocator.cooldown
	if cd and cd.has_method("clear_player"):
		cd.clear_player(peer_id)
