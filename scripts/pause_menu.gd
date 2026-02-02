extends CanvasLayer

@onready var music_button = $MenuRoot/MusicButton
@onready var sfx_button = $MenuRoot/SFXButton

func _ready():
	visible = false
	_initialize_button_states()

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if get_tree().paused:
			_on_resume_button_pressed()
		else:
			pause()

func pause():
	visible = true
	get_tree().paused = true
	_initialize_button_states()

func _on_resume_button_pressed():
	visible = false
	get_tree().paused = false

func _on_exit_button_pressed():
	get_tree().paused = false
	get_tree().quit()

func _on_music_button_toggled(is_on: bool):
	var bus_idx = AudioServer.get_bus_index("Music")
	if bus_idx != -1:
		AudioServer.set_bus_mute(bus_idx, not is_on)

func _on_sfx_button_toggled(is_on: bool):
	var bus_idx = AudioServer.get_bus_index("SFX")
	if bus_idx != -1:
		AudioServer.set_bus_mute(bus_idx, not is_on)

func _initialize_button_states():
	var music_idx = AudioServer.get_bus_index("Music")
	var sfx_idx = AudioServer.get_bus_index("SFX")
	
	if music_idx != -1:
		music_button.button_pressed = not AudioServer.is_bus_mute(music_idx)
	if sfx_idx != -1:
		sfx_button.button_pressed = not AudioServer.is_bus_mute(sfx_idx)
