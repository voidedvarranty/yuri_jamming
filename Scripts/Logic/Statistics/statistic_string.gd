# StatisticString - text statistic. With check_limits on, values longer than max_length are truncated.
# min_length is exposed but not enforced; must_contain / cant_contain are reserved and currently unused.

@tool
class_name StatisticString extends Statistic

@export_group("statistic value")
@export var statistic_value: String : set = _set_statistic_value

# 0 = unlimited. Both lengths are clamped to >= 0 and re-applied on change.
var max_length: int : set = set_max_length
var min_length: int : set = set_min_length

var must_contain: Array[String]
var cant_contain: Array[String]

func set_min_length(new_value: int) -> void:
	min_length = max(new_value, 0)
	_apply_limits()

func set_max_length(new_value: int) -> void:
	max_length = max(new_value, 0)
	_apply_limits()

func _set_statistic_value(new_value: String) -> void:
	var old_value: String = statistic_value

	# Truncate (not reject) over-long text; skipped during scene load.
	if check_limits and is_node_ready() and max_length > 0 and new_value.length() > max_length:
		new_value = new_value.substr(0, max_length)

	statistic_value = new_value

	if old_value != new_value:
		statistic_changed.emit(old_value, new_value)

func _reapply() -> void:
	statistic_value = statistic_value

func set_new_editor_values() -> Array:
	if check_limits:
		return [
			{
				"name": &"min_length",
				"type": TYPE_INT,
				"usage": PROPERTY_USAGE_DEFAULT,
			},
			{
				"name": &"max_length",
				"type": TYPE_INT,
				"usage": PROPERTY_USAGE_DEFAULT,
			},
		]

	return []
