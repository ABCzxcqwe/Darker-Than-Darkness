extends Node

func _ready() -> void:
	var scene: String = "res://ui/Boot/scenes/FirstTime.tscn" \
		if SettingsManager.is_first_launch() \
		else "res://ui/Boot/scenes/Intro.tscn"
	get_tree().change_scene_to_file.call_deferred(scene)
