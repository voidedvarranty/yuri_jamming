# ItemDefinition - immutable runtime snapshot of an InventoryItem's settings.
# Created by ItemDatabase; the inventory only ever deals in item ids + definitions,
# never in live world nodes (which are freed on pickup).

class_name ItemDefinition
extends RefCounted

var id: StringName
var display_name: String
var description: String
var max_carry: int
var use_effects: Dictionary
var consume_on_use: bool
var inventory_scale: float
var inventory_rotation: Vector3
var can_hold: bool
var hand_offset: Vector3
var hand_rotation: Vector3
var hand_scale: float

# Preferred source for new instances (mat models, hand model, dropped items).
var scene: PackedScene
# Fallback for items placed inline in a level: a detached duplicate of the original.
var template: Node3D


static func from_item(item: InventoryItem) -> ItemDefinition:
	var def := ItemDefinition.new()
	def.id = item.get_item_id()
	def.display_name = item.get_display_name()
	def.description = item.description
	def.max_carry = item.max_carry
	def.use_effects = item.use_effects.duplicate()
	def.consume_on_use = item.consume_on_use
	def.inventory_scale = item.inventory_scale
	def.inventory_rotation = item.inventory_rotation
	def.can_hold = item.can_hold
	def.hand_offset = item.hand_offset
	def.hand_rotation = item.hand_rotation
	def.hand_scale = item.hand_scale
	return def


# Fresh instance; callers decide whether it's a display copy (process disabled) or a world object.
func instantiate() -> Node3D:
	if scene != null:
		return scene.instantiate() as Node3D
	if template != null:
		return template.duplicate() as Node3D
	return null


func is_usable() -> bool:
	return not use_effects.is_empty()


# max_carry <= 0 means unlimited.
func has_carry_limit() -> bool:
	return max_carry > 0
