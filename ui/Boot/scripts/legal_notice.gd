extends Control

@export_multiline var notice_text: String = "AVISO LEGAL\n\nDarker Than Darkness es un juego no oficial creado por fans. No está afiliado a ningún estudio ni empresa.\nAl continuar aceptas las reglas del juego y entiendes que el contenido puede cambiar durante el desarrollo.\n\nEste aviso se muestra en cada apertura."

@onready var text_label: Label = $Panel/VBox/TextLabel
@onready var accept_btn: Button = $Panel/VBox/Buttons/AcceptBtn
@onready var quit_btn: Button = $Panel/VBox/Buttons/QuitBtn


func _ready() -> void:
	text_label.text = notice_text
	accept_btn.grab_focus()


func _on_accept_pressed() -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")


func _on_quit_pressed() -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	get_tree().quit()
