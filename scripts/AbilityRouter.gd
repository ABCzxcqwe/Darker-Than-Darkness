# AbilityRouter.gd  (Autoload)
# Recibe peticiones de habilidad desde los clientes.
# Valida, resuelve la versión correcta (normal o evolucionada) y despacha.
# NO tiene ningún mapa hardcodeado de habilidades.
# Para añadir una habilidad nueva: crea el .gd en la carpeta del personaje
# y asigna el script_path en su AbilityData.tres.
extends Node


func _ready() -> void:
	print("[AbilityRouter] listo.")


# ── RPC: el cliente llama esto en el servidor ──────────────────────────
@rpc("any_peer", "reliable")
func request_ability(slot_index: int, direction: Vector2) -> void:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var peer_id: int   = sender_id if sender_id != 0 else 1

	# ── 1. ¿Hay partida activa? ────────────────────────────────────────
	var state = GameServiceLocator.get_service("GameStateService")
	if not state or not state.is_in_game():
		print("[AbilityRouter] Sin partida activa. Bloqueado.")
		return

	# ── 2. ¿El jugador existe? ─────────────────────────────────────────
	var player_node := _get_player_node(peer_id)
	if not player_node:
		push_warning("[AbilityRouter] No se encontró jugador para peer ", peer_id)
		return

	# ── 3. ¿El jugador tiene CharacterData? ───────────────────────────
	var char_data: CharacterData = player_node.character_data
	if not char_data:
		push_warning("[AbilityRouter] Jugador ", peer_id, " sin character_data.")
		return

	# ── 4. ¿El jugador está vivo? ─────────────────────────────────────
	if player_node.health <= 0:
		print("[AbilityRouter] Jugador ", peer_id, " sin vida. Bloqueado.")
		return

	# ── 5. ¿Tiene algo en ese slot? ───────────────────────────────────
	if slot_index < 0 or slot_index >= char_data.ability_slots.size():
		push_warning("[AbilityRouter] Slot ", slot_index, " fuera de rango para peer ", peer_id)
		return
	var base_data: AbilityData = char_data.ability_slots[slot_index]
	if not base_data:
		print("[AbilityRouter] Slot ", slot_index, " vacío para peer ", peer_id)
		return

	# ── 6. Resolver versión: ¿evolucionada o normal? ──────────────────
	var evolution_service: Node = GameServiceLocator.get_service("EvolutionService")
	var is_evolved: bool = evolution_service != null and evolution_service.is_evolved(peer_id, slot_index)
	var ability_data: AbilityData = base_data.evolved_version if (is_evolved and base_data.evolved_version) else base_data

	# ── 7. ¿Cooldown listo? ───────────────────────────────────────────
	var cd = GameServiceLocator.get_service("CooldownService")
	if cd and not cd.is_ready(peer_id, ability_data.display_name):
		print("[AbilityRouter] Bloqueado por cooldown: ", ability_data.display_name,
			  " | restante: ", cd.get_remaining(peer_id, ability_data.display_name), "s")
		return

	# ── 8. ¿Efectos que bloquean? ─────────────────────────────────────
	var status = GameServiceLocator.get_service("StatusEffectService")
	if status:
		if status.is_silenced(peer_id):
			print("[AbilityRouter] Bloqueado por silence.")
			return
		if status.is_stunned(peer_id) and not ability_data.can_use_while_stunned:
			print("[AbilityRouter] Bloqueado por stun.")
			return

	# ── 9. ¿Existe el script? ─────────────────────────────────────────
	var ability_script: GDScript = ability_data.ability_script
	if not ability_script:
		push_error("[AbilityRouter] ability_script no asignado en AbilityData para '", ability_data.display_name, "'")
		return

	# ── 10. Instanciar y ejecutar ─────────────────────────────────────
	var handler: AbilityBase = ability_script.new()
	handler.activate(player_node, ability_data, direction)

	print("[AbilityRouter] '", ability_data.display_name, "' despachado para peer ", peer_id,
		  " (", "evolucionada" if is_evolved else "normal", ")")

	# ── 11. Consumir evolución si aplica ──────────────────────────────
	if is_evolved and evolution_service:
		evolution_service.consume_evolution(peer_id, slot_index)

	# ── 12. Iniciar cooldown ──────────────────────────────────────────
	if cd:
		cd.start(peer_id, ability_data.display_name, ability_data.cooldown, slot_index)


# ── Helper ─────────────────────────────────────────────────────────────
func _get_player_node(peer_id: int) -> Node:
	return get_tree().root.find_child(str(peer_id), true, false)
