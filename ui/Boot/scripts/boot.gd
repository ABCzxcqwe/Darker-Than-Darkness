extends Node

func _ready() -> void:
	if SettingsManager.is_first_launch():
		get_tree().change_scene_to_file.call_deferred("res://ui/Boot/scenes/FirstTime.tscn")
	else:
		get_tree().change_scene_to_file.call_deferred("res://ui/Boot/scenes/Intro.tscn")

