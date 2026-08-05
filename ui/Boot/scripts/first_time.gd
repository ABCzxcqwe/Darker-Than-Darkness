extends Control
## VesselCreation.gd
## Escena introductoria de creación de "Vessel" (estilo Deltarune - creación de FRISK/goner).
## Se muestra solo la primera vez que se abre el juego, o si settings_manager.vessel_data
## está vacío / first_launch_done == false.
##
## ---------------------------------------------------------------------
## SETUP DE ESCENA REQUERIDO (Control como raíz, anclado a pantalla completa):
##
## VesselCreation (Control)  <- este script
## ├── Background (ColorRect)               # fondo negro / agua
## ├── WaterBG (TextureRect)                 # textura de agua en loop (oculta al inicio)
## ├── RedLine (ColorRect)                   # línea roja vertical central (oculta al inicio)
## ├── Heart (TextureRect)                   # sprite del corazón (oculto al inicio)
## ├── MainLabel (Label)                     # texto central tipo "ARE YOU THERE?"
## ├── VesselPreview (Node2D)
## │   ├── HeadSprite (Sprite2D)
## │   ├── TorsoSprite (Sprite2D)
## │   └── LegsSprite (Sprite2D)
## ├── OptionsRow (HBoxContainer)             # fila de 5 opciones (partes) con TextureRect hijos
## ├── ChoiceHeart (TextureRect)              # corazón que se mueve sobre OptionsRow
## ├── MenuList (VBoxContainer)               # para YES/NO y lista de comida/color
## ├── NameEdit (LineEdit)                    # input de texto para el nombre (oculto hasta usarse)
## └── FadeRect (ColorRect)                   # negro fullscreen para fundidos, alpha 0 al inicio
##
## Ajusta los @onready paths de abajo si tu jerarquía difiere.
## ---------------------------------------------------------------------
 
@onready var background: ColorRect = $Background
@onready var water_bg: TextureRect = $WaterBG
@onready var red_line: ColorRect = $RedLine
@onready var heart: TextureRect = $Heart
@onready var main_label: Label = $MainLabel
@onready var vessel_preview: Node2D = $VesselPreview
@onready var head_sprite: Sprite2D = $VesselPreview/HeadSprite
@onready var torso_sprite: Sprite2D = $VesselPreview/TorsoSprite
@onready var legs_sprite: Sprite2D = $VesselPreview/LegsSprite
@onready var options_row: HBoxContainer = $OptionsRow
@onready var choice_heart: TextureRect = $ChoiceHeart
@onready var menu_list: VBoxContainer = $MenuList
@onready var name_edit: LineEdit = $NameEdit
@onready var fade_rect: ColorRect = $FadeRect
@onready var music_player: AudioStreamPlayer = $MusicPlayer  # AudioStreamPlayer en bus "Music", crea este nodo en la escena
 
const DRONE_PATH := "res://ui/Boot/scenes/AUDIO_DRONE.wav"
const ANOTHER_HIM_PATH := "res://ui/Boot/scenes/ANOTHER HIM.mp3"
const MUSIC_CROSSFADE_TIME := 1.2

# ---------------------------------------------------------------------
# TEXTURAS DE LAS PARTES — reemplaza estas rutas por las tuyas
# ---------------------------------------------------------------------
const HEAD_TEXTURES := [
	"res://sprites/vessel/head_0.png",
	"res://sprites/vessel/head_1.png",
	"res://sprites/vessel/head_2.png",
	"res://sprites/vessel/head_3.png",
	"res://sprites/vessel/head_4.png",
]
const TORSO_TEXTURES := [
	"res://sprites/vessel/torso_0.png",
	"res://sprites/vessel/torso_1.png",
	"res://sprites/vessel/torso_2.png",
	"res://sprites/vessel/torso_3.png",
	"res://sprites/vessel/torso_4.png",
]
const LEGS_TEXTURES := [
	"res://sprites/vessel/legs_0.png",
	"res://sprites/vessel/legs_1.png",
]

const FOOD_OPTIONS := ["SWEET", "SOFT", "SOUR", "SALTY", "PAIN", "COLD"]
const COLOR_OPTIONS := ["RED", "ORANGE", "YELLOW", "GREEN", "BLUE", "PURPLE", "WHITE"]
 
# ---------------------------------------------------------------------
# ESTADO
# ---------------------------------------------------------------------
var _selected_head := 2   # el del medio, como en las imágenes de referencia (5 opciones, índice 2)
var _selected_torso := 2
var _selected_legs := 2
var _selected_food := 0
var _selected_color := 0
var _player_name := ""
 
var _typing := false
var _skip_typing := false
var _busy := false  # bloquea input mientras se reproduce una secuencia no interactiva
 
const TYPE_SPEED := 0.2
const PART_COUNT := 5
 
 
func _ready() -> void:
	# El Boot ya se encarga de decidir si cargar esta escena (FirstTime.tscn)
	# o Intro.tscn directamente, así que aquí no hace falta comprobar nada más.
	_hide_everything()
	_play_music_looped(DRONE_PATH)
 
	await _run_intro_sequence()
	await _run_creation_sequence()
	_finish_creation()
 
 
func _hide_everything() -> void:
	main_label.text = ""
	main_label.visible = false
	red_line.visible = false
	heart.visible = false
	water_bg.visible = false
	vessel_preview.visible = false
	options_row.visible = false
	choice_heart.visible = false
	menu_list.visible = false
	name_edit.visible = false
	fade_rect.color = Color(0, 0, 0, 0)
	background.color = Color.BLACK
 
 
# =======================================================================
# INTRO — "ARE YOU THERE?" hasta "WE MAY BEGIN."
# =======================================================================
func _run_intro_sequence() -> void:
	main_label.visible = true
 
	await _show_text("ARE YOU\nTHERE?")
	await get_tree().create_timer(1.0).timeout
	await _hide_text()
 
	await _show_text("ARE WE\nCONNECTED?")
	await get_tree().create_timer(1.0).timeout
	await _hide_text()
 
	# la línea roja crece desde el centro hacia los lados hasta el ancho del alma
	await _line_grow_to_heart_width()
	# el alma aparece en el centro
	await _show_heart()
	# la línea se contrae de los lados al centro hasta desaparecer
	await _line_shrink_to_zero()
 
	await _show_text("EXCELLENT.")
	await get_tree().create_timer(0.9).timeout
	await _hide_text()
 
	await _show_text("TRULY\nEXCELLENT.")
	await get_tree().create_timer(0.9).timeout
	await _hide_text()
 
	await _show_text("NOW.")
	await get_tree().create_timer(0.8).timeout
	await _hide_text()
 
	await _show_text("WE MAY\nBEGIN.")
	await get_tree().create_timer(1.2).timeout
	await _hide_text()
 
	# se repite el mismo efecto: la línea vuelve a aparecer y crecer
	await _line_grow_to_heart_width()
	# el alma desaparece
	await _hide_heart()
	# la línea se contrae y desaparece de la misma forma que antes
	await _line_shrink_to_zero()
 
	# corte a negro para pasar a la siguiente parte
	background.color = Color.BLACK
	await get_tree().create_timer(0.3).timeout
 
 
func _line_grow_to_heart_width() -> void:
	var target_width: float = max(heart.size.x, 40.0)
	var screen_center_x := size.x / 2.0
	
	# Restablece anclajes a FULL_RECT para poder controlar posiciones/tamaños sin interferencias de layouts
	red_line.set_anchors_preset(Control.PRESET_FULL_RECT)
	red_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	red_line.grow_vertical = Control.GROW_DIRECTION_BOTH

	red_line.visible = true
	red_line.color = Color(1, 0.15, 0.1)
	
	# Asegura que ocupe todo el alto vertical (0 a size.y)
	# e inicia con ancho 0 centrado horizontalmente
	red_line.position = Vector2(screen_center_x, 0.0)
	red_line.size = Vector2(0.0, size.y)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(red_line, "position:x", screen_center_x - target_width / 2.0, 0.5)
	tw.tween_property(red_line, "size:x", target_width, 0.5)
	await tw.finished
 
 
func _line_shrink_to_zero() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(red_line, "position:x", size.x / 2.0, 0.5)
	tw.tween_property(red_line, "size:x", 0.0, 0.5)
	await tw.finished
	red_line.visible = false
 
 
func _show_heart() -> void:
	heart.visible = true
	heart.modulate.a = 0.0
	AudioManager.play_sfx_ui(SfxId.AUDIO_APPEARANCE)
	var tw := create_tween()
	tw.tween_property(heart, "modulate:a", 1.0, 0.4)
	await tw.finished
	await get_tree().create_timer(0.4).timeout
 
 
func _hide_heart() -> void:
	AudioManager.play_sfx_ui(SfxId.AUDIO_APPEARANCE)
	var tw := create_tween()
	tw.tween_property(heart, "modulate:a", 0.0, 0.4)
	await tw.finished
	heart.visible = false
 
 
# =======================================================================
# CREACIÓN DEL VESSEL
# =======================================================================
func _run_creation_sequence() -> void:
	water_bg.visible = true
	main_label.visible = true
	_play_music_looped(ANOTHER_HIM_PATH)  # reemplaza al DRONE una vez aparece el fondo
 
	await _show_text("FIRST.")
	await get_tree().create_timer(0.9).timeout
	await _hide_text()
 
	await _show_text("YOU MUST\nCREATE A VESSEL.")
	await get_tree().create_timer(1.2).timeout
	await _hide_text()
 
	vessel_preview.visible = true
	options_row.visible = true
	choice_heart.visible = true
 
	_selected_head = await _select_part("SELECT THE HEAD\nTHAT YOU PREFER.", HEAD_TEXTURES, head_sprite)
	_selected_torso = await _select_part("SELECT THE TORSO\nTHAT YOU PREFER.", TORSO_TEXTURES, torso_sprite)
	_selected_legs = await _select_part("SELECT THE LEGS\nTHAT YOU PREFER.", LEGS_TEXTURES, legs_sprite)
 
	options_row.visible = false
	choice_heart.visible = false
 
	var accepted := await _confirm_accept()
	if not accepted:
		# como en Deltarune: si dice NO, vuelve a pedir que elija de nuevo
		await _run_creation_sequence()
		return
 
	_player_name = await _ask_name()
	_selected_food = await _select_from_list("WHAT IS ITS\nFAVORITE FOOD?", FOOD_OPTIONS)
	_selected_color = await _select_from_list("WHAT IS ITS\nFAVORITE COLOR?", COLOR_OPTIONS)
 
 
func _select_part(prompt: String, textures: Array, target_sprite: Sprite2D) -> int:
	main_label.text = prompt
	_ensure_options_row_size(textures.size())
	_populate_options_row(textures)
	var index := textures.size() / 2  # empieza centrado, como en las capturas de referencia
	_update_part_selection(target_sprite, textures, index)
	_position_choice_heart(index)
 
	while true:
		var input := await _wait_for_menu_input()
		match input:
			"left":
				if index > 0:
					index -= 1
					_update_part_selection(target_sprite, textures, index)
					_position_choice_heart(index)
				else:
					pass
			"right":
				if index < textures.size() - 1:
					index += 1
					_update_part_selection(target_sprite, textures, index)
					_position_choice_heart(index)
				else:
					pass
			"confirm":
				return index
	return index  # inalcanzable, satisface al analizador estático
 
 
func _ensure_options_row_size(count: int) -> void:
	# Ajusta la cantidad de TextureRect hijos de OptionsRow a la cantidad real de opciones
	var current := options_row.get_child_count()
	if current < count:
		for i in (count - current):
			var tr := TextureRect.new()
			tr.custom_minimum_size = Vector2(48, 48)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			options_row.add_child(tr)
	elif current > count:
		for i in (current - count):
			var child := options_row.get_child(options_row.get_child_count() - 1)
			child.queue_free()
			options_row.remove_child(child)
 
 
func _populate_options_row(textures: Array) -> void:
	for i in options_row.get_child_count():
		var child := options_row.get_child(i)
		if child is TextureRect and i < textures.size():
			child.texture = load(textures[i]) as Texture2D
 
 
func _update_part_selection(target_sprite: Sprite2D, textures: Array, index: int) -> void:
	target_sprite.texture = load(textures[index]) as Texture2D
	for i in options_row.get_child_count():
		var child := options_row.get_child(i)
		if child is Control:
			child.modulate = Color(1, 1, 1, 1) if i == index else Color(0.5, 0.5, 0.5, 0.7)
 
 
func _position_choice_heart(index: int) -> void:
	if index >= options_row.get_child_count():
		return
	var target: Control = options_row.get_child(index)
	var target_pos := target.global_position + Vector2(target.size.x / 2.0 - choice_heart.size.x / 2.0, -choice_heart.size.y - 6)
	var tw := create_tween()
	tw.tween_property(choice_heart, "global_position", target_pos, 0.12)
 
 
func _confirm_accept() -> bool:
	main_label.text = "DO YOU\nACCEPT IT?"
	menu_list.visible = true
	_build_menu_list(["YES", "NO"])
	var idx := await _run_vertical_menu(2)
	menu_list.visible = false
	return idx == 0
 
 
func _select_from_list(prompt: String, options: Array) -> int:
	main_label.text = prompt
	menu_list.visible = true
	_build_menu_list(options)
	var idx := await _run_vertical_menu(options.size())
	menu_list.visible = false
	return idx
 
 
func _ask_name() -> String:
	main_label.text = "WHAT IS\nITS NAME?"
	name_edit.visible = true
	name_edit.text = ""
	name_edit.grab_focus()
 
	while true:
		var typed: String = await name_edit.text_submitted
		var final_name := typed.strip_edges()
		if final_name == "":
			name_edit.text = ""
			continue
		name_edit.visible = false
		return final_name
	return "VESSEL"  # inalcanzable, satisface al analizador estático
 
 
# =======================================================================
# HELPERS DE MENÚ VERTICAL (YES/NO, comida, color)
# =======================================================================
func _build_menu_list(options: Array) -> void:
	for c in menu_list.get_children():
		c.queue_free()
	for opt in options:
		var lbl := Label.new()
		lbl.text = str(opt)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		menu_list.add_child(lbl)
 
 
func _run_vertical_menu(count: int) -> int:
	var index := 0
	_highlight_menu_index(index)
	while true:
		var input := await _wait_for_menu_input()
		match input:
			"up":
				if index > 0:
					index -= 1
					_highlight_menu_index(index)
				else:
					pass
			"down":
				if index < count - 1:
					index += 1
					_highlight_menu_index(index)
				else:
					pass
			"confirm":
				return index
	return index  # inalcanzable, satisface al analizador estático
 
 
func _highlight_menu_index(index: int) -> void:
	for i in menu_list.get_child_count():
		var lbl := menu_list.get_child(i) as Label
		if not lbl:
			continue
		if i == index:
			lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
			lbl.text = "♥ " + lbl.text.trim_prefix("♥ ")
		else:
			lbl.add_theme_color_override("font_color", Color.WHITE)
			lbl.text = lbl.text.trim_prefix("♥ ")
 
 
# =======================================================================
# INPUT GENÉRICO (reemplaza esto por tu sistema de Input Actions si ya tienes uno)
# =======================================================================
func _wait_for_menu_input() -> String:
	while true:
		await get_tree().process_frame
		if Input.is_action_just_pressed("ui_left"):
			return "left"
		if Input.is_action_just_pressed("ui_right"):
			return "right"
		if Input.is_action_just_pressed("ui_up"):
			return "up"
		if Input.is_action_just_pressed("ui_down"):
			return "down"
		if Input.is_action_just_pressed("ui_accept"):
			return "confirm"
	return ""  # inalcanzable, satisface al analizador estático
 
 
# =======================================================================
# TEXTO ESTILO TYPEWRITER (con corazón parpadeante, como en las capturas)
# =======================================================================
func _show_text(full_text: String) -> void:
	_typing = true
	_skip_typing = false
	main_label.text = ""
 
	for i in full_text.length():
		if _skip_typing:
			main_label.text = full_text
			break
		main_label.text += full_text[i]
		await get_tree().create_timer(TYPE_SPEED).timeout
 
	_typing = false
 
 
func _hide_text() -> void:
	var tw := create_tween()
	tw.tween_property(main_label, "modulate:a", 0.0, 0.3)
	await tw.finished
	main_label.text = ""
	main_label.modulate.a = 1.0
 
 
func _unhandled_input(event: InputEvent) -> void:
	if _typing and event.is_action_pressed("ui_accept"):
		_skip_typing = true
 
 
# =======================================================================
# MÚSICA (DRONE al inicio, ANOTHER HIM cuando aparece el fondo — ambos en loop,
# uno reemplaza al otro con crossfade, no suenan mezclados)
# =======================================================================
var _current_music_path := ""
 
func _play_music_looped(path: String) -> void:
	if _current_music_path == path:
		return
	if not ResourceLoader.exists(path):
		push_warning("[VesselCreation] No se encontró música: " + path)
		return
	_current_music_path = path
 
	var stream := load(path) as AudioStream
	if stream and "loop" in stream:
		stream.loop = true
 
	if music_player.playing:
		var fade_out := create_tween()
		fade_out.tween_property(music_player, "volume_db", -80.0, MUSIC_CROSSFADE_TIME)
		await fade_out.finished
		music_player.stop()
 
	music_player.stream = stream
	music_player.volume_db = -80.0
	music_player.play()
	var fade_in := create_tween()
	fade_in.tween_property(music_player, "volume_db", 0.0, MUSIC_CROSSFADE_TIME)
 
 
# =======================================================================
# GUARDADO FINAL
# =======================================================================
func _finish_creation() -> void:
	var vessel_data := {
		"head": _selected_head,
		"torso": _selected_torso,
		"legs": _selected_legs,
		"food": FOOD_OPTIONS[_selected_food],
		"color": COLOR_OPTIONS[_selected_color],
	}
 
	SettingsManager.complete_goner_creation(_player_name, vessel_data, COLOR_OPTIONS[_selected_color])
 
	# fundido a negro y cierre de la escena
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, 1.0)
	tw.parallel().tween_property(music_player, "volume_db", -80.0, 1.0)
	await tw.finished
 
	get_tree().change_scene_to_file.call_deferred("res://ui/Boot/scenes/Intro.tscn")
 
