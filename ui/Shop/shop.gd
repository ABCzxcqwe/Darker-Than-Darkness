extends Control

## Tienda animada (Seam) del hub. Ocupa el viewport completo (1440x1080).
## Menu jerarquico: SKINS -> SUPERVIVIENTES/KILLERS -> personajes -> skins.

signal option_selected(action: String)
signal closed

const FONT := preload("res://Fonts/deltarune font.ttf")

const ANIM_IDLE := &"shop_idle"
const ANIM_LAUGH := &"shop_laugh"
const ANIM_ACT1 := &"shop_act1"
const LAUGH_REPEATS := 2

const ACT1_INTERVAL := 5.0
const ACT1_CHANCE := 0.50

const SHOP_MUSIC := "res://ui/Shop/shop_seam.ogg"

const MAIN_OPTIONS: Array[String] = ["skins", "fondo", "salir"]
const CATEGORY_OPTIONS: Array[String] = ["skins_survivors", "skins_killers"]
const SURVIVOR_OPTIONS: Array[String] = ["skins_kris", "skins_susie", "skins_ralsei"]
const KILLER_OPTIONS: Array[String] = ["skins_jevil", "skins_king"]
const KRIS_SKIN_OPTIONS: Array[String] = ["skin_default", "new_kris"]

const COLOR_NORMAL := Color(1, 1, 1, 1)
const COLOR_SELECTED := Color(1, 0.94, 0.35, 1)
const COLOR_DIM := Color(0.5, 0.5, 0.5, 1)

enum MenuLevel { MAIN, CATEGORIES, SURVIVORS, KILLERS, KRIS_SKINS }

@export var frame_size: Vector2 = Vector2(232, 174)
@export var fit_to_viewport: bool = true
@export var snap_to_integer_scale: bool = false

var shop_anim: AnimatedSprite2D = null
var _soul: TextureRect = null

var _skins_label: Label = null
var _fondo_label: Label = null
var _salir_label: Label = null

var _skins_menu: Control = null
var _categories_menu: Control = null
var _survivors_menu: Control = null
var _killers_menu: Control = null
var _kris_skins_menu: Control = null

var _survivors_label: Label = null
var _killers_label: Label = null
var _kris_label: Label = null
var _susie_label: Label = null
var _ralsei_label: Label = null
var _jevil_label: Label = null
var _king_label: Label = null
var _skin_default_label: Label = null
var _new_kris_label: Label = null

var _main_labels: Array[Label] = []
var _category_labels: Array[Label] = []
var _survivor_labels: Array[Label] = []
var _killer_labels: Array[Label] = []
var _kris_skin_labels: Array[Label] = []

var _labels: Array[Label] = []
var _options: Array[String] = []

var _level := MenuLevel.MAIN
var _index := 0
var _laugh_left := 0
var _playing_act1 := false
var _act1_timer: Timer = null


func _ready() -> void:
	add_to_group(GroupNames.GAME_MENU)
	_resolve_nodes()
	if shop_anim == null:
		push_error("[Shop] No se encontro ShopAnim; la tienda no puede animarse.")
		return
	_build_lists()
	_apply_texts()
	_apply_style()
	_fit()
	if get_viewport():
		get_viewport().size_changed.connect(_fit)
	if _soul:
		MenuUtils.init_soul(_soul)
	shop_anim.animation_finished.connect(_on_animation_finished)
	shop_anim.play(ANIM_IDLE)
	_create_act1_timer()
	_enter_level(MenuLevel.MAIN)


func is_open() -> bool:
	return visible


func open_shop() -> void:
	if shop_anim == null:
		return
	visible = true
	_enter_level(MenuLevel.MAIN)
	_reset_oneshots()
	_play(ANIM_IDLE)
	_play_shop_music()
	if _act1_timer:
		_act1_timer.start()
	_play_sfx(SfxId.SELECT)


func close_shop() -> void:
	if not visible:
		return
	visible = false
	if _act1_timer:
		_act1_timer.stop()
	_restore_hub_music()
	closed.emit()


## Reproduce la risa dos veces y vuelve al idle. Se usa al comprar.
func play_laugh() -> void:
	if shop_anim == null or shop_anim.sprite_frames == null:
		return
	if not shop_anim.sprite_frames.has_animation(ANIM_LAUGH):
		return
	_playing_act1 = false
	_laugh_left = LAUGH_REPEATS
	shop_anim.sprite_frames.set_animation_loop(ANIM_LAUGH, false)
	shop_anim.play(ANIM_LAUGH)


func play_act1() -> void:
	if shop_anim == null or _laugh_left > 0 or _playing_act1:
		return
	if shop_anim.sprite_frames == null:
		return
	if not shop_anim.sprite_frames.has_animation(ANIM_ACT1):
		return
	_playing_act1 = true
	shop_anim.sprite_frames.set_animation_loop(ANIM_ACT1, false)
	shop_anim.play(ANIM_ACT1)


func _on_animation_finished() -> void:
	if shop_anim == null:
		return
	var finished := shop_anim.animation
	if finished == ANIM_ACT1:
		_playing_act1 = false
		if shop_anim.sprite_frames:
			shop_anim.sprite_frames.set_animation_loop(ANIM_ACT1, true)
		_play(ANIM_IDLE)
		return
	if finished == ANIM_LAUGH:
		if _laugh_left > 1:
			_laugh_left -= 1
			shop_anim.play(ANIM_LAUGH)
			return
		_laugh_left = 0
		if shop_anim.sprite_frames:
			shop_anim.sprite_frames.set_animation_loop(ANIM_LAUGH, true)
		_play(ANIM_IDLE)
		return
	_play(ANIM_IDLE)


func _reset_oneshots() -> void:
	_laugh_left = 0
	_playing_act1 = false
	if shop_anim and shop_anim.sprite_frames:
		shop_anim.sprite_frames.set_animation_loop(ANIM_LAUGH, true)
		shop_anim.sprite_frames.set_animation_loop(ANIM_ACT1, true)


func _create_act1_timer() -> void:
	_act1_timer = Timer.new()
	_act1_timer.wait_time = ACT1_INTERVAL
	_act1_timer.one_shot = false
	_act1_timer.timeout.connect(_on_act1_tick)
	add_child(_act1_timer)


func _on_act1_tick() -> void:
	if not visible or shop_anim == null:
		return
	if _laugh_left > 0 or _playing_act1:
		return
	if shop_anim.animation != ANIM_IDLE:
		return
	if randf() <= ACT1_CHANCE:
		play_act1()


func _play(anim: StringName) -> void:
	if shop_anim and shop_anim.sprite_frames and shop_anim.sprite_frames.has_animation(anim):
		shop_anim.play(anim)


func _fit() -> void:
	if not fit_to_viewport or shop_anim == null:
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
		if _level == MenuLevel.MAIN:
			close_shop()
		else:
			_go_back()
			_play_sfx(SfxId.MENU_MOVE)
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
	var action: String = _options[_index]
	if _level == MenuLevel.MAIN:
		if action == "skins":
			_play_sfx(SfxId.SELECT)
			_enter_level(MenuLevel.CATEGORIES)
		elif action == "salir":
			close_shop()
		else:
			_play_sfx(SfxId.SELECT)
			option_selected.emit(action)
	elif _level == MenuLevel.CATEGORIES:
		_play_sfx(SfxId.SELECT)
		if action == "skins_survivors":
			_enter_level(MenuLevel.SURVIVORS)
		elif action == "skins_killers":
			_enter_level(MenuLevel.KILLERS)
	elif _level == MenuLevel.SURVIVORS:
		_play_sfx(SfxId.SELECT)
		if action == "skins_kris":
			_enter_level(MenuLevel.KRIS_SKINS)
	elif _level == MenuLevel.KILLERS:
		_play_sfx(SfxId.SELECT)
	elif _level == MenuLevel.KRIS_SKINS:
		_play_sfx(SfxId.SELECT)
		if action == "new_kris":
			option_selected.emit("new_kris")
			play_laugh()


func _go_back() -> void:
	match _level:
		MenuLevel.KRIS_SKINS:
			_enter_level(MenuLevel.SURVIVORS)
		MenuLevel.SURVIVORS, MenuLevel.KILLERS:
			_enter_level(MenuLevel.CATEGORIES)
		MenuLevel.CATEGORIES:
			_enter_level(MenuLevel.MAIN)
		_:
			close_shop()


func _enter_level(level: MenuLevel) -> void:
	var new_labels: Array[Label] = []
	var new_options: Array[String] = []
	var active_menu: Control = null
	match level:
		MenuLevel.MAIN:
			new_labels = _main_labels
			new_options = MAIN_OPTIONS
		MenuLevel.CATEGORIES:
			new_labels = _category_labels
			new_options = CATEGORY_OPTIONS
			active_menu = _categories_menu
		MenuLevel.SURVIVORS:
			new_labels = _survivor_labels
			new_options = SURVIVOR_OPTIONS
			active_menu = _survivors_menu
		MenuLevel.KILLERS:
			new_labels = _killer_labels
			new_options = KILLER_OPTIONS
			active_menu = _killers_menu
		MenuLevel.KRIS_SKINS:
			new_labels = _kris_skin_labels
			new_options = KRIS_SKIN_OPTIONS
			active_menu = _kris_skins_menu
	if level != MenuLevel.MAIN and new_labels.is_empty():
		push_warning("[Shop] Nivel de menu sin labels: %d" % level)
		return
	_level = level
	_labels = new_labels
	_options = new_options
	_index = 0
	if level == MenuLevel.MAIN:
		if is_instance_valid(_skins_menu):
			_skins_menu.visible = false
	else:
		_show_skins_level(active_menu)
	_refresh_highlight()
	_position_soul(true)


func _show_skins_level(active: Control) -> void:
	if is_instance_valid(_skins_menu):
		_skins_menu.visible = true
	for menu in [_categories_menu, _survivors_menu, _killers_menu, _kris_skins_menu]:
		if is_instance_valid(menu):
			menu.visible = menu == active


func _refresh_highlight() -> void:
	var main_active := _level == MenuLevel.MAIN
	for i in _main_labels.size():
		var color := COLOR_NORMAL
		if main_active:
			color = COLOR_SELECTED if i == _index else COLOR_NORMAL
		else:
			color = COLOR_DIM
		_main_labels[i].add_theme_color_override("font_color", color)
	if not main_active:
		for i in _labels.size():
			var color := COLOR_SELECTED if i == _index else COLOR_NORMAL
			_labels[i].add_theme_color_override("font_color", color)


func _position_soul(instant: bool) -> void:
	if _soul == null or _labels.is_empty():
		return
	if _index < 0 or _index >= _labels.size():
		return
	MenuUtils.move_soul(_soul, _labels[_index], instant, 14.0, false)


func _apply_texts() -> void:
	if _skins_label:
		_skins_label.text = _tr2("SHOP_SKINS", "SKINS", "SKINS")
	if _fondo_label:
		_fondo_label.text = _tr2("SHOP_BG", "FONDO", "BACKGROUND")
	if _salir_label:
		_salir_label.text = _tr2("SHOP_EXIT", "SALIR", "EXIT")
	if _survivors_label:
		_survivors_label.text = _tr2("SHOP_SURVIVORS", "SUPERVIVIENTES", "SURVIVORS")
	if _killers_label:
		_killers_label.text = _tr2("SHOP_KILLERS", "KILLERS", "KILLERS")
	if _kris_label:
		_kris_label.text = "KRIS"
	if _susie_label:
		_susie_label.text = "SUSIE"
	if _ralsei_label:
		_ralsei_label.text = "RALSEI"
	if _jevil_label:
		_jevil_label.text = "JEVIL"
	if _king_label:
		_king_label.text = "KING"
	if _skin_default_label:
		_skin_default_label.text = _tr2("SHOP_SKIN_DEFAULT", "SKIN POR DEFECTO", "DEFAULT SKIN")
	if _new_kris_label:
		_new_kris_label.text = _tr2("SHOP_NEW_KRIS", "NUEVO KRIS", "NEW KRIS")


func _tr2(key: String, es: String, en: String) -> String:
	var translated := tr(key)
	if translated != key and translated != "":
		return translated
	return en if TranslationServer.get_locale().begins_with("en") else es


func _apply_style() -> void:
	for label in _main_labels:
		_style_label(label)
	for label in _category_labels:
		_style_label(label)
	for label in _survivor_labels:
		_style_label(label)
	for label in _killer_labels:
		_style_label(label)
	for label in _kris_skin_labels:
		_style_label(label)


func _style_label(label: Label) -> void:
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 30)


func _resolve_nodes() -> void:
	shop_anim = get_node_or_null("ShopAnim") as AnimatedSprite2D
	_soul = get_node_or_null("OptionsRoot/SoulCursor") as TextureRect

	_skins_label = _find_label(["OptionsRoot/SkinsLabel", "OptionsRoot/Options/SkinsLabel"])
	_fondo_label = _find_label(["OptionsRoot/FondoLabel", "OptionsRoot/Options/FondoLabel"])
	_salir_label = _find_label(["OptionsRoot/SalirLabel", "OptionsRoot/Options/SalirLabel"])

	_skins_menu = get_node_or_null("OptionsRoot/SkinsMenu") as Control
	_categories_menu = get_node_or_null("OptionsRoot/SkinsMenu/CategoriesMenu") as Control
	_survivors_menu = get_node_or_null("OptionsRoot/SkinsMenu/SurvivorsMenu") as Control
	_killers_menu = get_node_or_null("OptionsRoot/SkinsMenu/KillersMenu") as Control
	_kris_skins_menu = get_node_or_null("OptionsRoot/SkinsMenu/KrisSkinsMenu") as Control

	_survivors_label = _find_label([
		"OptionsRoot/SkinsMenu/CategoriesMenu/SurvivorsLabel",
		"OptionsRoot/SkinsMenu/SurvivorsLabel",
		"OptionsRoot/SkinsMenu/Label",
	])
	_killers_label = _find_label([
		"OptionsRoot/SkinsMenu/CategoriesMenu/KillersLabel",
		"OptionsRoot/SkinsMenu/KillersLabel",
	])
	_kris_label = _find_label(["OptionsRoot/SkinsMenu/SurvivorsMenu/KrisLabel"])
	_susie_label = _find_label(["OptionsRoot/SkinsMenu/SurvivorsMenu/SusieLabel"])
	_ralsei_label = _find_label(["OptionsRoot/SkinsMenu/SurvivorsMenu/RalseiLabel"])
	_jevil_label = _find_label(["OptionsRoot/SkinsMenu/KillersMenu/JevilLabel"])
	_king_label = _find_label(["OptionsRoot/SkinsMenu/KillersMenu/KingLabel"])
	_skin_default_label = _find_label(["OptionsRoot/SkinsMenu/KrisSkinsMenu/SkinDefaultLabel"])
	_new_kris_label = _find_label(["OptionsRoot/SkinsMenu/KrisSkinsMenu/NewKrisLabel"])


func _find_label(paths: Array[String]) -> Label:
	for path in paths:
		var node := get_node_or_null(path)
		if node is Label:
			return node as Label
	return null


func _build_lists() -> void:
	_main_labels.clear()
	_category_labels.clear()
	_survivor_labels.clear()
	_killer_labels.clear()
	_kris_skin_labels.clear()
	if _skins_label:
		_main_labels.append(_skins_label)
	if _fondo_label:
		_main_labels.append(_fondo_label)
	if _salir_label:
		_main_labels.append(_salir_label)
	if _survivors_label:
		_category_labels.append(_survivors_label)
	if _killers_label:
		_category_labels.append(_killers_label)
	if _kris_label:
		_survivor_labels.append(_kris_label)
	if _susie_label:
		_survivor_labels.append(_susie_label)
	if _ralsei_label:
		_survivor_labels.append(_ralsei_label)
	if _jevil_label:
		_killer_labels.append(_jevil_label)
	if _king_label:
		_killer_labels.append(_king_label)
	if _skin_default_label:
		_kris_skin_labels.append(_skin_default_label)
	if _new_kris_label:
		_kris_skin_labels.append(_new_kris_label)
	_labels = _main_labels
	_options = MAIN_OPTIONS
	_index = 0
	if is_instance_valid(_skins_menu):
		_skins_menu.visible = false
	for menu in [_categories_menu, _survivors_menu, _killers_menu, _kris_skins_menu]:
		if is_instance_valid(menu):
			menu.visible = false


func _play_shop_music() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_menu_drone"):
		am.play_menu_drone(SHOP_MUSIC)


func _restore_hub_music() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_menu_drone"):
		am.play_menu_drone()


func _play_sfx(sfx: int) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx_ui"):
		am.play_sfx_ui(sfx)
