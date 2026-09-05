extends "res://ui/Old/scripts/menu_base.gd"
## Hub de Opciones: navega a las sub-secciones Audio/Video/Red/Controles.
## Cada sub-sección es una escena propia que ocupa toda la pantalla
## (change_scene_to_file), sin superponerse con el hub.

const SECTION_AUDIO := "res://ui/Old/scenes/SettingsAudio.tscn"
const SECTION_VIDEO := "res://ui/Old/scenes/SettingsVideo.tscn"
const SECTION_NETWORK := "res://ui/Old/scenes/SettingsNetwork.tscn"
const SECTION_CONTROLS := "res://ui/Old/scenes/SettingsControls.tscn"

@onready var audio_btn: Button = $VBox/AudioButton
@onready var video_btn: Button = $VBox/VideoButton
@onready var network_btn: Button = $VBox/NetworkButton
@onready var controls_btn: Button = $VBox/ControlsButton
@onready var back_btn: Button = $VBox/BackButton


func _ready() -> void:
	audio_btn.pressed.connect(_on_audio_pressed)
	video_btn.pressed.connect(_on_video_pressed)
	network_btn.pressed.connect(_on_network_pressed)
	controls_btn.pressed.connect(_on_controls_pressed)
	back_btn.pressed.connect(_on_back_pressed)

	_setup_focus([audio_btn, video_btn, network_btn, controls_btn, back_btn])


func _on_audio_pressed() -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	_go_back_to(SECTION_AUDIO)


func _on_video_pressed() -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	_go_back_to(SECTION_VIDEO)


func _on_network_pressed() -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	_go_back_to(SECTION_NETWORK)


func _on_controls_pressed() -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	_go_back_to(SECTION_CONTROLS)


func _on_back_pressed() -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	get_tree().change_scene_to_file("res://ui/Old/scenes/MainMenu.tscn")


func _on_menu_cancel() -> bool:
	_on_back_pressed()
	return true