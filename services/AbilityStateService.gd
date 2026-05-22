# res://services/AbilityStateService.gd
# ============================================================
# AbilityStateService
#
# Guarda el estado MUTABLE de habilidades por jugador por partida.
# Un Resource (.tres) es compartido en disco — no puede guardar
# "cuántas veces usó Susie Ultimate Health esta partida".
# Este servicio es ese estado en memoria, por peer_id + slot_index.
#
# Responsabilidades:
#   - Contador de usos por slot  (Ultimate Health de Susie)
#   - Cooldown dinámico acumulado por slot  (Ultimate Health)
#   - Contador de golpes pendientes por slot  (Pacify de Ralsei)
#   - Flags de modo activo por slot  (Counter de Kris, Rage Mode de Jevil,
#                                     Soul Protect de Kris, Vuelo de Spamton)
#   - Resistencia a stuns dinámica por slot  (Rage Mode de Jevil)
#
# Lo que NO hace este servicio:
#   - Sincronización visual con el cliente  (eso es CooldownService / EvolutionService)
#   - Aplicar daño, curación o efectos  (eso es el script de cada habilidad)
#   - Decidir si una habilidad se ejecuta  (eso es AbilityRouter)
#
# Acceso:
#   var state_svc = GameServiceLocator.get_service("AbilityStateService")
# ============================================================
extends Node


# ── ESTRUCTURA INTERNA ───────────────────────────────────────────────────
#
# _states[peer_id][slot_index] = {
#
#   — Escalabilidad (Ultimate Health de Susie) ——————————————————————————
#   "use_count"            : int    — número de usos en esta partida
#   "dynamic_cooldown"     : float  — cooldown actual (base + acumulado por uso)
#   "dynamic_tp_cost"      : float  — costo TP actual (base - reducción por uso)
#
#   — Contador de golpes (Pacify de Ralsei) ————————————————————————————
#   "hit_counter"          : int    — golpes acumulados esperando el umbral
#
#   — Modos activos (Counter de Kris, Soul Protect, Rage Mode, Vuelo) ——
#   "mode_active"          : bool   — true mientras el modo está activo
#   "mode_data"            : Dictionary — datos extra del modo activo:
#       Counter de Kris:   {}  (sin datos extra, solo el flag)
#       Soul Protect:      { "protected_peer_id": int }
#       Rage Mode Jevil:   { "stun_resistance": float }  — resistencia actual
#       Vuelo Spamton:     {}  (sin datos extra por ahora)
# }
#
# ────────────────────────────────────────────────────────────────────────

# { peer_id: { slot_index: { ...campos... } } }
var _states: Dictionary = {}

# Número de slots por jugador (debe coincidir con ability_slots en CharacterData)
const SLOT_COUNT: int = 5


# ════════════════════════════════════════════════════════════════════════════
# REGISTRO
# ════════════════════════════════════════════════════════════════════════════

## Llamado desde Player._ready() igual que los demás servicios.
## Inicializa el estado limpio para todos los slots del jugador.
func register_player(peer_id: int, char_data: Resource = null) -> void:
	if not multiplayer.is_server():
		return

	_states[peer_id] = {}

	for slot in SLOT_COUNT:
		var ability_data: Resource = null
		if char_data and char_data.get("ability_slots") and slot < char_data.ability_slots.size():
			ability_data = char_data.ability_slots[slot]

		_states[peer_id][slot] = _build_initial_state(ability_data)

	print("[AbilityStateService] Jugador ", peer_id, " registrado con ", SLOT_COUNT, " slots.")


## Limpia al salir o desconectarse.
func unregister_player(peer_id: int) -> void:
	if _states.has(peer_id):
		_states.erase(peer_id)
		print("[AbilityStateService] Datos eliminados para peer: ", peer_id)


## Construye el estado inicial de un slot leyendo los valores base del AbilityData.
## Si ability_data es null (slot vacío), devuelve defaults seguros.
func _build_initial_state(ability_data: Resource) -> Dictionary:
	var base_cd: float   = ability_data.cooldown      if ability_data and "cooldown"  in ability_data else 0.0
	var base_tp: float   = ability_data.tp_cost       if ability_data and "tp_cost"   in ability_data else 0.0

	return {
		# Escalabilidad
		"use_count"        : 0,
		"dynamic_cooldown" : base_cd,
		"dynamic_tp_cost"  : base_tp,

		# Contador de golpes
		"hit_counter"      : 0,

		# Modo activo
		"mode_active"      : false,
		"mode_data"        : {},
	}


# ════════════════════════════════════════════════════════════════════════════
# API — ESCALABILIDAD POR USO
# Usado por: Ultimate Health de Susie
# ════════════════════════════════════════════════════════════════════════════

## Registra un uso de la habilidad y actualiza cooldown y costo de TP.
## Llama esto DESPUÉS de que la habilidad se ejecutó con éxito.
## Devuelve el nuevo use_count.
func register_use(peer_id: int, slot_index: int, ability_data: Resource) -> int:
	if not _ensure_state(peer_id, slot_index):
		return 0

	var s: Dictionary = _states[peer_id][slot_index]
	s["use_count"] += 1
	var uses: int = s["use_count"]

	# Actualizar cooldown dinámico si la habilidad escala
	if ability_data and ability_data.get("is_scalable") and ability_data.is_scalable:
		var cd_increase: float = ability_data.cooldown_increase_per_use
		s["dynamic_cooldown"] = ability_data.cooldown + (cd_increase * uses)

		# Actualizar costo de TP dinámico
		var tp_reduction: float = ability_data.tp_cost_reduction_per_use * uses
		var new_tp: float = ability_data.tp_cost - tp_reduction
		s["dynamic_tp_cost"] = maxf(new_tp, ability_data.tp_cost_floor)

	print("[AbilityStateService] Uso registrado | peer: ", peer_id,
		  " | slot: ", slot_index, " | usos totales: ", uses,
		  " | cd actual: ", s["dynamic_cooldown"],
		  " | tp actual: ", s["dynamic_tp_cost"])

	return uses


## Devuelve el número de usos acumulados en esta partida.
func get_use_count(peer_id: int, slot_index: int) -> int:
	if not _ensure_state(peer_id, slot_index):
		return 0
	return _states[peer_id][slot_index]["use_count"]


## Devuelve el cooldown actual (ya aplicadas las subidas por uso).
## AbilityRouter debe llamar esto en lugar de leer ability_data.cooldown
## cuando la habilidad tiene is_scalable = true.
func get_dynamic_cooldown(peer_id: int, slot_index: int) -> float:
	if not _ensure_state(peer_id, slot_index):
		return 0.0
	return _states[peer_id][slot_index]["dynamic_cooldown"]


## Devuelve el costo de TP actual (ya aplicadas las reducciones por uso).
## AbilityRouter debe llamar esto para habilidades escalables en lugar
## de leer ability_data.tp_cost directamente.
func get_dynamic_tp_cost(peer_id: int, slot_index: int) -> float:
	if not _ensure_state(peer_id, slot_index):
		return 0.0
	return _states[peer_id][slot_index]["dynamic_tp_cost"]


## Calcula el valor del efecto principal escalado al número de usos actuales.
## Ejemplo: Ultimate Health con base 0.01, per_use 0.02, cap 0.55 y 3 usos → 0.07.
func get_scaled_value(peer_id: int, slot_index: int, ability_data: Resource) -> float:
	if not ability_data or not ability_data.get("is_scalable") or not ability_data.is_scalable:
		return ability_data.scaling_base_value if ability_data and "scaling_base_value" in ability_data else 0.0

	var uses: int    = get_use_count(peer_id, slot_index)
	var base: float  = ability_data.scaling_base_value
	var step: float  = ability_data.scaling_per_use
	var cap: float   = ability_data.scaling_cap

	return minf(base + step * uses, cap)


# ════════════════════════════════════════════════════════════════════════════
# API — CONTADOR DE GOLPES
# Usado por: Pacify de Ralsei (necesita 4 impactos para aplicar stun)
# ════════════════════════════════════════════════════════════════════════════

## Suma un golpe al contador del slot y devuelve el total acumulado.
func add_hit(peer_id: int, slot_index: int) -> int:
	if not _ensure_state(peer_id, slot_index):
		return 0
	_states[peer_id][slot_index]["hit_counter"] += 1
	var total: int = _states[peer_id][slot_index]["hit_counter"]
	print("[AbilityStateService] Hit registrado | peer: ", peer_id,
		  " | slot: ", slot_index, " | total: ", total)
	return total


## Devuelve los golpes acumulados sin modificar el contador.
func get_hit_count(peer_id: int, slot_index: int) -> int:
	if not _ensure_state(peer_id, slot_index):
		return 0
	return _states[peer_id][slot_index]["hit_counter"]


## Resetea el contador de golpes a 0.
## Llama esto cuando el umbral se cumplió (el stun se aplicó)
## o cuando la habilidad expiró sin completar los impactos.
func reset_hit_counter(peer_id: int, slot_index: int) -> void:
	if not _ensure_state(peer_id, slot_index):
		return
	_states[peer_id][slot_index]["hit_counter"] = 0
	print("[AbilityStateService] Hit counter reseteado | peer: ", peer_id,
		  " | slot: ", slot_index)


# ════════════════════════════════════════════════════════════════════════════
# API — MODOS ACTIVOS
# Usado por: Counter de Kris, Soul Protect de Kris,
#            Rage Mode de Jevil, Vuelo de Spamton
# ════════════════════════════════════════════════════════════════════════════

## Activa el modo para un slot con datos opcionales.
## data puede contener cualquier campo que la habilidad necesite rastrear.
##
## Ejemplos de uso:
##   Soul Protect:   activate_mode(peer_id, 2, { "protected_peer_id": target_id })
##   Counter:        activate_mode(peer_id, 1, {})
##   Rage Mode:      activate_mode(peer_id, 3, { "stun_resistance": 0.5 })
func activate_mode(peer_id: int, slot_index: int, data: Dictionary = {}) -> void:
	if not _ensure_state(peer_id, slot_index):
		return
	_states[peer_id][slot_index]["mode_active"] = true
	_states[peer_id][slot_index]["mode_data"]   = data.duplicate()
	print("[AbilityStateService] Modo ACTIVADO | peer: ", peer_id,
		  " | slot: ", slot_index, " | data: ", data)


## Desactiva el modo y limpia mode_data.
func deactivate_mode(peer_id: int, slot_index: int) -> void:
	if not _ensure_state(peer_id, slot_index):
		return
	_states[peer_id][slot_index]["mode_active"] = false
	_states[peer_id][slot_index]["mode_data"]   = {}
	print("[AbilityStateService] Modo DESACTIVADO | peer: ", peer_id,
		  " | slot: ", slot_index)


## Devuelve true si el modo está activo en ese slot.
func is_mode_active(peer_id: int, slot_index: int) -> bool:
	if not _ensure_state(peer_id, slot_index):
		return false
	return _states[peer_id][slot_index]["mode_active"]


## Devuelve el diccionario de datos del modo activo.
## Si el modo no está activo, devuelve un diccionario vacío.
func get_mode_data(peer_id: int, slot_index: int) -> Dictionary:
	if not _ensure_state(peer_id, slot_index):
		return {}
	return _states[peer_id][slot_index]["mode_data"]


## Actualiza un campo específico dentro de mode_data sin reemplazar todo el dict.
## Ejemplo: bajar la resistencia de Jevil tras recibir un stun.
##   update_mode_data(peer_id, slot, "stun_resistance", nueva_resistencia)
func update_mode_data(peer_id: int, slot_index: int, key: String, value: Variant) -> void:
	if not _ensure_state(peer_id, slot_index):
		return
	if not _states[peer_id][slot_index]["mode_active"]:
		push_warning("[AbilityStateService] update_mode_data llamado con modo inactivo | peer: ",
					 peer_id, " | slot: ", slot_index)
		return
	_states[peer_id][slot_index]["mode_data"][key] = value


# ════════════════════════════════════════════════════════════════════════════
# API — RESET
# ════════════════════════════════════════════════════════════════════════════

## Resetea el estado de un slot a sus valores iniciales.
## Útil si quieres reiniciar una habilidad individual sin tocar las demás.
func reset_slot(peer_id: int, slot_index: int, ability_data: Resource = null) -> void:
	if not _states.has(peer_id):
		return
	_states[peer_id][slot_index] = _build_initial_state(ability_data)
	print("[AbilityStateService] Slot ", slot_index, " reseteado para peer: ", peer_id)


## Resetea todos los slots de un jugador. Llámalo al terminar la partida.
func reset_player(peer_id: int) -> void:
	if not _states.has(peer_id):
		return
	for slot in _states[peer_id].keys():
		_states[peer_id][slot] = _build_initial_state(null)
	print("[AbilityStateService] Todos los slots reseteados para peer: ", peer_id)


# ════════════════════════════════════════════════════════════════════════════
# INTERNOS
# ════════════════════════════════════════════════════════════════════════════

## Verifica que el estado exista para peer+slot. Si no, lo inicializa en cero.
## Devuelve false si el peer no está registrado (indica un bug de registro).
func _ensure_state(peer_id: int, slot_index: int) -> bool:
	if not _states.has(peer_id):
		push_warning("[AbilityStateService] Peer ", peer_id,
					 " no registrado. ¿Se llamó register_player()?")
		return false
	if not _states[peer_id].has(slot_index):
		_states[peer_id][slot_index] = _build_initial_state(null)
	return true


func _exit_tree() -> void:
	_states.clear()
	print("[AbilityStateService] Limpiado.")
