# Cruising - default ridden state on the ground.
# Dispatches to Airborne / Braking / Reversing / Boosting, otherwise applies normal driving forces.
# Transitions return immediately so the target state handles this tick's forces from next tick on.

extends State

func physics_update(delta: float) -> void:
	var stats: StatisticList = context.statistic_list
	var input: Vector2 = stats.get_value_of("inputdirection")

	# Lost ground contact (all rays missing).
	if not stats.get_value_of("grounded"):
		transitioned.emit("airborne")
		return
	# Brake input: Braking while still moving forward, otherwise Reversing.
	if input.y < 0.0:
		if stats.get_value_of("forwardspeed") > 0.5:
			transitioned.emit("braking")
		else:
			transitioned.emit("reversing")
		return
	# Boost only engages with forward throttle.
	if stats.get_value_of("boosting") and input.y > 0.0:
		transitioned.emit("boosting")
		return

	# Normal drive; coast drag only while no throttle so it doesn't fight the engine.
	context.apply_engine()
	context.apply_grip()
	context.apply_steering(delta)
	if is_zero_approx(input.y):
		context.apply_coast()
