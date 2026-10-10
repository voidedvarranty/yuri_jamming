# Parked - no rider. Inputs are zeroed so the shared helpers act as pure damping:
# hover continues (in HoverBike), horizontal motion decays, and spin is stopped.

extends State

func enter() -> void:
	# Clear any input/boost left over from the last rider.
	context.statistic_list.set_value_of("inputdirection", Vector2.ZERO)
	context.statistic_list.set_value_of("boosting", false)

func physics_update(delta: float) -> void:
	# Ground-only drag + grip; airborne parked bikes just follow physics.
	if context.statistic_list.get_value_of("grounded"):
		context.apply_coast()
		context.apply_grip()
	# Steer input is 0 here, so this drives yaw rate to 0 (stops residual spin).
	context.apply_steering(delta)
