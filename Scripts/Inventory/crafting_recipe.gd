# CraftingRecipe - one way to craft the parent InventoryItem.
# Multiple CraftingRecipe children = alternative recipes. Ingredients are item scenes (resolved
# to item ids by ItemDatabase at load), and the mat must contain EXACTLY these items to craft.

@tool
class_name CraftingRecipe
extends Node

# PackedScene keys (drag from FileSystem) avoid id typos; values are required counts.
## Ingredient item scenes and how many of each are needed.
@export var ingredients: Dictionary[PackedScene, int] = {}
## How many items one craft makes (e.g. 5 arrows).
@export_range(1, 99) var result_count: int = 1


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not get_parent() is InventoryItem:
		warnings.append("CraftingRecipe must be a child of an InventoryItem node.")
	if ingredients.is_empty():
		warnings.append("Add at least one ingredient.")
	return warnings
