extends Control

## Tienda animada (Seam) del hub. Ocupa el viewport completo (1440x1080)
## y muestra opciones estilo Deltarune abajo a la derecha.

signal option_selected(action: String)
signal closed

const FONT := preload("res://Fonts/deltarune font.ttf")

const ANIM_IDLE := &"shop_idle"
const ANIM_LAUGH := &"shop_laugh"
const LAUGH_REPEATS := 2

const OPTIONS: Array[String] = ["skins", "fondo", "salir"]

const COLOR_NORMAL := Color(1, 1, 1, 1)
const COLOR_SELECTED := Color(1, 0.94, 0.35, 1)

@export var frame_size: Vector2 = Vector2(232, 174)
@export var fit_to_viewport: bool = true
@export var snap_to_integer_scale: bool = false

@onready var shop_anim: AnimatedSprite2D = $ShopAnim
@onready var _soul: TextureRect = $OptionsRoot/SoulCursor
@onready var _skins_label: Label = $OptionsRoot/Options/SkinsLabel
@onready var _fondo_label: Label = $OptionsRoot/Options/FondoLabel
@onready var _salir_label: Label = $OptionsRoot/Options/SalirLabel

var _labels: Array[Label] = []
var _index := 0
var _laugh_left := 0


func _ready() -> void:
	add_to_group(GroupNames.GAME_MENU)
	_labels.append(_skins_label)
	_labels.append(_fondo_label)
	_labels.append(_salir_label)
	_apply_texts()
	_apply_style()
	_fit()
	if get_viewport():
		get_viewport().size_changed.connect(_fit)
	MenuUtils.init_soul(_soul)
	shop_anim.animation_finished.connect(_on_animation_finished)
	shop_anim.play(ANIM_IDLE)
	_refresh_highlight()
	_position_soul(true)


func is_open() -> bool:
	return visible


func open_shop() -> void:
	visible = true
	_index = 0
	_refresh_highlight()
	_position_soul(true)
	_play(ANIM_IDLE)
	_play_sfx(SfxId.SELECT)


func close_shop() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


## Reproduce la risa dos veces y vuelve al idle. Llamar tras una compra exitosa.
func play_laugh() -> void:
	if shop_anim.sprite_frames == null:
		return
	if not shop_anim.sprite_frames.has_animation(ANIM_LAUGH):
		return
	_laugh_left = LAUGH_REPEATS
	shop_anim.sprite_frames.set_animation_loop(ANIM_LAUGH, false)
	shop_anim.play(ANIM_LAUGH)


func _on_animation_finished() -> void:
	if _laugh_left > 1:
		_laugh_left -= 1
		shop_anim.play(ANIM_LAUGH)
		return
	if _laugh_left == 1:
		_laugh_left = 0
		if shop_anim.sprite_frames:
			shop_anim.sprite_frames.set_animation_loop(ANIM_LAUGH, true)
	_play(ANIM_IDLE)


func _play(anim: StringName) -> void:
	if shop_anim.sprite_frames and shop_anim.sprite_frames.has_animation(anim):
		shop_anim.play(anim)


func _fit() -> void:
	if not fit_to_viewport:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var s := minf(vp.x / frame_size.x, vp.y / frame_size.y)
	if snap_to_integer_scale:
		s = maxf(1.0, floorf(s))
	shop_anim.scale = Vector2(s, s)
	shop_anim.position = vp * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("menu_up"):
		_move(-1)
		_mark_handled()
	elif event.is_action_pressed("menu_down"):
		_move(1)
		_mark_handled()
	elif event.is_action_pressed("menu_accept") \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Z):
		_confirm()
		_mark_handled()
	elif event.is_action_pressed("menu_cancel") \
			or event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X):
		close_shop()
		_mark_handled()


func _mark_handled() -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()


func _move(dir: int) -> void:
	if _labels.is_empty():
		return
	_index = posmod(_index + dir, _labels.size())
	_refresh_highlight()
	_position_soul(false)
	_play_sfx(SfxId.MENU_MOVE)


func _confirm() -> void:
	if _labels.is_empty():
		return
	var action: String = OPTIONS[_index]
	if action == "salir":
		close_shop()
		return
	_play_sfx(SfxId.SELECT)
	option_selected.emit(action)


func _refresh_highlight() -> void:
	for i in _labels.size():
		var color := COLOR_SELECTED if i == _index else COLOR_NORMAL
		_labels[i].add_theme_color_override("font_color", color)


func _position_soul(instant: bool) -> void:
	if _labels.is_empty():
		return
	if _index < 0 or _index >= _labels.size():
		return
	MenuUtils.move_soul(_soul, _labels[_index], instant, 14.0, false)


func _apply_texts() -> void:
	_skins_label.text = _tr2("SHOP_SKINS", "SKINS", "SKINS")
	_fondo_label.text = _tr2("SHOP_BG", "FONDO", "BACKGROUND")
	_salir_label.text = _tr2("SHOP_EXIT", "SALIR", "EXIT")


func _tr2(key: String, es: String, en: String) -> String:
	var translated := tr(key)
	if translated != key and translated != "":
		return translated
	return en if TranslationServer.get_locale().begins_with("en") else es


func _apply_style() -> void:
	for label in _labels:
		label.add_theme_font_override("font", FONT)
		label.add_theme_font_size_override("font_size", 30)


func _play_sfx(sfx: int) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(sfx)
