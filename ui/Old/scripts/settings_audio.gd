extends "res://ui/Old/scripts/settings_section.gd"
## Sub-sección Audio: Música y SFX.
## Escena propia: ui/MainMenu/scenes/SettingsAudio.tscn

@onready var music_slider: HSlider = $VBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $VBox/SfxRow/SfxSlider
@onready var back_btn: Button = $VBox/BackButton


func _ready() -> void:
	music_slider.value = SettingsManager.music_volume
	music_slider.value_changed.connect(func(v): SettingsManager.music_volume = v)

	sfx_slider.value = SettingsManager.sfx_volume
	sfx_slider.value_changed.connect(func(v): SettingsManager.sfx_volume = v)

	back_btn.pressed.connect(_go_back)

	_setup_focus([music_slider, sfx_slider, back_btn])