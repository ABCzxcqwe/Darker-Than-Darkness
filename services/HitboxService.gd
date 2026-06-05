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

func create(config: Dictionary) -> Node:
	if not multiplayer.is_server():
		push_warning("[HitboxService] Solo el servidor puede crear hitboxes.")
		return null

	var state = GameServiceLocator.get_service("GameStateService")
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
	var hitbox: Area2D
	if shape_scene:
		hitbox = shape_scene.instantiate()
		hitbox.set_script(HITBOX_SCRIPT)
	else:
		hitbox = Area2D.new()
		hitbox.set_script(HITBOX_SCRIPT)

	# ── Asignar propiedades ───────────────────────────────────────────
	hitbox.attacker_id   = attacker_id
	hitbox.damage        = damage
	hitbox.attack_type   = attack_type
	hitbox.hit_limit     = hit_limit
	hitbox.team_filter   = team_filter
	hitbox.lifetime      = lifetime
	hitbox.speed         = speed
	hitbox.aim_mode      = aim_mode

	# Attached: guardar referencia al nodo atacante para seguirlo
	if type == "attached":
		hitbox.attacker_node = attacker_node

	# Proyectil: velocidad en dirección
	if type == "projectile":
		hitbox.speed = speed if speed > 0.0 else 300.0
		hitbox.detect_walls = config.get("detect_walls", false)
		hitbox.impact_lifetime = config.get("impact_lifetime", 0.0)
		hitbox.hitbox_max_range = config.get("hitbox_max_range", 0.0)

	# Área y zona: hit_limit ilimitado por defecto
	if type == "area" or type == "zone":
		hitbox.hit_limit = config.get("hit_limit", 0)

	if on_hit.is_valid():
		hitbox.on_hit_callback = on_hit
	if on_end.is_valid():
		hitbox.on_end_callback = on_end

	# ── Posicionar ────────────────────────────────────────────────────
	var origin: Vector2 = attacker_node.global_position
	if aim_mode == "origin" or type == "area":
		hitbox.global_position = origin
	else:
		hitbox.global_position = origin + direction * offset

	hitbox.set_direction(direction)
	hitbox.set_multiplayer_authority(1)
	_setup_hitbox_layers(hitbox, team_filter, attacker_node)
	print("[HitboxService] Hitbox posición final: ", hitbox.global_position, " | direction: ", direction, " | offset: ", offset)
	add_child(hitbox)
	print("[HitboxService] Hitbox añadido al árbol. Colisión mask: ", hitbox.collision_mask)

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

	var hitbox = shape_scene.instantiate()
	hitbox.set_script(HITBOX_SCRIPT)

	hitbox.attacker_id   = config.get("attacker_id",   -1)
	hitbox.damage        = config.get("damage",        0)
	hitbox.attack_type   = config.get("attack_type",   "normal")
	hitbox.hit_limit     = config.get("hit_limit",     1)
	hitbox.team_filter   = config.get("team_filter",   "enemy")
	hitbox.lifetime      = config.get("lifetime",      2.0)
	hitbox.speed         = config.get("speed",         300.0)
	hitbox.aim_mode      = config.get("aim_mode",      "fixed")
	hitbox.detect_walls  = config.get("detect_walls",  false)
	hitbox.impact_lifetime = config.get("impact_lifetime", 0.0)
	hitbox.hitbox_max_range = config.get("hitbox_max_range", 0.0)

	var on_hit = config.get("on_hit", Callable())
	if on_hit.is_valid():
		hitbox.on_hit_callback = on_hit
	var on_end = config.get("on_end", Callable())
	if on_end.is_valid():
		hitbox.on_end_callback = on_end

	var origin: Vector2 = attacker_node.global_position
	var aim_mode: String = config.get("aim_mode", "mouse")
	var offset_val: float = config.get("offset", 40.0)
	hitbox.global_position = origin if aim_mode == "origin" else origin + direction * offset_val
	hitbox.set_direction(direction)
	hitbox.set_multiplayer_authority(1)
	_setup_hitbox_layers(hitbox, hitbox.team_filter, attacker_node)

	if hitbox.detect_walls:
		hitbox.collision_mask |= 1  # capa 1 = world (paredes)

	container.add_child(hitbox, true)

	# Eliminar el MultiplayerSynchronizer del hitbox del servidor
	# para que no intente replicarse a los clientes (la réplica visual
	# se hace manualmente via RPC).
	var sync = hitbox.get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.queue_free()

	# Replicar visualmente el proyectil a todos los clientes.
	var scene_path: String = shape_scene.resource_path
	if not scene_path.is_empty():
		rpc("_spawn_client_hitbox", scene_path, hitbox.global_position, direction, speed, hitbox.lifetime)

	return hitbox


@rpc("any_peer", "call_remote", "reliable")
func _spawn_client_hitbox(scene_path: String, pos: Vector2, dir: Vector2, _spd: float, lifetime: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	print("[HitboxService] Cliente: creando copia visual en ", pos, " dir: ", dir)
	var world = get_tree().root.find_child("World", true, false)
	if not world:
		push_warning("[HitboxService] Cliente: World no encontrado")
		return
	var container = world.get_node_or_null("Projectiles")
	if not container:
		push_warning("[HitboxService] Cliente: Projectiles no encontrado")
		return
	var scene: PackedScene = load(scene_path)
	if not scene:
		push_warning("[HitboxService] Cliente: no se pudo cargar: ", scene_path)
		return

	# Instanciar la escena SIN sobreescribir el script con Hitbox.gd.
	# En el cliente solo necesitamos la parte visual: sprite + movimiento.
	# set_script() destruye los @onready y desactiva _physics_process en clientes,
	# por eso se usa un Node2D wrapper que mueve al hijo instanciado.
	var visual: Node2D = Node2D.new()
	visual.global_position = pos
	# Escalar según dirección horizontal para que el sprite apunte bien
	visual.scale.x = 1.0 if dir.x >= 0.0 else -1.0
	visual.rotation = dir.angle()

	var sprite_node = scene.instantiate()
	# Eliminar el MultiplayerSynchronizer del clon cliente si existe,
	# ya que no debe replicar nada desde el cliente.
	var sync_child = sprite_node.get_node_or_null("MultiplayerSynchronizer")
	if sync_child:
		sprite_node.remove_child(sync_child)
		sync_child.queue_free()
	# Desactivar colisiones — solo es visual
	if sprite_node is Area2D or sprite_node is CollisionObject2D:
		sprite_node.collision_layer = 0
		sprite_node.collision_mask = 0
		var col = sprite_node.get_node_or_null("CollisionShape2D")
		if col:
			col.disabled = true

	visual.add_child(sprite_node)
	container.add_child(visual)

	# Reproducir animación de viaje si existe
	var anim_sprite: AnimatedSprite2D = sprite_node.get_node_or_null("AnimatedSprite2D")
	if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("travel"):
		anim_sprite.play("travel")

	print("[HitboxService] Cliente: copia creada en ", visual.global_position)

	# Mover el proyectil visual en cada frame durante su lifetime
	var speed_to_use: float = _spd if _spd > 0.0 else 300.0
	var elapsed: float = 0.0
	while elapsed < lifetime and is_instance_valid(visual):
		await get_tree().process_frame
		if not is_instance_valid(visual):
			break
		var d: float = get_process_delta_time()
		visual.global_position += dir * speed_to_use * d
		elapsed += d

	if is_instance_valid(visual):
		visual.queue_free()


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
func _setup_hitbox_layers(hitbox: Area2D, team_filter: String, attacker_node: Node) -> void:
	var attacker_team: String = ""
	if attacker_node and attacker_node.character_data:
		attacker_team = attacker_node.character_data.team

	# Layer: siempre capa 6 (hitbox)
	hitbox.collision_layer = 32  # bit 6

	match team_filter:
		"enemy":
			if attacker_team == "killer":
				hitbox.collision_mask = 8   # survivor_hurtbox (capa 4)
			else:
				hitbox.collision_mask = 16  # killer_hurtbox (capa 5)
		"ally":
			hitbox.collision_mask = 8       # survivor_hurtbox — aliados siempre survivors
		"all":
			hitbox.collision_mask = 8 | 16  # ambos hurtboxes
		_:
			hitbox.collision_mask = 8 | 16


func _exit_tree() -> void:
	print("[HitboxService] Limpiado.")
