extends State

func physics_update(delta: float) -> void:
	var stats: StatisticList = context.statistic_list

	if stats.get_value_of("grounded"):
		transitioned.emit("cruising")
		return

	var air_control: float = stats.get_value_of("aircontrol")
	context.apply_engine(1.0, air_control)
	context.apply_grip(air_control)
	context.apply_steering(delta, air_control)
