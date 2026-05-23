extends CanvasLayer

func _on_exit_button_pressed():
	if not is_inside_tree():
		return
	# No debemos cambiar la escena aquí; será reset_to_menu quien lo haga
	MatchCoordinator.reset_to_menu()
