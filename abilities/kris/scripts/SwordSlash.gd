extends AbilityBase

const HITBOX_LIFETIME: float = 0.5

# Fallback si el servidor no puede leer el SpriteFrames (headless).
# Debe coincidir con la duración real de la animación sword_slash.
# Calcula: frame_count / fps. Ejemplo: 6 frames a 12 fps = 0.5s
const ANIM_DURATION: float = 0.5


func activate(player_node: Node, data: AbilityData, direction: Vector2, slot_index: int = -1) -> void:
	if not is_instance_valid(player_node):
		push_warning("[SwordSlash] player_node inválido.")
		return

	var combat = GameServiceLocator.get_service("CombatMediator")
	if not combat:
		push_error("[SwordSlash] CombatMediator no disponible.")
		return

	var hs = GameServiceLocator.get_service("HitboxService")
	if not hs:
		push_error("[SwordSlash] HitboxService no disponible.")
		return

	var cd = GameServiceLocator.get_service("CooldownService")
	if not cd:
		push_error("[SwordSlash] CooldownService no disponible.")
		return

	var tp_svc = GameServiceLocator.get_service("TPService")

	var attacker_id: int = player_node.get_multiplayer_authority()
	var dmg: int         = int(data.base_damage * data.evo_damage_multiplier)
	var atk_type: String = data.attack_type
	var hit_range: float = data.range_
	var stun_dur: float  = data.stun_duration + data.evo_status_duration_bonus
	var tp_reward: float = data.tp_reward
	var facing_right     = direction.x >= 0.0
	var slash_dir: Vector2 = Vector2.RIGHT if facing_right else Vector2.LEFT

	# ── Consumir TP antes de ejecutar ────────────────────────────────────
	# El Router ya verificó que hay suficiente — aquí solo consumimos.
	if data.tp_cost > 0.0 and tp_svc:
		if not tp_svc.consume_tp(attacker_id, data.tp_cost):
			push_warning("[SwordSlash] consume_tp falló inesperadamente para peer ", attacker_id)
			return

	# ── Root durante la animación ────────────────────────────────────────
	combat.apply_root(player_node, ANIM_DURATION)

	# ── Animación ────────────────────────────────────────────────────────
	if data.action_animation != "":
		player_node.play_ability_animation(data.action_animation, slot_index, facing_right)

	# ── Timer de fin de animación ─────────────────────────────────────────
	# Resetea el FSM del jugador a IDLE cuando termina la animación.
	# Es independiente del hitbox para que golpear no corte la animación.
	var anim_dur := _get_anim_duration(player_node, data.action_animation)
	player_node.get_tree().create_timer(anim_dur).timeout.connect(
		func() -> void:
			if is_instance_valid(player_node):
				player_node.rpc("_sync_cancel_ability")
	)

	# ── Hitbox ────────────────────────────────────────────────────────────
	# El cooldown se inicia dentro de on_hit / on_end según si golpea o no.
	# Capturamos slot_index y data en el closure para poder llamar cd.start().
	var _hit_registered: bool = false  # guarda para que on_end sepa si ya inició cd

	hs.create({
		"attacker_id"   : attacker_id,
		"attacker_node" : player_node,
		"type"          : "slash",
		"aim_mode"      : "fixed",
		"direction"     : slash_dir,
		"shape_scene"   : data.ability_scene,
		"damage"        : 0,
		"attack_type"   : atk_type,
		"team_filter"   : "enemy",
		"hit_limit"     : 1,
		"lifetime"      : HITBOX_LIFETIME,
		"offset"        : hit_range,

		"on_hit": func(target_node: Node) -> void:
			if not is_instance_valid(target_node):
				return

			_hit_registered = true

			if dmg > 0:
				combat.apply_damage(player_node, target_node, dmg, atk_type)

			if target_node.is_in_group("killer"):
				if stun_dur > 0.0:
					combat.apply_stun(target_node, stun_dur)
				if tp_reward > 0.0 and tp_svc:
					tp_svc.add_tp_custom(attacker_id, tp_reward)

			# ── Cooldown al golpear ──────────────────────────────────────
			# Se inicia aquí, en el momento del impacto, para cerrar
			# la ventana de spam lo antes posible.
			cd.start(attacker_id, data.display_name, data.cooldown, slot_index),

		"on_end": func(hit_count: int) -> void:
			if is_instance_valid(player_node):
				combat.remove_root(player_node)

			# ── Cooldown al fallar ───────────────────────────────────────
			# Solo si on_hit no lo inició ya (hit_count == 0 significa que
			# el hitbox expiró sin golpear a nadie).
			if hit_count == 0:
				var fail_cd: float = data.cooldown_fail if data.cooldown_fail > 0.0 else data.cooldown
				cd.start(attacker_id, data.display_name, fail_cd, slot_index)

			print("[SwordSlash] Terminó | golpes: ", hit_count)
	})

	print("[SwordSlash] Activado | peer: ", attacker_id,
		  " | dir: ", slash_dir, " | dmg: ", dmg,
		  " | stun: ", stun_dur, "s | anim: ", data.action_animation)


## Lee la duración real de la animación desde el SpriteFrames.
## Si no puede leerla (servidor headless sin frames visuales), usa ANIM_DURATION como fallback.
func _get_anim_duration(player_node: Node, anim_name: String) -> float:
	if anim_name == "":
		return ANIM_DURATION
	var sprite: AnimatedSprite2D = player_node.get_node_or_null("AnimatedSprite2D")
	if not sprite or not sprite.sprite_frames:
		return ANIM_DURATION
	if not sprite.sprite_frames.has_animation(anim_name):
		return ANIM_DURATION
	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		return ANIM_DURATION
	return frame_count / fps
