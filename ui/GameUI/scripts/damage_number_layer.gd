# ui/GameUI/scripts/damage_number_layer.gd
# Overlay en pantalla que muestra números de daño flotantes cuando alguien
# recibe daño. La animación usa integración de Euler en _process (rígida,
# estilo arcade): un eje Z simulado hace saltar el número y rebotar.
extends Control

const FONT_DELTARUNE := preload("res://Fonts/deltarune font.ttf")

const FONT_SIZE: int = 34
const CENTER_OFFSET_Y: float = 20.0

# ── Física del rebote (integración de Euler) ───────────────────────────
const JUMP_VEL: float   = -350.0    # impulso inicial hacia arriba
const GRAVITY: float    = 1200.0    # gravedad que lo baja
const BOUNCE_KEEP: float = 0.4      # energía que conserva cada rebote
const MAX_BOUNCES: int  = 2         # toques al suelo antes de congelarse

const X_SPEED: float    = 70.0      # deriva lateral hacia el lado del ataque

const QUIET_DELAY: float = 0.5      # segundos quieto antes de desvanecer
const FADE_SPEED: float  = 5.0      # modulate.a -= FADE_SPEED * delta


var _entries: Dictionary = {}
var _next_id: int = 0


func setup() -> void:
	var relay = GameServiceLocator.get_client_relay()
	if relay and relay.has_signal("damage_number_spawned"):
		if not relay.damage_number_spawned.is_connected(_on_damage_number_spawned):
			relay.damage_number_spawned.connect(_on_damage_number_spawned)


func _on_damage_number_spawned(peer_id: int, amount: int, pos_x: float, pos_y: float, rng_seed: int, dir_sign: float, color: Color) -> void:
	if amount <= 0:
		return

	var label := Label.new()
	label.text = str(amount)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT_DELTARUNE)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.reset_size()
	label.pivot_offset = label.size * 0.5

	add_child(label)

	var id := _next_id
	_next_id += 1
	_entries[id] = {
		"label": label,
		"peer_id": peer_id,
		"spawn_pos": Vector2(pos_x, pos_y),
		"z_pos": 0.0,
		"z_vel": JUMP_VEL,
		"gravity": GRAVITY,
		"bounces": 0,
		"x_vel": dir_sign * X_SPEED,
		"x_off": 0.0,
		"quiet": 0.0,
		"fading": false,
	}


func _process(delta: float) -> void:
	if _entries.is_empty():
		return
	var cam = get_viewport().get_camera_2d()

	var expired: Array = []
	for id in _entries.keys():
		var entry = _entries[id]
		var label: Label = entry["label"]
		if not is_instance_valid(label):
			expired.append(id)
			continue

		var z_pos: float = entry["z_pos"]
		var z_vel: float = entry["z_vel"]
		var gravity: float = entry["gravity"]
		var bounces: int = entry["bounces"]
		var x_off: float = entry["x_off"]
		var x_vel: float = entry["x_vel"]

		# ── Física rígida por frame (sin easing) ──
		if gravity > 0.0:
			z_vel += gravity * delta
			z_pos += z_vel * delta
			x_off += x_vel * delta

			if z_pos >= 0.0:
				z_pos = 0.0
				if bounces + 1 >= MAX_BOUNCES:
					z_vel = 0.0
					gravity = 0.0
				else:
					bounces += 1
					z_vel = -z_vel * BOUNCE_KEEP

		# ── Quieto: espera y luego desvanecimiento agresivo ──
		var fading: bool = entry["fading"]
		var alpha := label.modulate.a
		if gravity <= 0.0:
			if fading:
				alpha -= FADE_SPEED * delta
				if alpha <= 0.0:
					expired.append(id)
					continue
			else:
				var quiet: float = entry["quiet"] + delta
				if quiet >= QUIET_DELAY:
					fading = true
				entry["quiet"] = quiet

		# ── Posición (proyecta la posición del atacado a pantalla) ──
		var target_pos: Vector2 = entry["spawn_pos"]
		var player = _find_player_by_peer_id(entry["peer_id"])
		if player:
			target_pos = player.global_position

		var screen_pos: Vector2 = target_pos
		if cam:
			screen_pos = cam.get_canvas_transform() * target_pos

		label.position = screen_pos + Vector2(x_off, CENTER_OFFSET_Y + z_pos) - label.size * 0.5
		label.modulate = Color(1, 1, 1, alpha)

		# ── Guardar estado físico ──
		entry["z_pos"] = z_pos
		entry["z_vel"] = z_vel
		entry["gravity"] = gravity
		entry["bounces"] = bounces
		entry["x_off"] = x_off
		entry["fading"] = fading

	for id in expired:
		var entry = _entries[id]
		if is_instance_valid(entry["label"]):
			entry["label"].queue_free()
		_entries.erase(id)


func _find_player_by_peer_id(peer_id: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_multiplayer_authority() == peer_id:
			return p
	return null
