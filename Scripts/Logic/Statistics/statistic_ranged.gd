# StatisticRanged - shared min/max clamping and Locked support for numeric/vector statistics.
#
# Locked blocks writes through the public setter. _reapply() uses _bypass_lock so that
# limit enforcement still works on locked statistics (a locked value can never sit
# outside its own range).

@tool
class_name StatisticRanged extends Statistic

# Not exported directly; exposed (and serialized) through _build_range_editor_values.
var locked: bool

var _bypass_lock := false

# Overridden by subclasses with typed min/max.
func _get_range_min():
	return null

func _get_range_max():
	return null

# Generic fallback; subclasses override with type-correct clamping (component-wise for vectors).
func _clamp_value(value):
	return clamp(value, _get_range_min(), _get_range_max())

func _clamp_to_range(value):
	# Skip clamping during scene load (see Statistic load-order note).
	if check_limits and is_node_ready():
		return _clamp_value(value)
	return value

func _can_write() -> bool:
	return _bypass_lock or not locked

func _reapply() -> void:
	# Round-trip through the property setter via set()/get() so the subclass clamp logic runs.
	_bypass_lock = true
	set("statistic_value", get("statistic_value"))
	_bypass_lock = false

func _build_range_editor_values(value_type: int) -> Array:
	var new_editor_values: Array

	# min/max are only editor-visible and serialized while limits are enabled; locked is always exposed.
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
