extends Node

# GameData stores simple settings and progress and audio abd shit.

signal audio_settings_changed
signal display_settings_changed
signal current_level_changed(current_level_scene: String)
signal input_bindings_changed(input_bindings: Dictionary)
signal settings_saved
signal settings_loaded

const SAVE_PATH: String = "user://game_data.cfg"

# Default settings to prevent ear blasting.
# Never default your master to 100%. That's a rookie mistake.
const DEFAULT_MASTER_VOLUME: float = 0.70
const DEFAULT_MUSIC_VOLUME: float = 0.70
const DEFAULT_SFX_VOLUME: float = 0.70
const DEFAULT_FULLSCREEN: bool = false
const DEFAULT_CURRENT_LEVEL_SCENE: String = "main"

# Master volume is special.
# 0.70 means normal volume. Above that gives a small boost.Again to prevent ear blasting.
const MASTER_NO_CHANGE_VALUE: float = 0.70
const MASTER_MAX_BOOST_DB: float = 10.0

const MASTER_BUS_NAME: String = "Master"
const MUSIC_BUS_NAME: String = "Music"
const SFX_BUS_NAME: String = "SFX"

var master_volume: float = DEFAULT_MASTER_VOLUME
var music_volume: float = DEFAULT_MUSIC_VOLUME
var sfx_volume: float = DEFAULT_SFX_VOLUME
var fullscreen: bool = DEFAULT_FULLSCREEN
var current_level_scene: String = DEFAULT_CURRENT_LEVEL_SCENE

# InputSettings can store custom keybinds here.
var input_bindings: Dictionary = {}


# Loads saved data and applies it when the game starts.
func _ready() -> void:
	load_game()
	apply_audio_settings()
	apply_display_settings()


# Saves all current settings to disk.
func save_game() -> void:
	var config_file: ConfigFile = ConfigFile.new()

	config_file.set_value("audio", "master_volume", master_volume)
	config_file.set_value("audio", "music_volume", music_volume)
	config_file.set_value("audio", "sfx_volume", sfx_volume)

	config_file.set_value("display", "fullscreen", fullscreen)
	config_file.set_value("progress", "current_level_scene", current_level_scene)
	config_file.set_value("input", "bindings", input_bindings)

	var save_error: Error = config_file.save(SAVE_PATH)

	if save_error != OK:
		push_warning("Could not save GameData to %s" % SAVE_PATH)
		return

	settings_saved.emit()


# Loads saved settings from disk.
# If no save file exists, the default values stay active.
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		settings_loaded.emit()
		return

	var config_file: ConfigFile = ConfigFile.new()
	var load_error: Error = config_file.load(SAVE_PATH)

	if load_error != OK:
		push_warning("Could not load GameData from %s" % SAVE_PATH)
		settings_loaded.emit()
		return

	master_volume = _get_clamped_float(
		config_file,
		"audio",
		"master_volume",
		DEFAULT_MASTER_VOLUME
	)
	music_volume = _get_clamped_float(
		config_file,
		"audio",
		"music_volume",
		DEFAULT_MUSIC_VOLUME
	)
	sfx_volume = _get_clamped_float(
		config_file,
		"audio",
		"sfx_volume",
		DEFAULT_SFX_VOLUME
	)

	fullscreen = bool(
		config_file.get_value(
			"display",
			"fullscreen",
			DEFAULT_FULLSCREEN
		)
	)

	current_level_scene = (
		String(
			config_file.get_value(
				"progress",
				"current_level_scene",
				DEFAULT_CURRENT_LEVEL_SCENE
			)
		)
		.strip_edges()
	)

	if current_level_scene.is_empty():
		current_level_scene = DEFAULT_CURRENT_LEVEL_SCENE

	var loaded_input_bindings: Variant = config_file.get_value(
		"input",
		"bindings",
		{}
	)

	if loaded_input_bindings is Dictionary:
		input_bindings = (loaded_input_bindings as Dictionary).duplicate(true)
	else:
		input_bindings = {}

	settings_loaded.emit()


# Gets a saved number and clamps it between 0 and 1.
func _get_clamped_float(
	config_file: ConfigFile,
	section: String,
	key: String,
	default_value: float
) -> float:
	return clampf(
		float(config_file.get_value(section, key, default_value)),
		0.0,
		1.0
	)


# Sets master volume.
func set_master_volume(value: float, should_save: bool = true) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_audio_change(should_save)


# Sets music volume.
func set_music_volume(value: float, should_save: bool = true) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_audio_change(should_save)


# Sets sound effect volume.
func set_sfx_volume(value: float, should_save: bool = true) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_audio_change(should_save)


# Applies, emits, and optionally saves audio changes.
func _apply_audio_change(should_save: bool) -> void:
	apply_audio_settings()
	audio_settings_changed.emit()

	if should_save:
		save_game()


# Applies all audio settings to the Godot audio buses.
func apply_audio_settings() -> void:
	_apply_bus_volume(
		MASTER_BUS_NAME,
		_master_volume_to_db(master_volume),
		master_volume
	)
	_apply_bus_volume(
		MUSIC_BUS_NAME,
		linear_to_db(max(music_volume, 0.0001)),
		music_volume
	)
	_apply_bus_volume(
		SFX_BUS_NAME,
		linear_to_db(max(sfx_volume, 0.0001)),
		sfx_volume
	)


# Applies one bus volume.
func _apply_bus_volume(
	bus_name: String,
	volume_db: float,
	volume_value: float
) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)

	if bus_index == -1:
		push_warning("Missing audio bus: %s" % bus_name)
		return

	if volume_value <= 0.0:
		AudioServer.set_bus_mute(bus_index, true)
		AudioServer.set_bus_volume_db(bus_index, -80.0)
		return

	AudioServer.set_bus_mute(bus_index, false)
	AudioServer.set_bus_volume_db(bus_index, volume_db)


# Converts the custom master slider value to decibels.
func _master_volume_to_db(value: float) -> float:
	var clamped_value: float = clampf(value, 0.0, 1.0)

	if clamped_value <= 0.0:
		return -80.0

	if clamped_value <= MASTER_NO_CHANGE_VALUE:
		return lerpf(
			-40.0,
			0.0,
			clamped_value / MASTER_NO_CHANGE_VALUE
		)

	return lerpf(
		0.0,
		MASTER_MAX_BOOST_DB,
		(clamped_value - MASTER_NO_CHANGE_VALUE)
		/ (1.0 - MASTER_NO_CHANGE_VALUE)
	)


# Resets only audio settings.
func reset_audio_settings(should_save: bool = true) -> void:
	master_volume = DEFAULT_MASTER_VOLUME
	music_volume = DEFAULT_MUSIC_VOLUME
	sfx_volume = DEFAULT_SFX_VOLUME

	_apply_audio_change(should_save)


# Sets fullscreen on/off.
func set_fullscreen(value: bool, should_save: bool = true) -> void:
	fullscreen = value
	apply_display_settings()
	display_settings_changed.emit()

	if should_save:
		save_game()


# Applies fullscreen/windowed mode.
func apply_display_settings() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# Saves which level retry/win/lose screens should use.
func set_current_level(level_scene: String, should_save: bool = true) -> void:
	var cleaned_level_scene: String = level_scene.strip_edges()

	if cleaned_level_scene.is_empty():
		current_level_scene = DEFAULT_CURRENT_LEVEL_SCENE
	else:
		current_level_scene = cleaned_level_scene

	current_level_changed.emit(current_level_scene)

	if should_save:
		save_game()


# Gets the current saved level.
func get_current_level() -> String:
	if current_level_scene.strip_edges().is_empty():
		return DEFAULT_CURRENT_LEVEL_SCENE

	return current_level_scene


# Compatibility function for scripts that ask for the most recent level.
func get_most_recent_level() -> String:
	return get_current_level()


# Saves custom input bindings.
func set_input_bindings(
	new_input_bindings: Dictionary,
	should_save: bool = true
) -> void:
	input_bindings = new_input_bindings.duplicate(true)
	input_bindings_changed.emit(input_bindings.duplicate(true))

	if should_save:
		save_game()


# Clears custom input bindings.
func clear_input_bindings(should_save: bool = true) -> void:
	input_bindings.clear()
	input_bindings_changed.emit({})

	if should_save:
		save_game()


# Resets everything stored by GameData.
func reset_all_settings(should_save: bool = true) -> void:
	master_volume = DEFAULT_MASTER_VOLUME
	music_volume = DEFAULT_MUSIC_VOLUME
	sfx_volume = DEFAULT_SFX_VOLUME
	fullscreen = DEFAULT_FULLSCREEN
	current_level_scene = DEFAULT_CURRENT_LEVEL_SCENE
	input_bindings.clear()

	apply_audio_settings()
	apply_display_settings()

	audio_settings_changed.emit()
	display_settings_changed.emit()
	current_level_changed.emit(current_level_scene)
	input_bindings_changed.emit({})

	if should_save:
		save_game()


# Alias for scripts that call this "settings" instead of "game".
# I cannot be arsed finding all of this.
func save_settings() -> void:
	save_game()


# Alias for scripts that call this "settings" instead of "game".
# I cannot be arsed finding all of this.
func load_settings() -> void:
	load_game()
	apply_audio_settings()
	apply_display_settings()
