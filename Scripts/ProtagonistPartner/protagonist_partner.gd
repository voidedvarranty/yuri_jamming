extends CharacterBody3D

@onready var statistic_list: StatisticList = $StatisticList

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += Vector3(0, -_stat("gravity", 6.0) * delta, 0)

	move_and_slide()


func _stat(stat_name: String, fallback: float) -> float:
	if statistic_list != null and statistic_list.statistics.has(stat_name):
		return float(statistic_list.get_value_of(stat_name))
	return fallback
