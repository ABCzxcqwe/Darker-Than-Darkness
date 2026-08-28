extends CanvasLayer

func _on_exit_button_pressed():
	if not is_inside_tree():
		return
	MatchCoordinator.reset_to_menu()
