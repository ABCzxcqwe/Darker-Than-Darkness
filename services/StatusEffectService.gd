# StatusEffectService.gd
# Gestiona efectos de estado: stun, slow, root, silence, blind.
# Solo el servidor aplica efectos. Los clientes reciben sincronización via RPC.
# Se accede via: GameServiceLocator.get_service("StatusEffectService")
#
# Post-stun:
#   Killer  → inmunidad automática = 50% de la duración del stun
#   Survivor → reducción de daño opcional, activada por la habilidad via params["post_stun_dr"]
extends Node

const EFFECT_TYPES := ["stun", "slow", "root", "silence", "blind", "speed_boost", "stamina_reduction", "protection", "bleed", "damage_boost", "damage_reduction", "invisibility", "sprint_disabled"]

# Efectos con acumulación por fuente: cada fuente distinta crea su propia
# instancia en el array. Los demás efectos refrescan la instancia existente.
const ACCUMULATE_EFFECTS := ["bleed", "damage_boost", "damage_reduction", "blind"]

# { peer_id: { effect_name: [...instancias...] } }
var _effects: Dictionary = {}

# Inmunidad post-stun del killer: { peer_id: timer_restante }
var _stun_immunity: Dictionary = {}

# Reducción de daño post-stun de survivors: { peer_id: { timer, magnitude } }
var _post_stun_dr: Dictionary = {}

# Última velocidad conocida para detectar cambios: { peer_id: float }
var _last_speed: Dictionary = {}

var _stamina_drain_originals: Dictionary = {}  # { peer_id: float }

var _rage_stun_hits: Dictionary = {}  # { peer_id: int }

var _revive_service: Node = null
var _health_service: Node = null


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	for __dbg_pid in _effects.keys():
		for __dbg_eff in ["root", "silence"]:
			if has_effect(__dbg_pid, __dbg_eff):
				var __dbg_t: float = _effects[__dbg_pid][__dbg_eff][0]["timer"] if _effects[__dbg_pid][__dbg_eff].size() > 0 else -1.0
				if int(Time.get_ticks_msec() / 500) % 4 == 0:
					print("[StatusEffectService][DBG] peer ", __dbg_pid, " ", __dbg_eff, " timer=", __dbg_t)
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

				# DoT (bleed): tick de daño por intervalo.
				if effect_name == "bleed":
					instances[i]["tick_timer"] -= delta
					if instances[i]["tick_timer"] <= 0.0:
						_apply_bleed_tick(peer_id, instances[i])
						instances[i]["tick_timer"] = instances[i]["tick_interval"]

				if instances[i]["timer"] <= 0.0:
					var expired_instance: Dictionary = instances[i]
					instances.remove_at(i)
					changed = true
					print("[StatusEffectService] ", effect_name, " expiró para peer ", peer_id)

					if effect_name == "stun":
						_on_stun_expired(peer_id, expired_instance)

					if effect_name == "stamina_reduction":
						_on_stamina_reduction_expired(peer_id)

					if effect_name == "blind":
						_refresh_blind_visual(peer_id)

					# Solo notificar a clientes cuando TODAS las instancias expiraron.
					# Ej: slow puede tener múltiples fuentes — si una expira pero otra
					# sigue activa, el cliente no debe eliminar la notificación aún.
					if instances.is_empty():
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

	if effect_name == "stun" and _is_rage_active(peer_id):
		var resist := _get_rage_resistance(peer_id)
		if resist > 0.0:
			var orig := duration
			duration = maxf(0.2, duration * (1.0 - resist))
			print("[StatusEffectService] Rage resistencia stun peer ", peer_id, " ", resist*100, "% ", orig, "->", duration)
			_rage_stun_hits[peer_id] = _rage_stun_hits.get(peer_id, 0) + 1

	# Bloquear stun si el killer tiene inmunidad post-stun
	if effect_name == "stun" and _stun_immunity.has(peer_id):
		print("[StatusEffectService] Stun bloqueado — killer ", peer_id, " tiene inmunidad post-stun.")
		return

	_ensure_registered(peer_id)

	var instances: Array = _effects[peer_id][effect_name]

	if instances.size() > 0:
		if effect_name == "stun":
			var is_killer: bool = is_instance_valid(player_node) and player_node.character_data and player_node.character_data.team == "killer"
			var max_stun := 5.0 if is_killer else INF
			instances[0]["timer"] = minf(instances[0]["timer"] + duration, max_stun)
			instances[0]["timer_original"] = minf(instances[0].get("timer_original", 0.0) + duration, max_stun)
			if params.has("post_stun_dr"):
				instances[0]["post_stun_dr"] = params.get("post_stun_dr")
			print("[StatusEffectService] stun acumulado para peer ", peer_id,
				  " | duración total restante: ", instances[0]["timer"])
		else:
			# Los efectos acumulables gestionan su propio refresh por fuente.
			if not effect_name in ACCUMULATE_EFFECTS:
				var prev_duration: float = instances[0]["timer"]
				instances[0]["timer"] = maxf(prev_duration, duration)

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

		if effect_name == "bleed":
			var incoming_dps: float = params.get("dps", 5.0)
			var incoming_interval: float = params.get("tick_interval", 1.0)
			var found_bleed := false
			for instance in instances:
				if is_equal_approx(instance.get("dps", 0.0), incoming_dps) \
						and is_equal_approx(instance.get("tick_interval", 0.0), incoming_interval):
					instance["timer"] = maxf(instance["timer"], duration)
					found_bleed = true
					break
			if not found_bleed:
				instances.append({
					"timer": duration,
					"dps": incoming_dps,
					"tick_interval": incoming_interval,
					"tick_timer": incoming_interval,
				})
				print("[StatusEffectService] bleed acumulado para peer ", peer_id,
					  " | dps: ", incoming_dps, " | intervalo: ", incoming_interval)

		if effect_name == "damage_boost":
			var incoming_mult: float = params.get("multiplier", 1.5)
			var found_boost := false
			for instance in instances:
				if is_equal_approx(instance.get("multiplier", 0.0), incoming_mult):
					instance["timer"] = maxf(instance["timer"], duration)
					found_boost = true
					break
			if not found_boost:
				instances.append({ "timer": duration, "multiplier": incoming_mult })
				print("[StatusEffectService] damage_boost acumulado para peer ", peer_id,
					  " | multiplier: ", incoming_mult)

		if effect_name == "damage_reduction":
			var incoming_mag: float = params.get("magnitude", 0.5)
			var found_red := false
			for instance in instances:
				if is_equal_approx(instance.get("magnitude", 0.0), incoming_mag):
					instance["timer"] = maxf(instance["timer"], duration)
					found_red = true
					break
			if not found_red:
				instances.append({ "timer": duration, "magnitude": incoming_mag })
				print("[StatusEffectService] damage_reduction acumulado para peer ", peer_id,
					  " | magnitude: ", incoming_mag)

		if effect_name == "blind":
			var incoming_factor: float = params.get("vision_factor", 0.5)
			var incoming_miss: float = params.get("miss_chance", 0.3)
			var found_blind := false
			for instance in instances:
				if is_equal_approx(instance.get("vision_factor", 0.0), incoming_factor) \
						and is_equal_approx(instance.get("miss_chance", 0.0), incoming_miss):
					instance["timer"] = maxf(instance["timer"], duration)
					found_blind = true
					break
			if not found_blind:
				instances.append({
					"timer": duration,
					"vision_factor": incoming_factor,
					"miss_chance": incoming_miss,
				})
				print("[StatusEffectService] blind acumulado para peer ", peer_id,
					  " | factor: ", incoming_factor, " | miss: ", incoming_miss)

		if effect_name == "stamina_reduction":
			var incoming_magnitude: float = params.get("magnitude", 0.7)
			var found := false
			for instance in instances:
				if is_equal_approx(instance["magnitude"], incoming_magnitude):
					instance["timer"] = maxf(instance["timer"], duration)
					found = true
					break
			if not found:
				instances.append({ "timer": duration, "magnitude": incoming_magnitude })
				print("[StatusEffectService] stamina_reduction acumulado para peer ", peer_id,
					  " | magnitude: ", incoming_magnitude)
			_recalculate_stamina_drain(peer_id, player_node)

		print("[StatusEffectService] ", effect_name, " refrescado para peer ", peer_id,
			  " | duración: ", instances[0]["timer"])
	else:
		var instance := { "timer": duration }
		if effect_name == "slow":
			instance["magnitude"] = params.get("magnitude", 0.3)
		if effect_name == "bleed":
			instance["dps"] = params.get("dps", 5.0)
			instance["tick_interval"] = params.get("tick_interval", 1.0)
			instance["tick_timer"] = instance["tick_interval"]
		if effect_name == "damage_boost":
			instance["multiplier"] = params.get("multiplier", 1.5)
		if effect_name == "damage_reduction":
			instance["magnitude"] = params.get("magnitude", 0.5)
		if effect_name == "blind":
			instance["vision_factor"] = params.get("vision_factor", 0.5)
			instance["miss_chance"] = params.get("miss_chance", 0.3)
		if effect_name == "stun":
			var is_killer: bool = is_instance_valid(player_node) and player_node.character_data and player_node.character_data.team == "killer"
			var max_stun := 5.0 if is_killer else INF
			instance["timer_original"] = minf(duration, max_stun)
			instance["timer"] = instance["timer_original"]
			if params.has("post_stun_dr"):
				instance["post_stun_dr"] = params.get("post_stun_dr")
		instances.append(instance)
		if effect_name == "speed_boost":
			instance["multiplier"] = params.get("multiplier", 1.3)
		if effect_name == "stamina_reduction":
			instance["magnitude"] = params.get("magnitude", 0.7)
			if not _stamina_drain_originals.has(peer_id):
				_stamina_drain_originals[peer_id] = player_node.character_data.stamina_sprint_drain
			_recalculate_stamina_drain(peer_id, player_node)
		print("[StatusEffectService] ", effect_name, " aplicado a peer ", peer_id,
			  " | duración: ", duration)

		if effect_name in ["stun", "root"]:
			var revive_svc = _revive_service
			if revive_svc:
				revive_svc.cancel_revive(peer_id)

	_recalculate_speed(peer_id)
	var notify_duration: float = instances[0]["timer"] if instances.size() > 0 else duration
	_sync_effect_to_clients(peer_id, effect_name, true, notify_duration)

	if effect_name == "blind":
		_refresh_blind_visual(peer_id)


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
func is_sped_up(peer_id: int)  -> bool: return has_effect(peer_id, "speed_boost")
func is_stamina_reduced(peer_id: int) -> bool: return has_effect(peer_id, "stamina_reduction")
func is_bleeding(peer_id: int) -> bool: return has_effect(peer_id, "bleed")
func is_invisible(peer_id: int) -> bool: return has_effect(peer_id, "invisibility")
func is_sprint_disabled(peer_id: int) -> bool: return has_effect(peer_id, "sprint_disabled")

## Multiplicador de daño efectivo del atacante (1.0 = sin buff).
## Acumulativo aditivo: 1.0 + Σ(multiplier_i − 1.0), cap 2.5.
func get_damage_boost(peer_id: int) -> float:
	if not _effects.has(peer_id) or _effects[peer_id]["damage_boost"].is_empty():
		return 1.0
	var total := 1.0
	for instance in _effects[peer_id]["damage_boost"]:
		total += instance.get("multiplier", 1.5) - 1.0
	return minf(total, 2.5)

## Reducción de daño efectiva del objetivo (0.0 = sin buff).
## Acumulativo aditivo: Σ magnitude_i, cap 0.9.
func get_damage_reduction(peer_id: int) -> float:
	if not _effects.has(peer_id) or _effects[peer_id]["damage_reduction"].is_empty():
		return 0.0
	var total := 0.0
	for instance in _effects[peer_id]["damage_reduction"]:
		total += instance.get("magnitude", 0.5)
	return minf(total, 0.9)

## Probabilidad de que un cegado falle sus ataques (máximo entre fuentes activas).
func get_blind_miss_chance(peer_id: int) -> float:
	if not _effects.has(peer_id) or _effects[peer_id]["blind"].is_empty():
		return 0.0
	var best := 0.0
	for instance in _effects[peer_id]["blind"]:
		best = maxf(best, instance.get("miss_chance", 0.3))
	return best

## Devuelve true si el killer tiene inmunidad post-stun activa
func has_stun_immunity(peer_id: int) -> bool:
	return _stun_immunity.has(peer_id)

## Activa o desactiva inmunidad a stun manualmente (usado por habilidades).
## duration > 0.0 → concede inmunidad por esa duración
## duration = 0.0 → elimina la inmunidad inmediatamente
func grant_stun_immunity(peer_id: int, duration: float) -> void:
	if not multiplayer.is_server():
		return
	if duration > 0.0:
		_stun_immunity[peer_id] = duration
	else:
		_stun_immunity.erase(peer_id)

## Devuelve la reducción de daño post-stun activa para un survivor (0.0 si no tiene)
func get_post_stun_dr(peer_id: int) -> float:
	if not _post_stun_dr.has(peer_id):
		return 0.0
	return _post_stun_dr[peer_id]["magnitude"]

func clear_rage_resistance(peer_id: int) -> void:
	_rage_stun_hits.erase(peer_id)


# BUG 1 FIX: register/unregister ahora reciben Node igual que apply().
# Antes recibían peer_id: int pero player.gd llamaba ss.register(self),
# lo que causaba que el nodo fuera usado como key del diccionario en lugar
# del peer_id — haciendo que is_stunned(), has_effect(), etc. fallaran siempre.

## Registra un jugador al entrar a la partida.
func register(player_node: Node) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := player_node.get_multiplayer_authority()
	_ensure_registered(peer_id)
	print("[StatusEffectService] ", peer_id, " registrado.")


func _is_rage_active(peer_id: int) -> bool:
	var abs_svc = GameServiceLocator.ability_state
	if abs_svc and abs_svc.has_method("is_mode_active"):
		return abs_svc.is_mode_active(peer_id, 4)
	return false

func _get_rage_resistance(peer_id: int) -> float:
	var player_node := _get_player(peer_id)
	if not is_instance_valid(player_node) or not player_node.character_data:
		return 0.0
	var slots: Array = player_node.character_data.ability_slots
	if slots.size() <= 4 or not slots[4]:
		return 0.0
	var rage_data: AbilityData = slots[4]
	var base: float = rage_data.rage_stun_resistance_base
	var decay: float = rage_data.rage_stun_resistance_decay
	if base <= 0.0:
		base = 0.5
		decay = 0.1
	var hits: int = _rage_stun_hits.get(peer_id, 0)
	var resist: float = base - decay * hits
	return clampf(resist, 0.0, 0.9)

## Limpia todos los efectos de un jugador.
func unregister(player_node: Node) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := player_node.get_multiplayer_authority()
	_effects.erase(peer_id)
	_last_speed.erase(peer_id)
	_stun_immunity.erase(peer_id)
	_post_stun_dr.erase(peer_id)
	_stamina_drain_originals.erase(peer_id)
	_rage_stun_hits.erase(peer_id)
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
		player_node.invincible_until = Time.get_ticks_msec() + int(immunity_duration * 1000)
		player_node.rpc("_sync_invincibility", int(immunity_duration * 1000))
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


# ── Stamina Reduction ──────────────────────────────────────────────────

func _recalculate_stamina_drain(peer_id: int, player_node: Node) -> void:
	if not _effects.has(peer_id) or _effects[peer_id]["stamina_reduction"].is_empty():
		if _stamina_drain_originals.has(peer_id):
			if is_instance_valid(player_node):
				player_node.character_data.stamina_sprint_drain = _stamina_drain_originals[peer_id]
			_stamina_drain_originals.erase(peer_id)
		return

	var original = _stamina_drain_originals.get(peer_id, player_node.character_data.stamina_sprint_drain)
	var min_magnitude := 1.0
	for instance in _effects[peer_id]["stamina_reduction"]:
		min_magnitude = minf(min_magnitude, instance["magnitude"])
	player_node.character_data.stamina_sprint_drain = original * min_magnitude


func _on_stamina_reduction_expired(peer_id: int) -> void:
	var player_node := _get_player(peer_id)
	if is_instance_valid(player_node):
		_recalculate_stamina_drain(peer_id, player_node)


# ── Internos ───────────────────────────────────────────────────────────

func _apply_bleed_tick(peer_id: int, instance: Dictionary) -> void:
	var player_node := _get_player(peer_id)
	if not is_instance_valid(player_node):
		return
	var dmg: int = ceili(instance.get("dps", 5.0) * instance.get("tick_interval", 1.0))
	var combat = GameServiceLocator.combat_mediator
	if is_instance_valid(combat) and combat.has_method("apply_dot_damage"):
		combat.apply_dot_damage(null, player_node, dmg)


## Recalcula el cegado visual efectivo ("más fuerte gana" = menor vision_factor).
## Si no queda ninguna fuente activa, restaura la visión completa.
func _refresh_blind_visual(peer_id: int) -> void:
	var player_node := _get_player(peer_id)
	if not is_instance_valid(player_node):
		return
	if not _effects.has(peer_id) or _effects[peer_id]["blind"].is_empty():
		player_node.rpc("_sync_vision_reduction", 1.0, 0.0)
		return

	var best_factor := 1.0
	var best_timer := 0.0
	for instance in _effects[peer_id]["blind"]:
		var factor: float = instance.get("vision_factor", 0.5)
		if factor < best_factor or (is_equal_approx(factor, best_factor) and instance["timer"] > best_timer):
			best_factor = factor
			best_timer = instance["timer"]

	if best_timer > 0.0:
		player_node.rpc("_sync_vision_reduction", best_factor, best_timer)


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
	# 1. Verificar si el jugador está caído mediante el HealthService
	var health_svc = _health_service
	if health_svc and health_svc.is_downed(peer_id):
		# 80% de reducción significa que se queda con el 20% de su base_speed
		return base_speed * 0.2
		
	# 2. Si NO está caído, se aplica la lógica normal de efectos de estado
	if has_effect(peer_id, "stun"):
		return 0.0
	if has_effect(peer_id, "root"):
		return 0.0
	if has_effect(peer_id, "slow"):
		var total_slow := 0.0
		for instance in _effects[peer_id]["slow"]:
			total_slow += instance["magnitude"]
		total_slow = minf(total_slow, 0.9)
		base_speed = base_speed * (1.0 - total_slow)

	if has_effect(peer_id, "speed_boost"):
		var max_multiplier := 1.0
		for instance in _effects[peer_id]["speed_boost"]:
			max_multiplier = maxf(max_multiplier, instance.get("multiplier", 1.3))
		base_speed = base_speed * max_multiplier
		
	return base_speed

func _sync_effect_to_clients(peer_id: int, effect_name: String, active: bool, duration: float = 0.0) -> void:
	var player_node := _get_player(peer_id)
	if is_instance_valid(player_node):
		player_node.rpc("_sync_effect", effect_name, active)

	var relay = GameServiceLocator.get_client_relay()
	if is_instance_valid(relay):
		if active:
			relay.rpc("_rpc_effect_applied", peer_id, effect_name, duration)
		else:
			relay.rpc("_rpc_effect_removed", peer_id, effect_name)


func _get_player(peer_id: int) -> Node:
	return PlayerRegistry.get_player(peer_id)

func remove_modifier(modifier_id: String, player_node: Node = null) -> void:
	if not multiplayer.is_server():
		return
		
	print("[StatusEffectService] Intento de remover modificador: ", modifier_id)
	
	# Si nos pasan el nodo del jugador, forzamos un recálculo de su velocidad 
	# para asegurarnos de que limpie cualquier rastro visual o mecánico.
	if is_instance_valid(player_node):
		var peer_id := player_node.get_multiplayer_authority()
		_recalculate_speed(peer_id)
	elif modifier_id == "lms_buff":
		# Si no hay nodo pero es el buff de LMS, recalculamos a todos los peers activos
		for peer_id in _effects.keys():
			_recalculate_speed(peer_id)

func remove_effect(player_node: Node, effect_name: String) -> void:
	if not multiplayer.is_server():
		return
	if not effect_name in EFFECT_TYPES:
		push_warning("[StatusEffectService] remove_effect: efecto desconocido: ", effect_name)
		return
 
	var peer_id := player_node.get_multiplayer_authority()
	if not _effects.has(peer_id):
		return
	if _effects[peer_id][effect_name].is_empty():
		return
 
	_effects[peer_id][effect_name].clear()
	_recalculate_speed(peer_id)
	if effect_name == "stamina_reduction" and _stamina_drain_originals.has(peer_id):
		if is_instance_valid(player_node):
			player_node.character_data.stamina_sprint_drain = _stamina_drain_originals[peer_id]
		_stamina_drain_originals.erase(peer_id)
	if effect_name == "blind":
		_refresh_blind_visual(peer_id)
	_sync_effect_to_clients(peer_id, effect_name, false)

	print("[StatusEffectService] ", effect_name, " eliminado manualmente para peer ", peer_id)
 

func _exit_tree() -> void:
	_effects.clear()
	_last_speed.clear()
	_stun_immunity.clear()
	_post_stun_dr.clear()
	_stamina_drain_originals.clear()
	_rage_stun_hits.clear()
	print("[StatusEffectService] Limpiado.")
