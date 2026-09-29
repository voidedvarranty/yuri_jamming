extends State

func physics_update(delta: float) -> void:
	var stats: StatisticList = context.statistic_list
	var input: Vector2 = stats.get_value_of("inputdirection")

	if not stats.get_value_of("grounded"):
		transitioned.emit("airborne")
		return
	if input.y < 0.0:
		if stats.get_value_of("forwardspeed") > 0.5:
			transitioned.emit("braking")
		else:
			transitioned.emit("reversing")
		return
	if stats.get_value_of("boosting") and input.y > 0.0:
		transitioned.emit("boosting")
		return

	context.apply_engine()
	context.apply_grip()
	context.apply_steering(delta)
	if is_zero_approx(input.y):
		context.apply_coast()
