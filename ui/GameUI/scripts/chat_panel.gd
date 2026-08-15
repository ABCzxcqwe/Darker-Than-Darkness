# ui/GameUI/scripts/chat_panel.gd
# Panel de chat superpuesto en el HUD, arriba a la izquierda.
extends Control

@onready var history_label: RichTextLabel = $VBoxContainer/HistoryLabel
@onready var input_box: LineEdit = $VBoxContainer/InputBox
@onready var separator: ColorRect = $VBoxContainer/Separator
@onready var background: Panel = $Background

const MAX_MESSAGES := 100
const FONT_SIZE := 14
const FONT_PATH := "res://Fonts/deltarune font.ttf"

var _input_active := false
var _messages: Array[String] = []


func _ready() -> void:
	var font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	if font:
		history_label.add_theme_font_override("normal_font", font)
		history_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
		input_box.add_theme_font_override("font", font)
		input_box.add_theme_font_size_override("font_size", FONT_SIZE)

	input_box.visible = false
	separator.visible = false
	input_box.placeholder_text = "Escribe un mensaje..."
	history_label.meta_underlined = false

	input_box.focus_exited.connect(_close_input)
	input_box.text_submitted.connect(_on_text_submitted)

	if ChatService.has_signal("chat_message_received"):
		ChatService.chat_message_received.connect(_on_chat_message)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	if _is_pause_open():
		return

	if not _input_active and event.keycode == KEY_T:
		get_viewport().set_input_as_handled()
		_open_input()


func _is_pause_open() -> bool:
	var menu := get_tree().get_first_node_in_group(GroupNames.GAME_MENU)
	return menu != null and menu.has_method("is_open") and menu.is_open()


func _unhandled_input(event: InputEvent) -> void:
	if not _input_active:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return

	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close_input()


func _on_text_submitted(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		_close_input()
		return
	ChatService.send_message(text)
	_close_input()


func _open_input() -> void:
	_input_active = true
	input_box.visible = true
	separator.visible = true
	input_box.grab_focus()
	history_label.custom_minimum_size.y = 85
	_set_player_movement(false)


func _close_input() -> void:
	_input_active = false
	input_box.text = ""
	input_box.visible = false
	separator.visible = false
	input_box.release_focus()
	history_label.custom_minimum_size.y = 180
	_set_player_movement(true)


func _set_player_movement(enabled: bool) -> void:
	var my_id = multiplayer.get_unique_id()
	var player = PlayerRegistry.get_player(my_id)
	if not player or not is_instance_valid(player):
		return
	var mov = player.get_node_or_null("PlayerMovementComponent")
	if not mov:
		return
	mov.set_physics_process(enabled)
	player.set_process_input(enabled)
	if not enabled:
		player.velocity = Vector2.ZERO


func _on_chat_message(sender_id: int, sender_name: String, message: String) -> void:
	var color = _get_player_color(sender_id)
	var formatted = "[color=#%s][b]%s:[/b][/color] %s" % [color.to_html(false), sender_name, message]
	_messages.append(formatted)

	if _messages.size() > MAX_MESSAGES:
		_messages.pop_front()

	history_label.text = "\n".join(_messages)
	history_label.scroll_to_line(history_label.get_line_count() - 1)


func _get_player_color(peer_id: int) -> Color:
	var char_id = LobbyManager.players.get(peer_id, {}).get("character_id", -1)
	if char_id >= 0:
		var character = CharacterRegistry.get_character(char_id)
		if character:
			match character.display_name.to_lower():
				"ralsei": return Color(0.0, 0.8, 0.4)
				"jevil":  return Color(0.6, 0.3, 1.0)
				"kris":   return Color(0.3, 0.6, 1.0)
				"susie":  return Color(1.0, 0.3, 0.6)
	return Color(0.7, 0.8, 1.0)
