extends AbilityBase

# ─────────────────────────────────────────────────────────────────────
# Counter.gd — Modo LMS de Kris.
#
# Flujo:
#   1. Kris activa Counter → root + animación PREPARE en loop.
#   2. CombatMediator._check_intercept() detecta el modo activo y llama
#      try_intercept() antes de aplicar cualquier daño.
#   3a. Killer dentro del radio → daño cancelado + stun + TP + animación acción.
#   3b. Killer fuera del radio → daño cancelado, sin stun, regresa a idle.
#   4. En ambos casos se inicia el cooldown.
#   5. Si la ventana expira sin golpe → vuelve a idle + cooldown normal.
#
# REQUISITO en AbilityData de Counter:
#   prepare_animation  : animación de PREPARE loop (distinta a la de ACT)
#   action_animation   : animación de contraataque (solo si hay stun)
#   range_             : radio del hitbox de respuesta en px
#   stun_duration      : duración del stun al killer
#   tp_reward          : TP que gana Kris al hacer parry exitoso con stun
#   tp_cost            : TP que consume al activar
#   cooldown           : cooldown tras resolución (éxito, bloqueo sin stun o expiración)
#
# INTEGRACIÓN:
#   Implementa try_intercept() — CombatMediator lo llama automáticamente
#   cuando detecta un modo activo en el slot. No requiere cambios externos.
# ─────────────────────────────────────────────────────────────────────


func activate(player_node: Node, data: AbilityData, _direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[Counter] player_node inválido.")
		return

	var caster_id: int = player_node.get_multiplayer_authority()

	# ── Servicios ────────────────────────────────────────────────────────
	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	var combat  = GameServiceLocator.get_service("CombatMediator")
	var cd_svc  = GameServiceLocator.get_service("CooldownService")
	var tp_svc  = GameServiceLocator.get_service("TPService")

	if not abs_svc:
		push_error("[Counter] AbilityStateService no disponible.")
		return
	if not combat:
		push_error("[Counter] CombatMediator no disponible.")
		return
	if not cd_svc:
		push_error("[Counter] CooldownService no disponible.")
		return

	# ── Guardia: ventana ya activa ───────────────────────────────────────
	if abs_svc.is_mode_active(caster_id, slot_index):
		print("[Counter] Ventana ya activa, ignorado | peer: ", caster_id)
		return

	# ── Consumir TP ──────────────────────────────────────────────────────
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(caster_id, data.tp_cost):
			push_warning("[Counter] consume_tp falló inesperadamente para peer ", caster_id)
			return

	# ── Activar modo ─────────────────────────────────────────────────────
	# Guardamos el radio en mode_data para que try_intercept() lo lea
	# sin necesitar acceso al AbilityData original.
	abs_svc.activate_mode(caster_id, slot_index, {
		"range": data.range_,
	})

	# ── Root durante la ventana ───────────────────────────────────────────
	combat.apply_root(player_node, data.cooldown + 1.0) # safety cap

	# ── Animación PREPARE en loop ────────────────────────────────────────
	if data.prepare_animation != "":
		player_node.play_prepare_animation(data.prepare_animation, slot_index, player_node.facing_right)

	print("[Counter] Ventana activa | peer: ", caster_id,
		  " | radio: ", data.range_)

	# ── Timer de expiración ──────────────────────────────────────────────
	var counter_window: float = _get_anim_duration(player_node, data.prepare_animation)
	player_node.get_tree().create_timer(counter_window).timeout.connect(
		func() -> void:
			if not is_instance_valid(player_node):
				return
			# Si el modo sigue activo, la ventana expiró sin recibir golpe
			if abs_svc.is_mode_active(caster_id, slot_index):
				abs_svc.deactivate_mode(caster_id, slot_index)
				combat.remove_root(player_node)
				player_node.rpc("_sync_cancel_ability")
				cd_svc.start(caster_id, data.display_name, data.cooldown, slot_index)
				print("[Counter] Ventana expiró sin golpe | peer: ", caster_id)
	)


# ═══════════════════════════════════════════════════════════════════════
# INTERCEPTOR — llamado por CombatMediator._check_intercept()
# ═══════════════════════════════════════════════════════════════════════

## Contrato del sistema de interceptores de CombatMediator.
## Se llama automáticamente antes de aplicar daño cuando el modo está activo.
## target    : Kris (el que recibe el golpe)
## attacker  : el killer que ataca
## data      : AbilityData del slot de Counter
## slot_index: slot donde vive Counter
## Devuelve true → daño cancelado. Devuelve false → daño continúa.
func try_intercept(target: Node, attacker: Node, data: AbilityData, slot_index: int) -> bool:
	if not is_instance_valid(target):
		return false

	var caster_id: int = target.get_multiplayer_authority()

	var abs_svc = GameServiceLocator.get_service("AbilityStateService")
	if not abs_svc or not abs_svc.is_mode_active(caster_id, slot_index):
		return false

	# ── Desactivar ventana ───────────────────────────────────────────────
	abs_svc.deactivate_mode(caster_id, slot_index)

	var combat = GameServiceLocator.get_service("CombatMediator")
	var cd_svc = GameServiceLocator.get_service("CooldownService")
	var tp_svc = GameServiceLocator.get_service("TPService")

	# ── Quitar root ───────────────────────────────────────────────────────
	if combat:
		combat.remove_root(target)

	# ── Verificar si el killer está dentro del radio de respuesta ────────
	var mode_data: Dictionary = abs_svc.get_mode_data(caster_id, slot_index)
	var counter_range: float  = mode_data.get("range", data.range_ if data else 120.0)
	var killer_in_range: bool = false

	if is_instance_valid(attacker):
		var dist: float = target.global_position.distance_to(attacker.global_position)
		killer_in_range = dist <= counter_range
		print("[Counter] Distancia al killer: %.1f | radio: %.1f | en rango: %s" \
			  % [dist, counter_range, killer_in_range])

	if killer_in_range:
		# ── Parry exitoso con stun ───────────────────────────────────────
		if data and data.stun_duration > 0.0 and combat:
			combat.apply_stun(attacker, data.stun_duration)
			print("[Counter] Stun aplicado al killer por ", data.stun_duration, "s")

		if data and data.tp_reward > 0.0 and tp_svc:
			tp_svc.add_tp_custom(caster_id, data.tp_reward)
			print("[Counter] TP otorgado: ", data.tp_reward, " a peer: ", caster_id)

		# Animación de contraataque solo si hubo stun
		if data and data.action_animation != "":
			target.play_ability_animation(
				data.action_animation, slot_index, target.facing_right
			)
			var anim_dur: float = _get_anim_duration_static(target, data.action_animation)
			target.get_tree().create_timer(anim_dur).timeout.connect(
				func() -> void:
					if is_instance_valid(target):
						target.rpc("_sync_cancel_ability")
			)
		else:
			target.rpc("_sync_cancel_ability")

		print("[Counter] PARRY EXITOSO | peer: ", caster_id)
	else:
		# ── Bloqueo sin stun (golpe a distancia) ─────────────────────────
		target.rpc("_sync_cancel_ability")
		print("[Counter] Bloqueo sin stun (killer fuera de rango) | peer: ", caster_id)

	# ── Cooldown en ambos casos ──────────────────────────────────────────
	if cd_svc and data:
		cd_svc.start(caster_id, data.display_name, data.cooldown, slot_index)

	return true


# ═══════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════

const _ANIM_FALLBACK: float = 2.0

## Duración de animación desde instancia (usado en activate).
func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return _ANIM_FALLBACK
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return _ANIM_FALLBACK
	if not sprite.sprite_frames.has_animation(anim_name):
		return _ANIM_FALLBACK
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return _ANIM_FALLBACK
	return frame_count / fps


## Versión estática para usar dentro de try_intercept.
## Duplicada intencionalmente — en GDScript los métodos estáticos no pueden
## llamar a métodos de instancia de la misma clase sin una referencia explícita.
static func _get_anim_duration_static(player_node: Node, anim_name: String) -> float:
	const FALLBACK: float = 2.0
	if anim_name == "":
		return FALLBACK
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return FALLBACK
	if not sprite.sprite_frames.has_animation(anim_name):
		return FALLBACK
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return FALLBACK
	return frame_count / fps
