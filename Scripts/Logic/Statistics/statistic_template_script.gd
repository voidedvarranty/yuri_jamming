@tool
extends Node
class_name Statistic

signal statistic_changed(old_value, new_value)

@export_category("statistic properties")
@export var stat_id: StringName : set = set_stat_id
@export var check_limits: bool : set = set_check_limits_value
## Hide this statistic from the StatisticList's Inspector (for live values that
## code updates every frame, like MovementDirection). Still works normally in code.
@export var hide_in_list: bool = false : set = set_hide_in_list

func set_stat_id(new_value: StringName) -> void:
	stat_id = new_value
	notify_property_list_changed()

func set_hide_in_list(new_value: bool) -> void:
	hide_in_list = new_value
	notify_property_list_changed()

func set_check_limits_value(new_value) -> void:
	if new_value and not check_limits and is_node_ready():
		_on_limits_enabled()
	check_limits = new_value
	_apply_limits()
	notify_property_list_changed()

func _ready() -> void:
	_reapply()

func _apply_limits() -> void:
	if is_node_ready():
		_reapply()

func _reapply() -> void:
	pass

func _on_limits_enabled() -> void:
	pass

func get_lookup_id() -> StringName:
	if stat_id != &"":
		return stat_id
	return StringName(name.to_lower())

func set_new_editor_values() -> Array:
	return []

func _get_property_list() -> Array:
	return set_new_editor_values()
