# Hitbox.gd
# Clase base para todos los hitboxes del juego.
# HitboxService lo instancia y configura antes de añadirlo al árbol.
# Solo vive en el servidor.
#
# Tipos soportados (definido en HitboxService via "type"):
#   "slash"      → área fija, un solo golpe, desaparece
#   "area"       → área fija, golpe múltiple hasta expirar
#   "attached"   → sigue al jugador mientras dura
#   "projectile" → viaja en dirección, golpea al primero y desaparece
#   "zone"       → zona fija en el mapa, dura X segundos, golpea múltiples veces
extends Area2D

# ── Asignados por HitboxService antes de add_child() ──────────────────
var attacker_id:  int     = -1
var attacker_node: Node   = null   # referencia al nodo del atacante (para "attached")
var damage:       int     = 10
var attack_type:  String  = "normal"

# Cuántos targets puede golpear (0 = ilimitado)
var hit_limit:    int     = 1

# Filtro de equipo — a quién puede golpear
# "enemy" = solo enemigos, "ally" = solo aliados, "all" = todos menos el atacante
var team_filter:  String  = "enemy"

# Duración en segundos (0 = desaparece al primer golpe sin timer)
var lifetime:     float   = 0.25

# Velocidad para proyectiles (px/s)
var speed:        float   = 0.0

# Modo de orientación — resuelto por HitboxService antes de instanciar
# "mouse" | "facing" | "fixed" | "origin"
var aim_mode:     String  = "fixed"

## Si true, el hitbox colisiona con paredes (StaticBody2D).
var detect_walls: bool    = false

## Tiempo en segundos entre impacto y desaparición (para animación "hit").
## 0 = desaparece instantáneamente al impactar.
var impact_lifetime: float = 0.0

## Distancia máxima que puede recorrer antes de auto-expirar (0 = ilimitado).
var hitbox_max_range: float = 0.0

# Callbacks
var on_hit_callback: Callable
var on_end_callback: Callable

# ── Estado interno ─────────────────────────────────────────────────────
var _hit_count:   int    = 0
var _expired:     bool   = false
var _impacted:    bool   = false
var _direction:   Vector2 = Vector2.RIGHT
var _travel_distance: float = 0.0
# Targets ya golpeados en este hitbox (evita doble golpe al mismo target)
var _hit_targets: Array  = []

# ── Inicialización ─────────────────────────────────────────────────────
func _ready() -> void:
	# Clientes: solo visual, sin colisión ni lógica de servidor.
	if not multiplayer.is_server():
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		# Reproducir animación de viaje en clientes para que las picas sean visibles.
		var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
		if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("travel"):
			anim_sprite.play("travel")
		return
	set_multiplayer_authority(1)
	area_entered.connect(_on_area_entered)
	if detect_walls:
		body_entered.connect(_on_body_entered)
	if lifetime > 0.0:
		get_tree().create_timer(lifetime).timeout.connect(_expire)

func set_direction(dir: Vector2) -> void:
	_direction = dir.normalized()
	rotation = _direction.angle()

# ── Proceso (solo proyectiles y attached usan _physics_process) ────────
func _physics_process(delta: float) -> void:
	if _expired or _impacted:
		return
	# Proyectil: avanza en dirección
	if speed > 0.0 and attacker_node == null:
		var step: float = speed * delta
		global_position += _direction * step
		# Auto-expirar si excede la distancia máxima
		if hitbox_max_range > 0.0:
			_travel_distance += step
			if _travel_distance >= hitbox_max_range:
				_do_impact(true)
	# Attached: sigue al atacante
	elif attacker_node != null and is_instance_valid(attacker_node):
		global_position = attacker_node.global_position + _direction * _get_offset()

# ── Detección ──────────────────────────────────────────────────────────
func _on_area_entered(area: Area2D) -> void:
	if _expired or _impacted:
		return
	if not area.is_in_group("hurtbox"):
		return

	var target: Node = area.get_parent()
	if not target or not target.is_in_group("players"):
		return

	# Sin auto-golpe
	var target_id: int = target.get_multiplayer_authority()
	if target_id == attacker_id:
		return

	# Filtro de equipo
	if not _passes_team_filter(target):
		return

	# Evitar golpear al mismo target dos veces en hitboxes multi-hit
	if _hit_targets.has(target_id):
		return
	_hit_targets.append(target_id)

	_hit_count += 1
	if on_hit_callback.is_valid():
		on_hit_callback.call(target)

	# Proyectil: impactar al alcanzar hit_limit
	if hit_limit > 0 and _hit_count >= hit_limit:
		if impact_lifetime > 0.0:
			_do_impact()
		else:
			_expire()

# ── Impacto con pared ─────────────────────────────────────────────────
func _on_body_entered(body: Node2D) -> void:
	if _expired or _impacted:
		return
	if body is StaticBody2D:
		_do_impact()


# ── Impacto (pared o jugador) ─────────────────────────────────────────
func _do_impact(timeout_expire: bool = false) -> void:
	if _impacted:
		return
	_impacted = true
	set_physics_process(false)
	speed = 0.0

	var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if anim_sprite and anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("hit"):
		anim_sprite.play("hit")

	if timeout_expire:
		_expire()
	elif impact_lifetime > 0.0:
		get_tree().create_timer(impact_lifetime).timeout.connect(_expire)
	else:
		_expire()


# ── Expiración ─────────────────────────────────────────────────────────
func _expire() -> void:
	if _expired:
		return
	_expired = true
	set_physics_process(false)
	if on_end_callback.is_valid():
		on_end_callback.call(_hit_count)
	queue_free()

# ── Helpers ────────────────────────────────────────────────────────────
func _passes_team_filter(target: Node) -> bool:
	if team_filter == "all":
		return true
	var attacker_team := _get_attacker_team()
	var target_team: String = target.character_data.team if target.character_data else ""
	if team_filter == "enemy":
		return target_team != attacker_team
	if team_filter == "ally":
		return target_team == attacker_team
	return true

func _get_attacker_team() -> String:
	if attacker_node and attacker_node.character_data:
		return attacker_node.character_data.team
	return ""

func _get_offset() -> float:
	# Offset por defecto para hitboxes attached
	return 40.0
