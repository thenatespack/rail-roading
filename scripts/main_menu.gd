extends Control


func _on_start_button_pressed() -> void:
	change_scene("res://scenes/test.tscn")

func _on_tutorial_button_pressed() -> void:
	change_scene("res://scenes/tutorial.tscn")


func _on_settings_button_pressed() -> void:
	pass # Replace with function body.

func _on_quit_button_pressed() -> void:
	get_tree().quit(0)

func change_scene(Scene: String):
	get_tree().change_scene_to_file(Scene)
