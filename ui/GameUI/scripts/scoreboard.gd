# res://ui/GameUI/scripts/scoreboard.gd
# Scoreboard de identidad: icono + nombre de todos los conectados.
# No muestra rol, vida ni estado. Se mantiene Tab para verlo.
extends CanvasLayer

const FONT := preload("res://Fonts/deltarune font.ttf")
const FALLBACK_ICON := preload("res://sprites/Soul.png")
const ROW_ICON_SIZE := Vector2(40, 40)

@onready var title_label: Label = $Root/Center/Panel/Margin/VBox/Title
@onready var rows: VBoxContainer = $Root/Center/Panel/Margin/VBox/Rows


func _ready() -> void:
	visible = false
	if title_label:
		title_label.text = _tr_or("SCOREBOARD_TITLE", "JUGADORES")
	if not LobbyManager.lobby_updated.is_connected(_on_lobby_updated):
		LobbyManager.lobby_updated.connect(_on_lobby_updated)


func _tr_or(key: String, fallback: String) -> String:
	var value := tr(key)
	return value if value != key else fallback


func _on_lobby_updated() -> void:
	if visible:
		_refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("scoreboard"):
		if not _can_show():
			return
		_refresh()
		visible = true
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()
	elif event.is_action_released("scoreboard"):
		if visible:
			visible = false
			var vp := get_viewport()
			if vp:
				vp.set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		visible = false


func _process(_delta: float) -> void:
	if visible and not _can_show():
		visible = false


func _can_show() -> bool:
	if MenuUtils.is_any_menu_open(get_tree()):
		return false
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit:
		return false
	return true


func _refresh() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()

	var players: Array = LobbyManager.get_player_list()
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)

	if players.is_empty():
		var empty := Label.new()
		empty.text = _tr_or("SCOREBOARD_EMPTY", "SIN JUGADORES")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_override("font", FONT)
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5, 1))
		rows.add_child(empty)
		return

	var my_id := 1
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		my_id = multiplayer.get_unique_id()
	for p in players:
		rows.add_child(_make_row(p, my_id))


func _make_row(p: Dictionary, my_id: int) -> HBoxContainer:
	var peer_id := int(p.get("id", -1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, ROW_ICON_SIZE.y + 8)

	var icon := TextureRect.new()
	icon.custom_minimum_size = ROW_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _get_icon(p)
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = str(p.get("name", "Jugador %d" % peer_id))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_override("font", FONT)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(0.85, 1, 0.85, 1))
	row.add_child(name_label)

	if peer_id == my_id:
		var tag := Label.new()
		tag.text = _tr_or("SCOREBOARD_YOU", "TÚ")
		tag.add_theme_font_override("font", FONT)
		tag.add_theme_font_size_override("font_size", 14)
		tag.add_theme_color_override("font_color", Color(0.4, 1, 0.4, 1))
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(tag)

	return row


func _get_icon(p: Dictionary) -> Texture2D:
	var char_id := int(p.get("character_id", -1))
	if char_id > 0 and CharacterRegistry.has_character(char_id):
		var data: CharacterData = CharacterRegistry.get_character(char_id)
		if data:
			if data.icon:
				return data.icon
			if data.panel_texture:
				return data.panel_texture
	return FALLBACK_ICON
