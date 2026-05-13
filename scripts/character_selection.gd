extends Control

var selected: int = 0

func _ready():
	$Kris.pressed.connect(_select.bind(0))
	$Susie.pressed.connect(_select.bind(1))

func _select(id):
	selected = id
	print("Personaje ", id, " seleccionado")

func _on_continue():
	GameData.selected_character = selected
	print("CharacterSelection: guardando personaje ", selected, " en GameData")
	get_tree().change_scene_to_file("res://Main.tscn")
