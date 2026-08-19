# ExplosiveCharge.gd
# Carga con forma de corazón/trébol que cae en los laterales del área de
# combate (si 'falling' está activo, desciende en vertical). Con un timer
# aleatorio (fuse): parpadea + SFX (modo clásico) o, si stop_before_explode
# > 0, se DETIENE con SFX y muestra el anillo del radio de explosión; luego
# explota + SFX.
# Al explotar ejecuta on_explode (solo servidor, donde existe la callable).
# Los clientes solo ven el parpadeo/anillo (modulate + armed replicados) y el
# fade-out.
extends Area2D

# ── Config (asignada por la fase antes/durante el spawn) ────────────────
var attacker_id: int = -1
var attacker_node: Node = null
var damage: int = 20
var attack_type: String = "normal"
var team_filter: String = "enemy"

var fuse: float = 2.0
var blink_duration: float = 0.5
var on_explode: Callable

## Modo detención (reemplaza al parpadeo): si > 0, la carga deja de caer y
## muestra el anillo del radio de explosión `stop_before_explode` segundos
## antes de explotar. 'armed' y 'explosion_radius' se replican para que el
## anillo también se vea en los clientes.
var stop_before_explode: float = 0.0
var armed: bool = false

# ── Caída (opcional; la fase la activa si la carga debe descender) ──────
var falling: bool = false
var fall_speed: float = 500.0

# ── Explosión propia (formato travel→hit, sin escena aparte) ───────────
# Si explosion_radius > 0, la propia carga se convierte en el hitbox de
# área al explotar: escala su shape al radio, activa colisión, daña a todos
# los target válidos (hit_limit ilimitado) y reproduce la anim "hit".
# Con 0 queda el comportamiento antiguo (la fase spawnea su propia explosión).
var explosion_radius: float = 0.0
var explosion_lifetime: float = 0.35

# ── Visual ──────────────────────────────────────────────────────────────
var symbol: String = "heart"
var symbol_color: Color = Color(1.0, 0.3, 0.4)

# ── Estado interno ──────────────────────────────────────────────────────
var _elapsed: float = 0.0
var _blinking: bool = false
var _blink_t: float = 0.0
var exploded: bool = false
var _fading: float = 0.0
var _hit_played: bool = false

const FADE_OUT: float = 0.35
const BLINK_FREQ: float = 18.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	modulate = Color(1, 1, 1, 1)


func _process(delta: float) -> void:
	# Redibujar cada frame en todos los peers para que el anillo aparezca en
	# los clientes cuando 'armed' se replica (y desaparezca al explotar).
	queue_redraw()

	# Los clientes solo renderizan: el fuse/detención/explosión lo maneja el
	# servidor (autoridad) y se replica vía armed/exploded/modulate. Al liberar
	# el nodo en el servidor, el MultiplayerSpawner lo des-spawnea en clientes.
	if exploded:
		_fading -= delta
		_play_hit_once()
		return

	if not multiplayer.is_server():
		return

	if falling:
		global_position.y += fall_speed * delta

	_elapsed += delta

	if stop_before_explode > 0.0:
		# Modo detención: se frena y marca el anillo un instante antes de explotar.
		if not armed and _elapsed >= fuse - stop_before_explode:
			armed = true
			falling = false
			AudioManager.play_sfx_networked.rpc(SfxId.SPELLCAST, global_position.x, global_position.y)
		if _elapsed >= fuse:
			_do_explode()
	elif _blinking:
		_blink_t += delta
		modulate.a = 0.35 + 0.65 * absf(sin(_blink_t * BLINK_FREQ))
		if _elapsed >= fuse:
			_do_explode()
	elif _elapsed >= fuse - blink_duration:
		_blinking = true
		_blink_t = 0.0
		AudioManager.play_sfx_networked.rpc(SfxId.SPELLCAST, global_position.x, global_position.y)


func _do_explode() -> void:
	if exploded:
		return
	exploded = true
	_fading = explosion_lifetime if explosion_radius > 0.0 else FADE_OUT

	if multiplayer.is_server():
		# Despawn con SceneTreeTimer (patrón de Hitbox.gd) en vez de dentro de
		# _process: le da al MultiplayerSpawner el flush de red del frame antes
		# de encolar el despawn, evitando despawns huérfanos en el cliente.
		get_tree().create_timer(_fading).timeout.connect(_self_despawn)
		AudioManager.play_sfx_networked.rpc(SfxId.EXPLOSION, global_position.x, global_position.y)
		if explosion_radius > 0.0:
			_setup_self_explosion()
		if on_explode.is_valid():
			on_explode.call(self)

	var tween := create_tween()
	# Mantener el sprite visible mientras la explosión hace daño, luego fundir.
	tween.tween_property(self, "modulate:a", 0.0, _fading)


## La anim "hit" se reproduce UNA vez en cada peer localmente (sin depender de
## la replicación de animation/frame), cuando el "exploded" replicado llega.
func _play_hit_once() -> void:
	if _hit_played:
		return
	_hit_played = true
	var anim := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim and anim.sprite_frames and anim.sprite_frames.has_animation("hit"):
		anim.play("hit")


func _self_despawn() -> void:
	if not multiplayer.is_server():
		return
	queue_free()


# La carga pasa a ser el hitbox de explosión en área (solo servidor).
func _setup_self_explosion() -> void:
	var shape := get_node_or_null("CollisionShape2D")
	if shape and shape.shape:
		var prev: float = shape.shape.radius
		if prev > 0.0:
			shape.scale = Vector2(explosion_radius / prev, explosion_radius / prev)

	# La anim "hit" la reproduce _play_hit_once (todos los peers, local).

	var attacker_team: String = ""
	if attacker_node and attacker_node.character_data:
		attacker_team = attacker_node.character_data.team
	collision_layer = 32
	collision_mask = 8 if attacker_team == "killer" else 16
	area_entered.connect(_on_explosion_area_entered)


func _on_explosion_area_entered(area: Area2D) -> void:
	if not area.is_in_group(GroupNames.HURTBOX):
		return
	var target: Node = area.get_parent()
	if not target or not target.is_in_group(GroupNames.PLAYERS):
		return
	if target.get_multiplayer_authority() == attacker_id:
		return
	if not _passes_explosion_team_filter(target):
		return
	var cmbt = GameServiceLocator.combat_mediator
	if cmbt and attacker_node:
		cmbt.apply_damage(attacker_node, target, damage, attack_type)


func _passes_explosion_team_filter(target: Node) -> bool:
	if team_filter == "all":
		return true
	var attacker_team: String = ""
	if attacker_node and attacker_node.character_data:
		attacker_team = attacker_node.character_data.team
	var target_team: String = target.character_data.team if target.character_data else ""
	if team_filter == "enemy":
		return target_team != attacker_team
	if team_filter == "ally":
		return target_team == attacker_team
	return true


func _draw() -> void:
	# Anillo del radio de explosión mientras la carga está detenida (armed).
	if armed and not exploded and explosion_radius > 0.0:
		draw_circle(Vector2.ZERO, explosion_radius, Color(1.0, 0.15, 0.15, 0.12))
		draw_arc(Vector2.ZERO, explosion_radius, 0.0, TAU, 48, Color(1.0, 0.25, 0.25, 0.85), 5.0, true)

	if get_node_or_null("AnimatedSprite2D") or get_node_or_null("Sprite2D"):
		return
	var size := 18.0
	if exploded:
		size += (1.0 - modulate.a) * 26.0
	PlaceholderSymbol.draw_symbol(self, symbol, symbol_color, size)
