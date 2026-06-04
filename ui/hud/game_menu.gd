extends Control

const FONT := preload("res://Fonts/deltarune font.ttf")
const ICON := preload("res://sprites/menu.png")

const BUS_MASTER := 0
const BUS_SFX := 2

var _is_open := false

var menu_button: TextureButton
var overlay: ColorRect
var menu_panel: Panel
var master_slider: HSlider
var sfx_slider: HSlider
var exit_button: Button

func _ready() -> void:
	_build_ui()
	menu_button.pressed.connect(_toggle)
	overlay.gui_input.connect(_on_overlay_clicked)
	exit_button.pressed.connect(_on_exit_pressed)
	master_slider.value_changed.connect(_on_master_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	_close()

func _build_ui() -> void:
	var panel_bg := StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	panel_bg.set_corner_radius_all(8)
	var exit_style := StyleBoxFlat.new()
	exit_style.bg_color = Color(0.55, 0.1, 0.1, 1.0)
	exit_style.set_corner_radius_all(4)
	var exit_hover := StyleBoxFlat.new()
	exit_hover.bg_color = Color(0.7, 0.15, 0.15, 1.0)
	exit_hover.set_corner_radius_all(4)

	menu_button = TextureButton.new()
	menu_button.name = "MenuButton"
	menu_button.texture_normal = ICON
	menu_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	menu_button.custom_minimum_size = Vector2(48, 48)
	menu_button.position = Vector2(10, 10)
	add_child(menu_button)

	var esc_label := Label.new()
	esc_label.name = "ESCLabel"
	esc_label.text = "ESC"
	esc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	esc_label.add_theme_font_size_override("font_size", 10)
	esc_label.mouse_filter = MOUSE_FILTER_IGNORE
	esc_label.position = Vector2(8, 58)
	esc_label.size = Vector2(52, 14)
	add_child(esc_label)

	overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.mouse_filter = MOUSE_FILTER_STOP
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	add_child(overlay)

	menu_panel = Panel.new()
	menu_panel.name = "Panel"
	menu_panel.add_theme_stylebox_override("panel", panel_bg)
	menu_panel.mouse_filter = MOUSE_FILTER_STOP
	menu_panel.set_anchors_preset(PRESET_CENTER)
	menu_panel.set_offset(SIDE_LEFT, -200)
	menu_panel.set_offset(SIDE_RIGHT, 200)
	menu_panel.set_offset(SIDE_TOP, -150)
	menu_panel.set_offset(SIDE_BOTTOM, 150)
	add_child(menu_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	menu_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = "MENÚ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	master_slider = _make_row(vbox, "Master", "VOLUMEN", FONT)
	sfx_slider = _make_row(vbox, "SFX", "SFX", FONT)

	vbox.add_spacer(true)

	exit_button = Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = "SALIR DEL JUEGO"
	exit_button.add_theme_font_override("font", FONT)
	exit_button.add_theme_font_size_override("font_size", 22)
	exit_button.add_theme_stylebox_override("normal", exit_style)
	exit_button.add_theme_stylebox_override("hover", exit_hover)
	exit_button.custom_minimum_size = Vector2(0, 44)
	vbox.add_child(exit_button)

func _make_row(parent: VBoxContainer, row_name: String, label_text: String, font: Font) -> HSlider:
	var row := HBoxContainer.new()
	row.name = row_name + "Row"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)

	var label := Label.new()
	label.name = row_name + "Label"
	label.text = label_text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 22)
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.name = row_name + "Slider"
	slider.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 1.0
	row.add_child(slider)

	return slider

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	if _is_open:
		_close()
	else:
		_open()

func _open() -> void:
	_is_open = true
	overlay.visible = true
	menu_panel.visible = true
	master_slider.value = db_to_linear(AudioServer.get_bus_volume_db(BUS_MASTER))
	sfx_slider.value = db_to_linear(AudioServer.get_bus_volume_db(BUS_SFX))

func _close() -> void:
	_is_open = false
	overlay.visible = false
	menu_panel.visible = false

func _on_master_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(BUS_MASTER, linear_to_db(value))

func _on_sfx_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(BUS_SFX, linear_to_db(value))

func _on_overlay_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_close()

func _on_exit_pressed() -> void:
	MatchCoordinator.reset_to_menu()
