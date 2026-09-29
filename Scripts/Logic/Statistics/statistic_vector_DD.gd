@tool
class_name StatisticVectorDD extends StatisticRanged

@export_group("statistic properties")
@export var statistic_value: Vector2 : set = _set_statistic_value

var minimum_statistic_value: Vector2 : set = _set_minimum
var maximum_statistic_value: Vector2 : set = _set_maximum

func _get_range_min():
	return minimum_statistic_value

func _get_range_max():
	return maximum_statistic_value

func _set_minimum(new_value: Vector2) -> void:
	minimum_statistic_value = new_value
	_apply_limits()

func _set_maximum(new_value: Vector2) -> void:
	maximum_statistic_value = new_value
	_apply_limits()

func _clamp_value(value):
	return (value as Vector2).clamp(minimum_statistic_value, maximum_statistic_value)

func _on_limits_enabled() -> void:
	if minimum_statistic_value == maximum_statistic_value:
		minimum_statistic_value = statistic_value.min(Vector2.ZERO)
		maximum_statistic_value = statistic_value.max(Vector2.ZERO)

func _set_statistic_value(new_value: Vector2) -> void:
	if not _can_write():
		return

	var old_value: Vector2 = statistic_value
	new_value = _clamp_to_range(new_value)
	statistic_value = new_value

	if old_value != new_value:
		statistic_changed.emit(old_value, new_value)

func set_new_editor_values() -> Array:
	return _build_range_editor_values(TYPE_VECTOR2)
