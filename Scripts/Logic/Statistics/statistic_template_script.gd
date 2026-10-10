# Statistic - abstract base for all statistic types (number, bool, string, vectors).
#
# Subclasses implement:
#   _reapply()              push the current value back through its setter (re-applies limits)
#   _on_limits_enabled()    seed sensible limits when check_limits is first switched on
#   set_new_editor_values() extra editor-only properties (min/max, locked, ...)
#
# Load-order note: when a scene is instantiated, properties are assigned in
# serialization order, so statistic_value is set BEFORE min/max. All limit logic is
# therefore gated on is_node_ready() and applied once in _ready(); otherwise values
# would be clamped against a still-empty 0..0 range on load.

@tool
extends Node
class_name Statistic

# Emitted by subclass setters only when the value actually changes.
signal statistic_changed(old_value, new_value)

@export_category("statistic properties")
@export var stat_id: StringName : set = set_stat_id
@export var check_limits: bool : set = set_check_limits_value
## Hide this statistic from the StatisticList's Inspector (for live values that
## code updates every frame, like MovementDirection). Still works normally in code.
@export var hide_in_list: bool = false : set = set_hide_in_list

# property_list_changed is what StatisticList listens to for re-indexing.
func set_stat_id(new_value: StringName) -> void:
	stat_id = new_value
	notify_property_list_changed()

func set_hide_in_list(new_value: bool) -> void:
	hide_in_list = new_value
	notify_property_list_changed()

func set_check_limits_value(new_value) -> void:
	# Seed limits BEFORE enabling them, so the value isn't clamped against an empty range in between.
	if new_value and not check_limits and is_node_ready():
		_on_limits_enabled()
	check_limits = new_value
	_apply_limits()
	notify_property_list_changed()

# Deferred limit application (see load-order note above).
func _ready() -> void:
	_reapply()

# Entry point used by all limit-related setters; no-op until the node is ready.
func _apply_limits() -> void:
	if is_node_ready():
		_reapply()

func _reapply() -> void:
	pass

func _on_limits_enabled() -> void:
	pass

# Lookup key used by StatisticList.
func get_lookup_id() -> StringName:
	if stat_id != &"":
		return stat_id
	return StringName(name.to_lower())

func set_new_editor_values() -> Array:
	return []

# Exposes subclass editor properties (dynamic, depends on check_limits).
func _get_property_list() -> Array:
	return set_new_editor_values()
