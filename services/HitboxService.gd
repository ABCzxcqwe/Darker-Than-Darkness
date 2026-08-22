# HitboxService.gd
# Servicio centralizado para crear y gestionar hitboxes.
# Solo el servidor instancia hitboxes.
# Se accede via: GameServiceLocator.get_service("HitboxService")
#
# Parámetros de config:
#   Obligatorios:
#     attacker_id  : int          — peer_id del atacante
#     attacker_node: Node         — nodo del jugador atacante
#
#   Opcionales:
#     type         : String       — "slash"(default) | "area" | "attached" | "projectile" | "zone"
#     aim_mode     : String       — "mouse"(default) | "facing" | "fixed" | "origin"
#     shape_scene  : PackedScene  — escena con CollisionShape2D (si no se pasa, hitbox sin forma visible)
#     damage       : int          — daño (default: 10)
#     attack_type  : String       — "normal", "slash", "true_damage", etc.
#     hit_limit    : int          — máx targets (0=ilimitado, default: 1)
#     team_filter  : String       — "enemy"(default) | "ally" | "all"
#     lifetime     : float        — segundos hasta expirar (default: 0.25)
#     offset       : float        — distancia desde origin al centro del hitbox (default: 40.0)
#     speed        : float        — velocidad px/s para proyectiles (default: 0.0)
#     direction    : Vector2      — dirección fija (solo si aim_mode = "fixed")
#     mouse_pos    : Vector2      — posición del mouse en coords globales (para aim_mode = "mouse")
#     on_hit       : Callable     — func(target_node) al golpear
#     on_end       : Callable     — func(hit_count)   al expirar
extends Node

const HITBOX_SCRIPT := preload("uid://ct6ctabp7nijt")

var _game_state_service: Node = null


func create(config: Dictionary) -> Node:
	if not multiplayer.is_server():
		push_warning("[HitboxService] Solo el servidor puede crear hitboxes.")
		return null

	var state = _game_state_service
	if not state or not state.is_in_game():
		push_warning("[HitboxService] No hay partida activa.")
		return null

	# ── Leer config ───────────────────────────────────────────────────
	var attacker_id:   int         = config.get("attacker_id",   -1)
	var attacker_node: Node        = config.get("attacker_node", null)
	var type:          String      = config.get("type",          "slash")
	var aim_mode:      String      = config.get("aim_mode",      "mouse")
	var shape_scene:   PackedScene = config.get("shape_scene",   null)
	var damage:        int         = config.get("damage",        10)
	var attack_type:   String      = config.get("attack_type",   "normal")
	var hit_limit:     int         = config.get("hit_limit",     1)
	var team_filter:   String      = config.get("team_filter",   "enemy")
	var lifetime:      float       = config.get("lifetime",      0.25)
	var offset:        float       = config.get("offset",        40.0)
	var speed:         float       = config.get("speed",         0.0)
	var on_hit:        Callable    = config.get("on_hit",        Callable())
	var on_end:        Callable    = config.get("on_end",        Callable())

	if attacker_id == -1 or not is_instance_valid(attacker_node):
		push_error("[HitboxService] 'attacker_id' y 'attacker_node' son obligatorios.")
		return null

	# ── Resolver dirección según aim_mode ────────────────────────────
	var direction: Vector2 = _resolve_direction(aim_mode, config, attacker_node)

	# ── Proyectiles: usar ProjectileSpawner para replicar a clientes ──
	if type == "projectile":
		var spawned = _spawn_projectile(config, attacker_node, direction, lifetime, speed)
		if spawned:
			return spawned
		push_warning("[HitboxService] Falló spawn por ProjectileSpawner, usando modo local.")

	# ── Crear hitbox ──────────────────────────────────────────────────
	var hitbox: Node
	if shape_scene:
		hitbox = shape_scene.instantiate()
		if not config.get("custom_hitbox", false):
			hitbox.set_script(HITBOX_SCRIPT)
	else:
		hitbox = Area2D.new()
		hitbox.set_script(HITBOX_SCRIPT)

	# ── Asignar propiedades (duck-typing para soportar Node2D contenedor) ──
	if "attacker_id" in hitbox: hitbox.attacker_id = attacker_id
	if "damage" in hitbox: hitbox.damage = damage
	if "attack_type" in hitbox: hitbox.attack_type = attack_type
	if "hit_limit" in hitbox: hitbox.hit_limit = hit_limit
	if "team_filter" in hitbox: hitbox.team_filter = team_filter
	if "lifetime" in hitbox: hitbox.lifetime = lifetime
	if "speed" in hitbox: hitbox.speed = speed
	if "aim_mode" in hitbox: hitbox.aim_mode = aim_mode

	# Attached: guardar referencia al nodo atacante para seguirlo
	if type == "attached" and "attacker_node" in hitbox:
		hitbox.attacker_node = attacker_node

	# Proyectil: velocidad en dirección
	if type == "projectile":
		if "speed" in hitbox:
			hitbox.speed = speed if speed > 0.0 else 300.0
		if "detect_walls" in hitbox:
			hitbox.detect_walls = config.get("detect_walls", false)
		if "impact_lifetime" in hitbox:
			hitbox.impact_lifetime = config.get("impact_lifetime", 0.0)
		if "hitbox_max_range" in hitbox:
			hitbox.hitbox_max_range = config.get("hitbox_max_range", 0.0)

	# Área y zona: hit_limit ilimitado por defecto
	if (type == "area" or type == "zone") and "hit_limit" in hitbox:
		hitbox.hit_limit = config.get("hit_limit", 0)

	if on_hit.is_valid() and "on_hit_callback" in hitbox:
		hitbox.on_hit_callback = on_hit
	if on_end.is_valid() and "on_end_callback" in hitbox:
		hitbox.on_end_callback = on_end

	# ── Posicionar ────────────────────────────────────────────────────
	var origin: Vector2 = attacker_node.global_position
	if config.has("position"):
		hitbox.global_position = config["position"]
	elif aim_mode == "origin" or type == "area":
		hitbox.global_position = origin
	else:
		hitbox.global_position = origin + direction * offset

	if hitbox.has_method("set_direction"):
		hitbox.set_direction(direction)
	if hitbox.has_method("set_multiplayer_authority"):
		hitbox.set_multiplayer_authority(1)
	_setup_hitbox_layers(hitbox, team_filter, attacker_node)
	print("[HitboxService] Hitbox posición final: ", hitbox.global_position, " | direction: ", direction, " | offset: ", offset)
	add_child(hitbox)
	var dbg_mask = hitbox.get("collision_mask") if "collision_mask" in hitbox else _find_hurtbox_area(hitbox).collision_mask if _find_hurtbox_area(hitbox) else -1
	print("[HitboxService] Hitbox añadido al árbol. Colisión mask: ", dbg_mask)

	print("[HitboxService] Hitbox creado | tipo:", type,
		  " | aim:", aim_mode, " | atacante:", attacker_id,
		  " | daño:", damage)
	return hitbox


# ── Spawn de proyectil via auto-spawn en Projectiles ─────────────
func _spawn_projectile(config: Dictionary, attacker_node: Node, direction: Vector2, lifetime: float, speed: float) -> Node:
	var world = get_tree().root.find_child("World", true, false)
	if not world:
		return null
	var container = world.get_node_or_null("Projectiles")
	if not container:
		return null

	var shape_scene: PackedScene = config.get("shape_scene")
	if not shape_scene:
		return null

	var hitbox: Node = shape_scene.instantiate()
	if not config.get("custom_hitbox", false):
		hitbox.set_script(HITBOX_SCRIPT)

	# Asignación duck-typing para soportar Node2D contenedor (TopoSpear) y Area2D/CharacterBody2D
	if "attacker_id" in hitbox: hitbox.attacker_id = config.get("attacker_id", -1)
	# attacker_node solo en hitboxes custom
	if config.get("custom_hitbox", false) and "attacker_node" in hitbox:
		hitbox.attacker_node = config.get("attacker_node", null)
	if "damage" in hitbox: hitbox.damage = config.get("damage", 0)
	if "attack_type" in hitbox: hitbox.attack_type = config.get("attack_type", "normal")
	if "hit_limit" in hitbox: hitbox.hit_limit = config.get("hit_limit", 1)
	if "team_filter" in hitbox: hitbox.team_filter = config.get("team_filter", "enemy")
	if "lifetime" in hitbox: hitbox.lifetime = config.get("lifetime", 2.0)
	if "speed" in hitbox: hitbox.speed = config.get("speed", 300.0)
	if "aim_mode" in hitbox: hitbox.aim_mode = config.get("aim_mode", "fixed")
	if "detect_walls" in hitbox: hitbox.detect_walls = config.get("detect_walls", false)
	if "impact_lifetime" in hitbox: hitbox.impact_lifetime = config.get("impact_lifetime", 0.0)
	if "hitbox_max_range" in hitbox: hitbox.hitbox_max_range = config.get("hitbox_max_range", 0.0)
	var on_hit = config.get("on_hit", Callable())
	if on_hit.is_valid() and "on_hit_callback" in hitbox:
		hitbox.on_hit_callback = on_hit
	var on_end = config.get("on_end", Callable())
	if on_end.is_valid() and "on_end_callback" in hitbox:
		hitbox.on_end_callback = on_end

	var origin: Vector2 = attacker_node.global_position
	var aim_mode: String = config.get("aim_mode", "mouse")
	var offset_val: float = config.get("offset", 40.0)
	if config.has("position"):
		hitbox.global_position = config["position"]
	else:
		hitbox.global_position = origin if aim_mode == "origin" else origin + direction * offset_val
	if hitbox.has_method("set_direction"):
		hitbox.set_direction(direction)
	if hitbox.has_method("set_multiplayer_authority"):
		hitbox.set_multiplayer_authority(1)
	var team_filter_val: String = hitbox.get("team_filter") if "team_filter" in hitbox else config.get("team_filter", "enemy")
	_setup_hitbox_layers(hitbox, team_filter_val, attacker_node)

	var dbg_detect_walls: bool = hitbox.get("detect_walls") if "detect_walls" in hitbox else false
	if dbg_detect_walls:
		# Para Node2D contenedor, aplicar a Hurtbox Area2D hijo
		if hitbox is CollisionObject2D:
			hitbox.collision_mask |= 1
		else:
			var area_walls = _find_hurtbox_area(hitbox)
			if area_walls:
				area_walls.collision_mask |= 1

	container.add_child(hitbox, true)

	# NOTA: El MultiplayerSynchronizer se conserva para que el
	# MultiplayerSpawner (World/ProjectileSpawner) replique el proyectil
	# automáticamente a los clientes.
	# var sync = hitbox.get_node_or_null("MultiplayerSynchronizer")
	# if sync:
	# 	sync.queue_free()

	# La réplica visual ahora la maneja el MultiplayerSpawner vía
	# el SceneReplicationConfig del MultiplayerSynchronizer.
	# var scene_path: String = shape_scene.resource_path
	# if not scene_path.is_empty():
	# 	rpc("_spawn_client_hitbox", scene_path, hitbox.global_position, direction, speed, hitbox.lifetime)

	return hitbox


# ── Resolver dirección ─────────────────────────────────────────────────
func _resolve_direction(aim_mode: String, config: Dictionary, attacker_node: Node) -> Vector2:
	match aim_mode:
		"mouse":
			# La habilidad pasa la posición del mouse desde el cliente
			var mouse_pos: Vector2 = config.get("mouse_pos", Vector2.ZERO)
			if mouse_pos == Vector2.ZERO:
				push_warning("[HitboxService] aim_mode 'mouse' sin mouse_pos — usando facing.")
				return _get_facing(attacker_node)
			return (mouse_pos - attacker_node.global_position).normalized()

		"facing":
			return _get_facing(attacker_node)

		"fixed":
			var dir: Vector2 = config.get("direction", Vector2.RIGHT)
			return dir.normalized()

		"origin":
			# Sin dirección — el hitbox es centrado (área de explosión)
			return Vector2.RIGHT

	return Vector2.RIGHT


func _get_facing(attacker_node: Node) -> Vector2:
	# El slash siempre es horizontal — ignorar arriba/abajo
	# Usa la propiedad 'facing_right' del jugador si existe
	if attacker_node.get("facing_right") != null:
		return Vector2.RIGHT if attacker_node.facing_right else Vector2.LEFT
	# Fallback: inferir desde flip_h del sprite
	var sprite = attacker_node.get_node_or_null("AnimatedSprite2D")
	if sprite and sprite.flip_h:
		return Vector2.LEFT
	return Vector2.RIGHT


# ── Capas de colisión del hitbox ───────────────────────────────────────
# Capas definidas en Project Settings > Layer Names > 2D Physics:
#   1 = world          2 = survivor_body   3 = killer_body
#   4 = survivor_hurtbox   5 = killer_hurtbox   6 = hitbox   7 = projectile
# Soporta tanto Area2D/CharacterBody2D root como Node2D contenedor con hijo Hurtbox Area2D (TopoSpear).
func _setup_hitbox_layers(hitbox: Node, team_filter: String, attacker_node: Node) -> void:
	var target: CollisionObject2D = null
	if hitbox is CollisionObject2D:
		target = hitbox as CollisionObject2D
	else:
		# Node2D contenedor (TopoSpear, futuros visuales) — buscar Area2D hijo
		target = _find_hurtbox_area(hitbox)
		if not target:
			push_warning("[HitboxService] Node2D hitbox sin Area2D hijo para capas | ", hitbox.name)
			return
	var attacker_team: String = ""
	if attacker_node and attacker_node.character_data:
		attacker_team = attacker_node.character_data.team

	# Layer: siempre capa 6 (hitbox)
	target.collision_layer = 32  # bit 6

	match team_filter:
		"enemy":
			if attacker_team == "killer":
				target.collision_mask = 8   # survivor_hurtbox (capa 4)
			else:
				target.collision_mask = 16  # killer_hurtbox (capa 5)
		"ally":
			target.collision_mask = 8       # survivor_hurtbox — aliados siempre survivors
		"all":
			target.collision_mask = 8 | 16  # ambos hurtboxes
		_:
			target.collision_mask = 8 | 16


func _find_hurtbox_area(root: Node) -> Area2D:
	# Búsqueda determinística por nombres comunes, luego primer Area2D
	var names: Array[String] = ["Hurtbox", "HurtboxDetector", "Detector", "Area"]
	for n in names:
		var c = root.get_node_or_null(n)
		if c and c is Area2D:
			return c as Area2D
	for child in root.get_children():
		if child is Area2D:
			return child as Area2D
		var found = child.find_child("Hurtbox", true, false)
		if found and found is Area2D:
			return found as Area2D
	return null


func _exit_tree() -> void:
	print("[HitboxService] Limpiado.")
