extends Control

@onready var music_slider: HSlider = $VBoxContainer/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $VBoxContainer/SFXRow/SFXSlider
@onready var network_option: OptionButton = $VBoxContainer/NetworkRow/NetworkOption
@onready var display_option: OptionButton = $VBoxContainer/DisplayRow/DisplayOption
@onready var vhs_check: CheckBox = $VBoxContainer/VHSRow/VHSCheckBox
@onready var fog_check: CheckBox = $VBoxContainer/FogRow/FogCheckBox
@onready var back_btn: Button = $VBoxContainer/BackButton

var _focus_items: Array[Control] = []
var _focus_idx := 0

func _ready() -> void:
	_load_from_settings()
	_setup_signals()
	_setup_focus()

func _load_from_settings() -> void:
	music_slider.value = SettingsManager.music_volume
	sfx_slider.value = SettingsManager.sfx_volume
	network_option.selected = SettingsManager.network_mode
	display_option.selected = 0 if SettingsManager.display_mode == 0 else 1
	vhs_check.button_pressed = SettingsManager.vhs_enabled
	fog_check.button_pressed = SettingsManager.fog_enabled

func _setup_signals() -> void:
	music_slider.value_changed.connect(func(v): SettingsManager.music_volume = v)
	sfx_slider.value_changed.connect(func(v): SettingsManager.sfx_volume = v)
	network_option.item_selected.connect(func(i): SettingsManager.network_mode = i)
	display_option.item_selected.connect(func(i):
		SettingsManager.display_mode = display_option.get_item_id(i)
	)
	vhs_check.toggled.connect(func(b): SettingsManager.vhs_enabled = b)
	fog_check.toggled.connect(func(b): SettingsManager.fog_enabled = b)

func _setup_focus() -> void:
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color(0.114, 0.114, 0.114, 1)
	focus_style.border_color = Color.WHITE
	focus_style.border_width_left = 3
	focus_style.border_width_top = 3
	focus_style.border_width_right = 3
	focus_style.border_width_bottom = 3
	focus_style.set_corner_radius_all(3)
	focus_style.set_expand_margin_all(5)
	_focus_items = [music_slider, sfx_slider, network_option, display_option, vhs_check, fog_check, back_btn]
	for i in _focus_items.size():
		_focus_items[i].add_theme_stylebox_override("focus", focus_style)
		_focus_items[i].focus_entered.connect(_update_focus.bind(i))
	music_slider.grab_focus()
	_focus_idx = 0

func _update_focus(i: int) -> void:
	_focus_idx = i

func _input(event):
	if event is InputEventKey and event.pressed and not event.is_echo():
		var kc = event.keycode
		var pkc = event.physical_keycode
		if kc != KEY_W and kc != KEY_S and pkc != KEY_W and pkc != KEY_S:
			return
		if (kc == KEY_W or pkc == KEY_W) and _focus_idx > 0:
			_focus_idx -= 1
			_focus_items[_focus_idx].grab_focus()
			AudioManager.play_sfx_ui(SfxId.MENU_MOVE)
			get_viewport().set_input_as_handled()
		elif (kc == KEY_S or pkc == KEY_S) and _focus_idx < _focus_items.size() - 1:
			_focus_idx += 1
			_focus_items[_focus_idx].grab_focus()
			AudioManager.play_sfx_ui(SfxId.MENU_MOVE)
			get_viewport().set_input_as_handled()

func _on_back_pressed() -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	SettingsManager.save_settings()
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")
