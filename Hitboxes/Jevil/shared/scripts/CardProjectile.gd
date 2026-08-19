# CardProjectile.gd
# Proyectil de cartas para las fases evolucionadas de Diamond Rain.
# Extiende Hitbox para reutilizar detección de impacto, filtro de equipo y
# expiración, pero sobrescribe el movimiento con modos especiales:
#   "straight"      → línea recta (comportamiento base)
#   "straight_spin" → línea recta girando sobre su propio eje
#   "homing_point"  → persigue un punto fijo mientras gira
#   "orbit"         → orbita un centro mientras gira
#   "carousel_ring" → rota sobre una elipse con frente/atrás (Carrusel)
#   "carousel_wave" → barrido horizontal con onda senoidal en Y (Carrusel)
extends "res://Hitboxes/Hitbox.gd"

# ── Modo de movimiento (asignado por la fase tras create) ──────────────
var mode: String = "straight"
var spin_speed: float = 0.0
var orbit_center: Vector2 = Vector2.ZERO
var orbit_radius: float = 0.0
var orbit_speed: float = 0.0
var orbit_angle: float = 0.0
## true cuando la fase ya asignó explícitamente orbit_angle (HeartRain); si es
## false, _move_orbit lo deriva de la posición de spawn (CarouselRain).
var orbit_angle_set: bool = false
var target_point: Vector2 = Vector2.ZERO

# ── Chase (cuadrado de corazones): el centro de órbita se desplaza hacia un nodo vivo ──
var chase_node: Node2D = null
var chase_speed: float = 0.0

# ── Traslación fija: el centro de órbita se desplaza en línea recta a velocidad constante.
# Si es distinto de ZERO, prevalece sobre el chase (se usa para Heart Chaos).
var orbit_translate: Vector2 = Vector2.ZERO

# ── Carousel ring (anillos elípticos del carrusel) ──────────────────────
## Modo "carousel_ring": el caballo rota sobre una elipse (ring_radius_x >>
## ring_radius_y) alrededor de orbit_center, con un bamboleo global del anillo
## y un efecto frente/atrás (modulate/scale/z_index) que da la ilusión de un
## cilindro 3D. Solo los caballos del FRENTE golpean (mask base restaurada).
var ring_radius_x: float = 0.0
var ring_radius_y: float = 0.0
var wobble_speed: float = 0.0
var wobble_amp: float = 0.0
var wobble_phase: float = 0.0
## Máscara de colisión base que puso HitboxService (se restaura al pasar al frente).
var _base_collision_mask: int = 0
## Tiempo (s) desde el spawn durante el cual el caballo NO colisiona (telegraph).
var hitbox_delay: float = 0.0
## Radio inicial de entrada como multiplicador del radio del aro: el caballo
## "entra" desde afuera del carril y se desliza hasta el radio real mientras
## se materializa (fade-in).
var entry_excess: float = 1.4
## Segundos de desvanecimiento antes del fin de vida. Durante este tramo la
## hitbox NO colisiona (deja de hacer daño mientras el caballo se va).
var exit_fade_time: float = 0.4

# ── Carousel wave (barrido tipo carrusel de Deltarune) ──────────────────
## Avance horizontal constante mientras el caballo bobea en Y sobre base_y con
## una onda senoidal, y además una inclinación lenta (skew) que hace que el
## camino de la columna fluctúe.
var translation_speed: float = 0.0
var wave_bob_speed: float = 0.0
var wave_bob_amp: float = 0.0
var wave_phase: float = 0.0
var skew_amp: float = 0.0
var skew_speed: float = 0.0
var skew_phase: float = 0.0
## Altura sobre la que oscila (derivada de la posición de spawn).
var base_y: float = 0.0
var _elapsed: float = 0.0

# ── Visual placeholder ──────────────────────────────────────────────────
var symbol: String = "diamond"
var symbol_color: Color = Color(1, 1, 1)

## Escala base del sprite tomada de la escena; el efecto frente/atrás solo
## aplica la diferencia de profundidad sobre esta base.
var _sprite_base_scale := Vector2(2.0, 2.0)


func _ready() -> void:
	super._ready()
	if not multiplayer.is_server():
		return
	_base_collision_mask = collision_mask
	if hitbox_delay > 0.0:
		collision_mask = 0
	var spr: Node2D = get_node_or_null("AnimatedSprite2D")
	if spr:
		_sprite_base_scale = spr.scale


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if _expired or _impacted:
		return

	match mode:
		"straight_spin":
			_move_straight(delta)
			rotation += spin_speed * delta
		"homing_point":
			_move_homing(delta)
			rotation += spin_speed * delta
		"orbit":
			_move_orbit(delta)
		"carousel_ring":
			_move_carousel_ring(delta)
		"carousel_wave":
			_move_carousel_wave(delta)
		_:
			_move_straight(delta)


func _move_straight(delta: float) -> void:
	if speed <= 0.0:
		return
	var step := speed * delta
	global_position += _direction * step
	if hitbox_max_range > 0.0:
		_travel_distance += step
		if _travel_distance >= hitbox_max_range:
			_do_impact(true)


func _move_homing(delta: float) -> void:
	var to_target := target_point - global_position
	if to_target.length() < 12.0:
		return
	_direction = to_target.normalized()
	if speed <= 0.0:
		return
	var step := speed * delta
	global_position += _direction * step
	if hitbox_max_range > 0.0:
		_travel_distance += step
		if _travel_distance >= hitbox_max_range:
			_do_impact(true)


func _move_orbit(delta: float) -> void:
	if orbit_translate != Vector2.ZERO:
		orbit_center += orbit_translate * delta
	elif is_instance_valid(chase_node) and chase_speed > 0.0:
		var to_target: Vector2 = chase_node.global_position - orbit_center
		var step := chase_speed * delta
		if to_target.length() <= step:
			orbit_center = chase_node.global_position
		else:
			orbit_center += to_target.normalized() * step
	if not orbit_angle_set:
		orbit_angle_set = true
		orbit_angle = (global_position - orbit_center).angle()
	orbit_angle += orbit_speed * delta
	global_position = orbit_center + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius
	rotation += spin_speed * delta


func _move_carousel_ring(delta: float) -> void:
	orbit_angle += orbit_speed * delta
	_elapsed += delta
	# Ola que viaja por el aro: la fase depende del ángulo actual, así los
	# caballos adyacentes bobean en contra-fase (efecto "pill shape wave").
	var wobble_y := sin(_elapsed * wobble_speed + orbit_angle) * wobble_amp

	# Entrada: durante el telegraph el caballo "entra" desde afuera del aro
	# (radio * entry_excess) deslizándose hasta el radio real con suavizado.
	var entry_t: float = 1.0
	if hitbox_delay > 0.0:
		entry_t = smoothstep(0.0, 1.0, clampf(_elapsed / hitbox_delay, 0.0, 1.0))
	var radius_x := lerpf(ring_radius_x * entry_excess, ring_radius_x, entry_t)
	var radius_y := lerpf(ring_radius_y * entry_excess, ring_radius_y, entry_t)

	global_position = orbit_center + Vector2(cos(orbit_angle) * radius_x, sin(orbit_angle) * radius_y + wobble_y)

	var is_front := sin(orbit_angle) > 0.0

	# Salida: en los últimos exit_fade_time segundos el caballo se desvanece.
	var exit_t: float = 1.0
	if lifetime > 0.0 and exit_fade_time > 0.0:
		exit_t = clampf((lifetime - _elapsed) / exit_fade_time, 0.0, 1.0)

	# Modulate frente/atrás combinado con fade-in (entrada) y fade-out (salida).
	if is_front:
		modulate = Color.WHITE
		modulate.a *= entry_t * exit_t
	else:
		modulate = Color(0.35, 0.35, 0.4, 0.85)
		modulate.a *= entry_t * exit_t

	# La colisión se activa recién después de hitbox_delay (telegraph) y se
	# DESACTIVA al comenzar el desvanecimiento: el caballo que está saliendo
	# no hace daño. Solo golpean los del frente durante la fase activa.
	if _elapsed < hitbox_delay or exit_t <= 0.999 or not is_front:
		collision_mask = 0
	elif is_front:
		collision_mask = _base_collision_mask
	else:
		collision_mask = 0
	_set_depth_visual(is_front)
	rotation += spin_speed * delta


func _set_depth_visual(is_front: bool) -> void:
	var sprite: Node2D = get_node_or_null("AnimatedSprite2D")
	if not sprite:
		return
	if is_front:
		sprite.scale = _sprite_base_scale
		sprite.z_index = 10
	else:
		sprite.scale = _sprite_base_scale * 0.85
		sprite.z_index = 1


func _move_carousel_wave(delta: float) -> void:
	var step := translation_speed * delta
	global_position += _direction * step
	_elapsed += delta
	global_position.y = base_y \
		+ sin(_elapsed * wave_bob_speed + wave_phase) * wave_bob_amp \
		+ sin(_elapsed * skew_speed + skew_phase) * skew_amp
	rotation += spin_speed * delta
	if hitbox_max_range > 0.0:
		_travel_distance += step
		if _travel_distance >= hitbox_max_range:
			_do_impact(true)


func _draw() -> void:
	if get_node_or_null("AnimatedSprite2D") or get_node_or_null("Sprite2D"):
		return
	PlaceholderSymbol.draw_symbol(self, symbol, symbol_color, 18.0)
