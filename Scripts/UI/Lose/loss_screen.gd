extends Control

@export_group("Scenes")
# Used if GameData has no saved current level.
@export var fallback_level_scene: String = "main"

# SceneManager key for the main menu.
@export var main_menu_scene: String = "main_menu"

@export_group("Scene Transitions")
# Loading duration when retrying after losing.
@export var retry_loading_duration: float = 1.0

# Loading duration when returning to the main menu.
@export var menu_loading_duration: float = 1.0


func _on_retry_button_pressed() -> void:
	SceneManager.go(get_retry_level_scene(), retry_loading_duration)


func _on_main_menu_button_pressed() -> void:
	SceneManager.go(main_menu_scene, menu_loading_duration)


# Gets the scene the Retry button should load.
func get_retry_level_scene() -> String:
	# First try the current level saved in GameData. This is preferred
	var current_level_scene: String = _get_game_data_scene("get_current_level")

	# strip_edges() makes sure spaces like "   " do not count. and accidental spaces are removed.
	if current_level_scene.strip_edges() != "":
		return current_level_scene

	# If that is empty, try the most recent level.
	var recent_level_scene: String = _get_game_data_scene("get_most_recent_level")

	if recent_level_scene.strip_edges() != "":
		return recent_level_scene

	# If GameData has nothing, use the fallback from the Inspector.
	return fallback_level_scene


# Safely calls a GameData scene getter if it exists.
# This keeps the loss screen from exploding if that GameData function is missing.
func _get_game_data_scene(method_name: String) -> String:
	if not GameData.has_method(method_name):
		return ""

	return GameData.call(method_name)
