@tool
class_name StatisticRanged extends Statistic

var locked: bool

var _bypass_lock := false

func _get_range_min():
	return null

func _get_range_max():
	return null

func _clamp_value(value):
	return clamp(value, _get_range_min(), _get_range_max())

func _clamp_to_range(value):
	if check_limits and is_node_ready():
		return _clamp_value(value)
	return value

func _can_write() -> bool:
	return _bypass_lock or not locked

func _reapply() -> void:
	_bypass_lock = true
	set("statistic_value", get("statistic_value"))
	_bypass_lock = false

func _build_range_editor_values(value_type: int) -> Array:
	var new_editor_values: Array

	if check_limits:
		new_editor_values.append({
			"name": &"minimum_statistic_value",
			"type": value_type,
			"usage": PROPERTY_USAGE_DEFAULT,
		})
		new_editor_values.append({
			"name": &"maximum_statistic_value",
			"type": value_type,
			"usage": PROPERTY_USAGE_DEFAULT,
		})

	new_editor_values.append({
		"name": &"locked",
		"type": TYPE_BOOL,
		"usage": PROPERTY_USAGE_DEFAULT,
	})

	return new_editor_values
