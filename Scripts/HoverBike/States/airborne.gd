# Airborne - no ray contact. Gravity dominates; engine, grip and steering are scaled by AirControl.
# Returns to Cruising on touchdown (Cruising re-dispatches to Braking/Boosting/etc. if needed).

extends State

func physics_update(delta: float) -> void:
	var stats: StatisticList = context.statistic_list

	if stats.get_value_of("grounded"):
		transitioned.emit("cruising")
		return

	# Single factor applied to all three force helpers.
	var air_control: float = stats.get_value_of("aircontrol")
	context.apply_engine(1.0, air_control)
	context.apply_grip(air_control)
	context.apply_steering(delta, air_control)
