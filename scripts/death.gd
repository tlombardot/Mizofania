extends Control

func _on_button_jouer_pressed():
	# Charge la scène de jeu
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_button_quitter_pressed():
	# Ferme le jeu
	get_tree().quit()
