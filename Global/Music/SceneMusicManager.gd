extends Node

# SceneMusicManager decides which music should play for each scene.
# MusicPlayer still handles the actual audio playback.

@export_group("Default Behaviour")
@export var default_fade_out_duration: float = 0.35
@export var default_fade_in_duration: float = 0.75
@export var stop_music_when_scene_has_no_music: bool = false

@export_group("Scene Rules")
# These scenes keep whatever music is already playing.
@export var scenes_that_keep_current_music: Array[String] = [
	"settings",
]

# These scenes always stop the music.
@export var scenes_that_stop_music: Array[String] = []

# Add scene music here.
# Keys can be scene keys, like "main_menu",
# or direct scene paths, like "res://Scenes/Main/main.tscn".
# Values can be AudioStreams or resource paths.
#MAKE SURE THEY ARE MP3s!
@export var scene_music: Dictionary = {
	"main_menu": preload("res://Assets/Audio/OST/To No Avail.mp3"),
	"main": preload("res://Assets/Audio/OST/Sous Les Donkehs (1).mp3"),
	"credits": preload("res://Assets/Audio/OST/something3.mp3"),
}

# Music that should start after the new scene has loaded.
var prepared_music: AudioStream = null


# Checks what music the next scene needs.
# Usually called before the scene transition.
func prepare_scene_music(scene_key: String, scene_path: String = "") -> void:
	prepared_music = null

	if _scene_is_in_list(scenes_that_stop_music, scene_key, scene_path):
		stop_music()
		return

	if _scene_is_in_list(scenes_that_keep_current_music, scene_key, scene_path):
		return

	var target_music: AudioStream = get_music_for_scene(scene_key, scene_path)

	if target_music == null:
		if stop_music_when_scene_has_no_music:
			stop_music()

		return

	if MusicPlayer.is_playing(target_music):
		return

	prepared_music = target_music
	stop_music()


# Plays the music prepared by prepare_scene_music().
# Usually called after the new scene has loaded.
func play_prepared_scene_music() -> void:
	if prepared_music == null:
		return

	if MusicPlayer.is_playing(prepared_music):
		prepared_music = null
		return

	MusicPlayer.play(prepared_music, true, false, default_fade_in_duration, true)

	prepared_music = null


# Immediately applies music for a scene.
# Useful if you do not need a separate prepare/play step.
func apply_scene_music(scene_key: String, scene_path: String = "") -> void:
	prepare_scene_music(scene_key, scene_path)
	play_prepared_scene_music()


# Gets the AudioStream assigned to a scene.
func get_music_for_scene(scene_key: String, scene_path: String = "") -> AudioStream:
	var music_value: Variant = null

	if not scene_key.is_empty() and scene_music.has(scene_key):
		music_value = scene_music[scene_key]
	elif not scene_path.is_empty() and scene_music.has(scene_path):
		music_value = scene_music[scene_path]
	else:
		return null

	if music_value is AudioStream:
		return music_value as AudioStream

	if music_value is String:
		var loaded_resource: Resource = load(music_value)

		if loaded_resource is AudioStream:
			return loaded_resource as AudioStream

		push_error("Scene music path is not an AudioStream: %s" % music_value)
		return null

	push_error("Scene music value must be an AudioStream or resource path.")
	return null


# Stops the current music with the default fade-out.
func stop_music() -> void:
	MusicPlayer.stop(true, default_fade_out_duration)


# Checks if a scene key or scene path is in a rule list.
func _scene_is_in_list(scene_list: Array[String], scene_key: String, scene_path: String) -> bool:
	if not scene_key.is_empty() and scene_key in scene_list:
		return true

	if not scene_path.is_empty() and scene_path in scene_list:
		return true

	return false
