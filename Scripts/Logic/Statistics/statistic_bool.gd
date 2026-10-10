# StatisticBool - boolean statistic. With check_limits on, the value is forced to forced_bool_value.

@tool
class_name StatisticBool extends Statistic

@export_group("statistic value")
@export var statistic_value: bool : set = _set_statistic_value

# Not exported; exposed only while check_limits is on. Setting it re-applies immediately.
var forced_bool_value: bool : set = _set_forced_bool_value

func _set_forced_bool_value(new_value: bool) -> void:
	forced_bool_value = new_value
	_apply_limits()

func _set_statistic_value(new_value: bool) -> void:
	var old_value: bool = statistic_value

	# Forced value wins once the node is ready and limits are on; raw value is kept during load.
	var resolved_value: bool = forced_bool_value if (check_limits and is_node_ready()) else new_value

	statistic_value = resolved_value

	if old_value != resolved_value:
		statistic_changed.emit(old_value, resolved_value)

func _reapply() -> void:
	statistic_value = statistic_value

# Enabling limits forces the current value, so nothing flips.
func _on_limits_enabled() -> void:
	forced_bool_value = statistic_value

func set_new_editor_values() -> Array:
	if check_limits:
		return [{
			"name": &"forced_bool_value",
			"type": TYPE_BOOL,
			"usage": PROPERTY_USAGE_DEFAULT,
			"prefix": "statistic",
		}]

	return []
