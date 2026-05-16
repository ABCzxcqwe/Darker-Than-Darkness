# StatusEffectService.gd
# Gestiona efectos de estado: stun, slow, root, silence, blind.
# Solo el servidor aplica efectos. Los clientes reciben sincronización via RPC.
# Se accede via: GameServiceLocator.get_service("StatusEffectService")
#
# Post-stun:
#   Killer  → inmunidad automática = 50% de la duración del stun
#   Survivor → reducción de daño opcional, activada por la habilidad via params["post_stun_dr"]
extends Node

const EFFECT_TYPES := ["stun", "slow", "root", "silence", "blind"]

# { peer_id: { effect_name: [...instancias...] } }
var _effects: Dictionary = {}

# Inmunidad post-stun del killer: { peer_id: timer_restante }
var _stun_immunity: Dictionary = {}

# Reducción de daño post-stun de survivors: { peer_id: { timer, magnitude } }
var _post_stun_dr: Dictionary = {}

# Última velocidad conocida para detectar cambios: { peer_id: float }
var _last_speed: Dictionary = {}


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	# BUG 3 FIX: iterar sobre copia para evitar crash si unregister()
	# es llamado durante la iteración (ej: jugador muere mientras tiene stun)
	for peer_id in _effects.keys().duplicate():
		var changed := false

		for effect_name in EFFECT_TYPES:
			# Verificar que el peer sigue registrado (pudo haber sido borrado
			# por unregister() en otra iteración del mismo frame)
			if not _effects.has(peer_id):
				break

			var instances: Array = _effects[peer_id][effect_name]
			var i := instances.size() - 1

			while i >= 0:
				instances[i]["timer"] -= delta
				if instances[i]["timer"] <= 0.0:
					var expired_instance: Dictionary = instances[i]
					instances.remove_at(i)
					changed = true
					print("[StatusEffectService] ", effect_name, " expiró para peer ", peer_id)

					if effect_name == "stun":
						_on_stun_expired(peer_id, expired_instance)

					# BUG 2 FIX: notificar a clientes que el efecto terminó.
					# Sin esto la UI y lógica del cliente quedan desincronizadas
					# (ej: animación de stun sigue mostrándose después de expirar)
					_sync_effect_to_clients(peer_id, effect_name, false)
				i -= 1

		if changed:
			_recalculate_speed(peer_id)

	# Tick de inmunidad post-stun (killer)
	for peer_id in _stun_immunity.keys().duplicate():
		_stun_immunity[peer_id] -= delta
		if _stun_immunity[peer_id] <= 0.0:
			_stun_immunity.erase(peer_id)
			print("[StatusEffectService] Inmunidad post-stun expiró para peer ", peer_id)

	# Tick de reducción de daño post-stun (survivors)
	for peer_id in _post_stun_dr.keys().duplicate():
		_post_stun_dr[peer_id]["timer"] -= delta
		if _post_stun_dr[peer_id]["timer"] <= 0.0:
			_post_stun_dr.erase(peer_id)
			print("[StatusEffectService] DR post-stun expiró para peer ", peer_id)


# ── API pública ────────────────────────────────────────────────────────

## Aplica un efecto a un jugador.
## params:
##   duration      : float  — duración en segundos (obligatorio)
##   magnitude     : float  — solo para "slow", porcentaje de reducción (0.0 - 1.0)
##   post_stun_dr  : float  — solo para "stun" en survivors, reducción de daño post-stun (0.0 - 1.0)
##                            si no se pasa, el survivor no recibe DR post-stun
func apply(player_node: Node, effect_name: String, params: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if not effect_name in EFFECT_TYPES:
		push_warning("[StatusEffectService] Efecto desconocido: ", effect_name)
		return

	var peer_id := player_node.get_multiplayer_authority()
	var duration: float = params.get("duration", 1.0)

	# Bloquear stun si el killer tiene inmunidad post-stun
	if effect_name == "stun" and _stun_immunity.has(peer_id):
		print("[StatusEffectService] Stun bloqueado — killer ", peer_id, " tiene inmunidad post-stun.")
		return

	_ensure_registered(peer_id)

	var instances: Array = _effects[peer_id][effect_name]

	if instances.size() > 0:
		# Refresh: tomar la duración mayor
		var prev_duration: float = instances[0]["timer"]
		instances[0]["timer"] = maxf(prev_duration, duration)

		if effect_name == "stun":
			var old_original = instances[0].get("timer_original", duration)
			instances[0]["timer_original"] = maxf(old_original, duration)
			if params.has("post_stun_dr"):
				instances[0]["post_stun_dr"] = params.get("post_stun_dr")

		# BUG 3 FIX: el slow acumulable necesita append, no refresh.
		# _calculate_speed suma todas las instancias del array, pero apply()
		# solo guardaba una → dos slows simultáneos se comportaban como uno.
		# Ahora cada fuente de slow es una instancia separada en el array.
		# El refresh solo ocurre si es la misma fuente (mismo magnitude).
		if effect_name == "slow":
			var incoming_magnitude: float = params.get("magnitude", 0.3)
			var found := false
			for instance in instances:
				if is_equal_approx(instance["magnitude"], incoming_magnitude):
					# Misma fuente — solo refrescar duración
					instance["timer"] = maxf(instance["timer"], duration)
					found = true
					break
			if not found:
				# Fuente distinta — agregar nueva instancia acumulable
				instances.append({ "timer": duration, "magnitude": incoming_magnitude })
				print("[StatusEffectService] slow acumulado para peer ", peer_id,
					  " | magnitude: ", incoming_magnitude)

		print("[StatusEffectService] ", effect_name, " refrescado para peer ", peer_id,
			  " | duración: ", instances[0]["timer"])
	else:
		var instance := { "timer": duration }
		if effect_name == "slow":
			instance["magnitude"] = params.get("magnitude", 0.3)
		if effect_name == "stun":
			instance["timer_original"] = duration
			if params.has("post_stun_dr"):
				instance["post_stun_dr"] = params.get("post_stun_dr")
		instances.append(instance)
		print("[StatusEffectService] ", effect_name, " aplicado a peer ", peer_id,
			  " | duración: ", duration)

		if effect_name in ["stun", "root"]:
			var revive_svc := GameServiceLocator.get_service("ReviveService")
			if revive_svc:
				revive_svc.cancel_revive(peer_id)

	_recalculate_speed(peer_id)
	_sync_effect_to_clients(peer_id, effect_name, true)


## Verifica si un jugador tiene un efecto activo.
func has_effect(peer_id: int, effect_name: String) -> bool:
	if not _effects.has(peer_id):
		return false
	return _effects[peer_id][effect_name].size() > 0

func is_stunned(peer_id: int)  -> bool: return has_effect(peer_id, "stun")
func is_slowed(peer_id: int)   -> bool: return has_effect(peer_id, "slow")
func is_rooted(peer_id: int)   -> bool: return has_effect(peer_id, "root")
func is_silenced(peer_id: int) -> bool: return has_effect(peer_id, "silence")
func is_blinded(peer_id: int)  -> bool: return has_effect(peer_id, "blind")

## Devuelve true si el killer tiene inmunidad post-stun activa
func has_stun_immunity(peer_id: int) -> bool:
	return _stun_immunity.has(peer_id)

## Devuelve la reducción de daño post-stun activa para un survivor (0.0 si no tiene)
func get_post_stun_dr(peer_id: int) -> float:
	if not _post_stun_dr.has(peer_id):
		return 0.0
	return _post_stun_dr[peer_id]["magnitude"]


# BUG 1 FIX: register/unregister ahora reciben Node igual que apply().
# Antes recibían peer_id: int pero player.gd llamaba ss.register(self),
# lo que causaba que el nodo fuera usado como key del diccionario en lugar
# del peer_id — haciendo que is_stunned(), has_effect(), etc. fallaran siempre.

## Registra un jugador al entrar a la partida.
func register(player_node: Node) -> void:
	var peer_id := player_node.get_multiplayer_authority()
	_ensure_registered(peer_id)
	print("[StatusEffectService] ", peer_id, " registrado.")


## Limpia todos los efectos de un jugador.
func unregister(player_node: Node) -> void:
	var peer_id := player_node.get_multiplayer_authority()
	_effects.erase(peer_id)
	_last_speed.erase(peer_id)
	_stun_immunity.erase(peer_id)
	_post_stun_dr.erase(peer_id)
	print("[StatusEffectService] ", peer_id, " desregistrado.")


# ── Post-stun ──────────────────────────────────────────────────────────

func _on_stun_expired(peer_id: int, instance: Dictionary) -> void:
	var player_node := _get_player(peer_id)
	if not is_instance_valid(player_node):
		return

	var stun_duration: float    = instance.get("timer_original", 1.0)
	var immunity_duration: float = stun_duration * 0.5

	if player_node.character_data and player_node.character_data.team == "killer":
		_stun_immunity[peer_id] = immunity_duration
		print("[StatusEffectService] Killer ", peer_id,
			  " tiene inmunidad post-stun por ", immunity_duration, "s")
	else:
		var dr: float = instance.get("post_stun_dr", 0.0)
		if dr > 0.0:
			_post_stun_dr[peer_id] = {
				"timer":     immunity_duration,
				"magnitude": dr,
			}
			print("[StatusEffectService] Survivor ", peer_id,
				  " tiene DR post-stun ", dr * 100, "% por ", immunity_duration, "s")


# ── Internos ───────────────────────────────────────────────────────────

func _ensure_registered(peer_id: int) -> void:
	if not _effects.has(peer_id):
		_effects[peer_id] = {}
		for effect_name in EFFECT_TYPES:
			_effects[peer_id][effect_name] = []


func _recalculate_speed(peer_id: int) -> void:
	var player_node := _get_player(peer_id)
	if not is_instance_valid(player_node):
		return
	if not player_node.character_data:
		return

	var new_speed := _calculate_speed(peer_id, player_node.character_data.speed)
	var last: float = _last_speed.get(peer_id, -1.0)

	if not is_equal_approx(new_speed, last):
		_last_speed[peer_id] = new_speed
		player_node.rpc("_sync_speed", new_speed)
		print("[StatusEffectService] Speed de ", peer_id, " → ", new_speed)


func _calculate_speed(peer_id: int, base_speed: float) -> float:
	if has_effect(peer_id, "stun"):
		return 0.0
	if has_effect(peer_id, "root"):
		return 0.0
	if has_effect(peer_id, "slow"):
		var total_slow := 0.0
		for instance in _effects[peer_id]["slow"]:
			total_slow += instance["magnitude"]
		total_slow = minf(total_slow, 0.9)
		return base_speed * (1.0 - total_slow)
	return base_speed


func _sync_effect_to_clients(peer_id: int, effect_name: String, active: bool) -> void:
	var player_node := _get_player(peer_id)
	if is_instance_valid(player_node):
		player_node.rpc("_sync_effect", effect_name, active)


func _get_player(peer_id: int) -> Node:
	return get_tree().root.find_child(str(peer_id), true, false)


func _exit_tree() -> void:
	_effects.clear()
	_last_speed.clear()
	_stun_immunity.clear()
	_post_stun_dr.clear()
	print("[StatusEffectService] Limpiado.")
