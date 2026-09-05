# res://core/player/LobbyHeart.gd
# Corazon del lobby fisico - solo movimiento, sin habilidades ni emotes
extends CharacterBody2D

@onready var sprite: Sprite2D = $Sprite2D
@onready var synchronizer: MultiplayerSynchronizer = $Synchronizer
@onready var name_tag: PanelContainer = $NameTag

var _speed: float = 220.0

func _ready() -> void:
	add_to_group("lobby_hearts")
	_apply_color()
	_setup_name_tag()
	if not is_multiplayer_authority():
		if has_node("Camera2D"):
			$Camera2D.enabled = false
	else:
		var listener := AudioListener2D.new()
		add_child(listener)
		listener.make_current()
	# public_visibility=true ya replica a todos, no hace falta set_visibility_for


func _apply_color() -> void:
	var pid := get_multiplayer_authority()
	var col: Color = Color.WHITE
	if LobbyManager.players.has(pid):
		var c = LobbyManager.players[pid].get("lobby_color", Color.WHITE)
		if c is Color:
			col = c
		elif c is String:
			col = Color(c)
	if sprite:
		sprite.modulate = col


func _setup_name_tag() -> void:
	var pid := get_multiplayer_authority()
	if is_multiplayer_authority():
		name_tag.visible = false
		return
	var name_str: String = LobbyManager.players.get(pid, {}).get("name", "Jugador %d" % pid)
	var lbl: Label = name_tag.get_node("NameLabel")
	lbl.text = name_str
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0,0,0,0.6)
	style.border_color = Color.WHITE
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	name_tag.add_theme_stylebox_override("panel", style)
	var font := preload("res://Fonts/deltarune font.ttf")
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 12)


func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if not multiplayer.multiplayer_peer:
		return
	var dir := Vector2.ZERO
	dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var sprinting := Input.is_action_pressed("run") or Input.is_key_pressed(KEY_SHIFT)
	var cur_speed := _speed * (1.7 if sprinting else 1.0)
	if dir.length() > 0.1:
		velocity = dir.normalized() * cur_speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	if sprite and dir.x != 0:
		sprite.flip_h = dir.x < 0
