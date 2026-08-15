extends "res://ui/MainMenu/scripts/settings_section.gd"
## Sub-sección Video: pantalla, VHS y niebla.
## Escena propia: ui/MainMenu/scenes/SettingsVideo.tscn

@onready var display_option: OptionButton = $VBox/DisplayRow/DisplayOption
@onready var vhs_check: CheckBox = $VBox/VhsRow/VhsCheck
@onready var fog_check: CheckBox = $VBox/FogRow/FogCheck
@onready var back_btn: Button = $VBox/BackButton


func _ready() -> void:
	display_option.selected = 0 if SettingsManager.display_mode == 0 else 1
	display_option.item_selected.connect(func(i): SettingsManager.display_mode = display_option.get_item_id(i))

	vhs_check.button_pressed = SettingsManager.vhs_enabled
	vhs_check.toggled.connect(func(b): SettingsManager.vhs_enabled = b)

	fog_check.button_pressed = SettingsManager.fog_enabled
	fog_check.toggled.connect(func(b): SettingsManager.fog_enabled = b)

	back_btn.pressed.connect(_go_back)

	_setup_focus([display_option, vhs_check, fog_check, back_btn])