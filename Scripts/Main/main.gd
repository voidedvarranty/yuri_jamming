extends Node

#Useful tool for grouping export variables. Lowkey kinda pointless here. But I wanted to show it.
@export_group("Scenes")

# This should match a key in the SceneManager scenes dictionary.
# Example: "main", "paper_clip", "boss_room"
@export var current_level_scene: String = "main"


func _ready() -> void:
	# Saves this scene as the current level in GameData.
	# Retry/continue systems can then know which scene to load.
	GameData.set_current_level(current_level_scene)
