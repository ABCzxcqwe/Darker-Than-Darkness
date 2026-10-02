extends Control

@export_multiline var notice_text: String = "AVISO LEGAL\n\nDarker Than Darkness es un juego no oficial creado por fans. No está afiliado a ningún estudio ni empresa.\nAl continuar aceptas las reglas del juego y entiendes que el contenido puede cambiar durante el desarrollo.\n\nEste aviso se muestra en cada apertura."

@onready var text_label: Label = $Panel/VBox/TextLabel
@onready var accept_btn: Button = $Panel/VBox/Buttons/AcceptBtn
@onready var quit_btn: Button = $Panel/VBox/Buttons/QuitBtn


func _ready() -> void:
	_refresh_texts()
	accept_btn.grab_focus()
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and sm.has_signal("setting_changed") and not sm.setting_changed.is_connected(_on_setting_changed):
		sm.setting_changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and sm.has_signal("setting_changed") and sm.setting_changed.is_connected(_on_setting_changed):
		sm.setting_changed.disconnect(_on_setting_changed)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "language":
		_refresh_texts()


func _refresh_texts() -> void:
	var body := tr("LEGAL_BODY")
	if body == "" or body == "LEGAL_BODY":
		text_label.text = notice_text
	else:
		text_label.text = tr("LEGAL_TITLE") + "\n\n" + body
	var accept_t := tr("LEGAL_ACCEPT")
	accept_btn.text = accept_t if accept_t != "" and accept_t != "LEGAL_ACCEPT" else "Aceptar"
	var quit_t := tr("LEGAL_QUIT")
	quit_btn.text = quit_t if quit_t != "" and quit_t != "LEGAL_QUIT" else "Salir"


func _on_accept_pressed() -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	get_tree().change_scene_to_file("res://ui/MainMenu/scenes/MainMenu.tscn")


func _on_quit_pressed() -> void:
	AudioManager.play_sfx_ui(SfxId.SELECT)
	get_tree().quit()
