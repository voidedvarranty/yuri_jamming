# Reversing - brake held from standstill. Drives backwards up to MaxReverseSpeed.
# Steering is inverted when invert_steering is on (car-style). Any non-negative throttle
# hands control back to Cruising, whose engine/coast forces then brake the backward roll.

extends State

## true = steers like a car in reverse (press right, the nose swings left).
@export var invert_steering: bool = true

func physics_update(delta: float) -> void:
	var stats: StatisticList = context.statistic_list
	var input: Vector2 = stats.get_value_of("inputdirection")

	if not stats.get_value_of("grounded"):
		transitioned.emit("airborne")
		return
	if input.y >= 0.0:
		transitioned.emit("cruising")
		return

	context.apply_reverse()
	context.apply_grip()
	# Inversion is state-driven rather than speed-driven to avoid flipping mid-manoeuvre.
	context.apply_steering(delta, 1.0, -1.0 if invert_steering else 1.0)
