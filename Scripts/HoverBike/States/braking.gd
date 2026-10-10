# Braking - brake held while moving forward.
# apply_brake removes speed without overshooting into reverse; after the bike has been
# (nearly) stationary for reverse_delay seconds with brake still held, it switches to Reversing.
# Releasing the brake returns to Cruising.

extends State

## How long you have to hold brake at a standstill before reversing starts.
@export var reverse_delay: float = 0.35

# Accumulated time spent below the standstill threshold while braking.
var _stopped_time := 0.0

func enter() -> void:
	_stopped_time = 0.0

func physics_update(delta: float) -> void:
	var stats: StatisticList = context.statistic_list
	var input: Vector2 = stats.get_value_of("inputdirection")

	if not stats.get_value_of("grounded"):
		transitioned.emit("airborne")
		return
	if input.y >= 0.0:
		transitioned.emit("cruising")
		return

	# Standstill timer; reset whenever the bike is moving again.
	if absf(stats.get_value_of("forwardspeed")) < 0.5:
		_stopped_time += delta
		if _stopped_time >= reverse_delay:
			transitioned.emit("reversing")
			return
	else:
		_stopped_time = 0.0

	# Grip and steering stay active so the bike can be aimed while slowing down.
	context.apply_brake(delta)
	context.apply_grip()
	context.apply_steering(delta)
