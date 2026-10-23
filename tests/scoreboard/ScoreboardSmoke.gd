# res://tests/scoreboard/ScoreboardSmoke.gd
# Smoke test del scoreboard de identidad: filas por jugador, icono + nombre
# y marcador del jugador local. No debe mostrar estado ni rol.
extends Node


func _ready() -> void:
	await get_tree().process_frame

	if not InputMap.has_action("scoreboard"):
		push_error("[ScoreboardSmoke] Falta la acción 'scoreboard' en el InputMap")
		get_tree().quit(1)
		return

	var scene: PackedScene = load("res://ui/GameUI/Scenes/Scoreboard.tscn")
	if scene == null:
		push_error("[ScoreboardSmoke] No se pudo cargar Scoreboard.tscn")
		get_tree().quit(1)
		return

	var scoreboard := scene.instantiate()
	add_child(scoreboard)
	await get_tree().process_frame

	LobbyManager.players = {
		1: {"name": "Host", "character_id": 1, "assigned_role": "killer", "is_spectator": false},
		2: {"name": "Amigo", "character_id": 2, "assigned_role": "survivor", "is_spectator": false},
		3: {"name": "Spec", "character_id": -1, "assigned_role": "survivor", "is_spectator": true},
	}

	scoreboard._refresh()
	await get_tree().process_frame

	var rows: VBoxContainer = scoreboard.get_node("Root/Center/Panel/Margin/VBox/Rows")
	if rows.get_child_count() != 3:
		push_error("[ScoreboardSmoke] Se esperaban 3 filas, hay %d" % rows.get_child_count())
		get_tree().quit(1)
		return

	var found_names := {}
	var found_local_tag := false
	for row in rows.get_children():
		for child in row.get_children():
			if child is Label:
				found_names[child.text] = true
				if child.text == "TÚ":
					found_local_tag = true

	for expected in ["Host", "Amigo", "Spec"]:
		if not found_names.has(expected):
			push_error("[ScoreboardSmoke] Falta el nombre '%s'" % expected)
			get_tree().quit(1)
			return

	if not found_local_tag:
		push_error("[ScoreboardSmoke] No se encontró el marcador TÚ del jugador local")
		get_tree().quit(1)
		return

	# Simular mantener/soltar Tab.
	var press := InputEventAction.new()
	press.action = "scoreboard"
	press.pressed = true
	scoreboard._input(press)
	if not scoreboard.visible:
		push_error("[ScoreboardSmoke] Tab no mostró el scoreboard")
		get_tree().quit(1)
		return

	var release := InputEventAction.new()
	release.action = "scoreboard"
	release.pressed = false
	scoreboard._input(release)
	if scoreboard.visible:
		push_error("[ScoreboardSmoke] Soltar Tab no ocultó el scoreboard")
		get_tree().quit(1)
		return

	print("[ScoreboardSmoke] OK: 3 filas, nombres, marcador local y hold de Tab")
	get_tree().quit(0)
