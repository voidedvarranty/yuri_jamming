extends State

func enter() -> void:
	context.statistic_list.set_value_of("inputdirection", Vector2.ZERO)
	context.statistic_list.set_value_of("boosting", false)

func physics_update(delta: float) -> void:
	if context.statistic_list.get_value_of("grounded"):
		context.apply_coast()
		context.apply_grip()
	context.apply_steering(delta)
