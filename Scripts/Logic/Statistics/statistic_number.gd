# StatisticNumber - float statistic with optional min/max limits and Locked.

@tool
class_name StatisticNumber extends StatisticRanged

@export var statistic_value: float : set = _set_statistic_value

# Not exported; exposed via _build_range_editor_values only while check_limits is on.
# Setters re-apply limits so changing a bound immediately re-clamps the value.
var minimum_statistic_value: float : set = _set_minimum
var maximum_statistic_value: float : set = _set_maximum

func _get_range_min():
	return minimum_statistic_value

func _get_range_max():
	return maximum_statistic_value

func _set_minimum(new_value: float) -> void:
	minimum_statistic_value = new_value
	_apply_limits()

func _set_maximum(new_value: float) -> void:
	maximum_statistic_value = new_value
	_apply_limits()

func _clamp_value(value):
	return clampf(value, minimum_statistic_value, maximum_statistic_value)

func _on_limits_enabled() -> void:
	# No range configured yet: build one that contains the current value (and 0) instead of clamping it to 0.
	if minimum_statistic_value == maximum_statistic_value:
		minimum_statistic_value = minf(statistic_value, 0.0)
		maximum_statistic_value = maxf(statistic_value, 0.0)

func _set_statistic_value(new_value: float) -> void:
	# Locked: ignore the write.
	if not _can_write():
		return

	var old_value: float = statistic_value
	# Clamp (no-op while loading or with limits off), assign, then notify on actual change.
	new_value = _clamp_to_range(new_value)
	statistic_value = new_value

	if old_value != new_value:
		statistic_changed.emit(old_value, new_value)

func set_new_editor_values() -> Array:
	return _build_range_editor_values(TYPE_FLOAT)
