@tool
class_name InventoryItem
extends Node

@export var display_name: String = ""
@export_multiline var description: String = ""
## How many the player can carry at once (0 = no limit). The Forest: 5 rocks, 10 sticks...
@export_range(0, 999) var max_carry: int = 10
## Optional custom id. Leave empty to use the scene file name (rock.tscn -> "rock").
@export var item_id: StringName = &""
## Untick for items that should only exist in the inventory (or can't be taken yet).
@export var can_pick_up: bool = true

@export_group("Using")
## Player statistics changed when the item is used from the inventory (left click),
## e.g. "health": 10. Only statistics that exist in the player's StatisticList change.
@export var use_effects: Dictionary[String, float] = {}
## Remove one from the inventory each time it is used (food, medicine...).
@export var consume_on_use: bool = true

@export_group("In Hand")
## Can this be held in the hand (left click in the inventory)?
@export var can_hold: bool = true
## Nudges the item in the hand (metres, relative to the grip).
@export var hand_offset: Vector3 = Vector3.ZERO
## Rotation in degrees for how the item is held.
@export var hand_rotation: Vector3 = Vector3.ZERO
## Size in the hand (big items are shrunk to fit first).
@export_range(0.1, 3.0, 0.05) var hand_scale: float = 1.0

@export_group("Inventory Look")
## Extra size on the inventory mat. Models are auto-fitted first, so 1.0 is usually right.
@export_range(0.1, 3.0, 0.05) var inventory_scale: float = 1.0
## Rotation in degrees for how the model lies on the mat.
@export var inventory_rotation: Vector3 = Vector3.ZERO


func get_item_root() -> Node3D:
	return get_parent() as Node3D


func get_item_id() -> StringName:
	if item_id != &"":
		return item_id
	var root := get_parent()
	if root == null:
		return &"unknown_item"
	if root.scene_file_path != "":
		return StringName(root.scene_file_path.get_file().get_basename().to_snake_case())
	return StringName(String(root.name).to_snake_case())


func get_display_name() -> String:
	if display_name != "":
		return display_name
	return String(get_item_id()).capitalize()


static func find_on(node: Node) -> InventoryItem:
	var depth := 0
	while node != null and depth < 4:
		for child in node.get_children():
			if child is InventoryItem:
				return child
		node = node.get_parent()
		depth += 1
	return null


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var root := get_parent()
	if not root is Node3D:
		warnings.append("InventoryItem must be a direct child of a 3D object (Node3D, RigidBody3D, StaticBody3D...).")
	elif Engine.is_editor_hint() and is_inside_tree() and root != get_tree().edited_scene_root:
		warnings.append("Tip: put InventoryItem under the ROOT of the item's own scene and save it in res://Scenes/Items/, so it can be crafted and dropped.")
	return warnings
