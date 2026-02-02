extends Control

@onready var music_button = $MusicButton
@onready var sfx_button = $SFXButton

func _ready():
	music_button.button_pressed = AudioManager.is_music_enabled()
	sfx_button.button_pressed = AudioManager.is_sfx_enabled()

func _on_music_button_toggled(is_on: bool):
	AudioManager.toggle_music(is_on)

func _on_sfx_button_toggled(is_on: bool):
	AudioManager.toggle_sfx(is_on)
	
func _on_button_play_pressed():
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_button_exit_pressed():
	get_tree().quit()
