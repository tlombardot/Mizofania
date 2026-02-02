extends Node

var music_bus = "Music"
var sfx_bus = "SFX"

func toggle_music(is_on: bool):
	var bus_idx = AudioServer.get_bus_index(music_bus)
	if bus_idx != -1:
		AudioServer.set_bus_mute(bus_idx, not is_on)

func toggle_sfx(is_on: bool):
	var bus_idx = AudioServer.get_bus_index(sfx_bus)
	if bus_idx != -1:
		AudioServer.set_bus_mute(bus_idx, not is_on)

func is_music_enabled() -> bool:
	var bus_idx = AudioServer.get_bus_index(music_bus)
	return not AudioServer.is_bus_mute(bus_idx)

func is_sfx_enabled() -> bool:
	var bus_idx = AudioServer.get_bus_index(sfx_bus)
	return not AudioServer.is_bus_mute(bus_idx)
