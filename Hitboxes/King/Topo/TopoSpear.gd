extends Node2D
# TopoSpear — Lanza Undyne vertical estática (sin gancho)
# Crece 3-5x desde el suelo (señal), hold 1s, retrae y se destruye. Solo daño 10.

var attacker_id: int = -1
var attacker_node: Node = null
var damage: int = 10
var attack_type: String = "normal"
var hit_limit: int = 0
var team_filter: String = "enemy"
var lifetime: float = 3.0
var speed: float = 0.0
var aim_mode: String = "fixed"
var detect_walls: bool = false
var impact_lifetime: float = 0.0
var hitbox_max_range: float = 0.0

# compatibles con HitboxService
var on_hit_callback: Callable
var on_end_callback: Callable

var origin: Vector2 = Vector2.ZERO

const TILE_SIZE: float = 96.0
const GROW_SPEED: float = 1400.0
const RETRACT_SPEED: float = 1800.0
const HOLD_TIME: float = 1.5
const HEAD_SIZE_Y: float = 84.0 # lanza_cabeza2.png height aprox

# Texturas verticales duplicadas (paradas)
const LANZA_TEX := preload("res://Characters/King/assets/Sprites/lanza2.png")
const LANZA_CABEZA_TEX := preload("res://Characters/King/assets/Sprites/lanza_cabeza2.png")

enum Phase { GROWING, HOLD, RETRACTING, DONE }

var _phase: int = Phase.GROWING
var _target_height: float = 0.0
var _current_height: float = 0.0:
	set(v):
		_current_height = v
		queue_redraw()
var _hit_done: bool = false
var _hold_timer: float = 0.0

var _ability: RefCounted = null
var _caster: Node = null


func setup_topo(ability: RefCounted, caster: Node, height_mult: float) -> void:
	_ability = ability
	_caster = caster
	_target_height = TILE_SIZE * clampf(height_mult, 2.0, 5.0)


func set_direction(_dir: Vector2) -> void:
	pass


func _ready() -> void:
	if not multiplayer.is_server():
		# Cliente: desactivar solo colisión/daño, mantener _process para dibujar
		var area_cli := $Hurtbox as Area2D
		if area_cli:
			area_cli.monitoring = false
			area_cli.monitorable = false
			area_cli.collision_layer = 0
			area_cli.collision_mask = 0
		queue_redraw()
		return
	set_multiplayer_authority(1)
	# Hitbox de daño: Area2D hijo
	var area := $Hurtbox as Area2D
	if area:
		area.monitoring = true
		area.collision_layer = 32 # hitbox
		area.collision_mask = 8 # survivor_hurtbox (HitboxService lo setea, pero por si acaso)
		area.area_entered.connect(_on_area_entered)
	# Tamaño inicial 0
	_current_height = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if not multiplayer.is_server() and _phase != Phase.DONE:
		queue_redraw()
		return
	if _phase == Phase.DONE:
		return

	match _phase:
		Phase.GROWING:
			_current_height = move_toward(_current_height, _target_height, GROW_SPEED * delta)
			_update_hurtbox()
			queue_redraw()
			if _current_height >= _target_height - 1.0:
				_phase = Phase.HOLD
				_hold_timer = HOLD_TIME
		Phase.HOLD:
			_hold_timer -= delta
			if _hold_timer <= 0.0:
				_phase = Phase.RETRACTING
		Phase.RETRACTING:
			_current_height = move_toward(_current_height, 0.0, RETRACT_SPEED * delta)
			_update_hurtbox()
			queue_redraw()
			if _current_height <= 1.0:
				_phase = Phase.DONE
				queue_free()
				if on_end_callback.is_valid():
					on_end_callback.call(0)
		_:
			pass


func _update_hurtbox() -> void:
	var area := get_node_or_null("Hurtbox") as Area2D
	var shape_node := get_node_or_null("Hurtbox/CollisionShape2D") as CollisionShape2D
	if not area or not shape_node:
		return
	var shape := shape_node.shape as RectangleShape2D
	if not shape:
		return
	# Hurtbox SOLO en la cabeza (últimos HEAD_SIZE_Y px)
	var head_h: float = HEAD_SIZE_Y
	var y_pos: float = -_current_height + head_h * 0.5
	shape.size = Vector2(40, head_h)
	shape_node.position = Vector2(0, y_pos)


func _on_area_entered(area: Area2D) -> void:
	if _hit_done:
		return
	if not multiplayer.is_server():
		return
	if not area.is_in_group("hurtbox"):
		return
	var target: Node = area.get_parent()
	if not target or not target.is_in_group("players"):
		return
	if target.get_multiplayer_authority() == attacker_id:
		return
	if not _passes_team_filter(target):
		return
	_hit_done = true
	var combat = GameServiceLocator.combat_mediator
	if combat and is_instance_valid(_caster):
		combat.apply_damage(_caster, target, damage, attack_type)
	if on_hit_callback.is_valid():
		on_hit_callback.call(target)


func _passes_team_filter(target: Node) -> bool:
	var attacker_team := ""
	if attacker_node and attacker_node.character_data:
		attacker_team = attacker_node.character_data.team
	elif _caster and _caster.character_data:
		attacker_team = _caster.character_data.team
	var target_team: String = target.character_data.team if target.character_data else ""
	if team_filter == "enemy":
		return target_team != attacker_team
	if team_filter == "ally":
		return target_team == attacker_team
	return true


func _draw() -> void:
	if _current_height < 4.0:
		return
	if not LANZA_TEX or not LANZA_CABEZA_TEX:
		return
	var seg_h: float = float(LANZA_TEX.get_height()) # ~30
	var seg_w: float = float(LANZA_TEX.get_width())  # ~18
	if seg_h <= 0.0 or seg_w <= 0.0:
		return
	var head_tex_size := LANZA_CABEZA_TEX.get_size() # 72x84
	if head_tex_size.y <= 0.0:
		return

	# Guard anti-congela: step nunca 0, límite iteraciones
	var step: float = seg_h * 0.9
	if step <= 0.0:
		step = seg_h
	var max_iter: int = 64
	var iter: int = 0
	# Dibujar asta tiled vertical
	var y: float = 0.0
	while y < _current_height - head_tex_size.y and iter < max_iter:
		draw_texture_rect(LANZA_TEX, Rect2(-seg_w * 0.5, -y - seg_h, seg_w, seg_h), false)
		y += step
		iter += 1

	# Cabeza en punta
	draw_texture_rect(LANZA_CABEZA_TEX, Rect2(-head_tex_size.x * 0.5, -_current_height, head_tex_size.x, head_tex_size.y), false)
