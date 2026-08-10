extends Control


func _on_main_menu_pressed() -> void:
	change_scene("res://scenes/main_menu.tscn")


func _on_quit_game_pressed() -> void:
	get_tree().quit()
	

func change_scene(Scene: String):
	get_tree().change_scene_to_file(Scene)


func _on_resume_button_pressed() -> void:
	var root = (get_parent()).get_parent()
	root.get_tree().paused = not root.get_tree().paused
	self.visible = false
