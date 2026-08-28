extends "res://ui/Old/scripts/settings_section.gd"
## Sub-sección Red: modo LAN/Steam.
## Escena propia: ui/MainMenu/scenes/SettingsNetwork.tscn

var _has_steam := false

@onready var network_option: OptionButton = $VBox/NetworkRow/NetworkOption
@onready var back_btn: Button = $VBox/BackButton


func _ready() -> void:
	_has_steam = NetworkManager.is_steam_ready()

	if _has_steam:
		network_option.add_item("Steam", 1)
	var max_mode := 0 if not _has_steam else 1
	SettingsManager.network_mode = clampi(SettingsManager.network_mode, 0, max_mode)
	network_option.selected = SettingsManager.network_mode
	network_option.item_selected.connect(_on_network_selected)

	back_btn.pressed.connect(_go_back)

	_setup_focus([network_option, back_btn])


func _on_network_selected(i: int) -> void:
	SettingsManager.network_mode = i
	if _has_steam and SettingsManager.network_mode == 1:
		NetworkManager.initialize_steam()
	else:
		NetworkManager.set_lan_mode()