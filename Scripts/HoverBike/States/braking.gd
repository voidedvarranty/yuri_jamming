extends State

## How long you have to hold brake at a standstill before reversing starts.
@export var reverse_delay: float = 0.35

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

	if absf(stats.get_value_of("forwardspeed")) < 0.5:
		_stopped_time += delta
		if _stopped_time >= reverse_delay:
			transitioned.emit("reversing")
			return
	else:
		_stopped_time = 0.0

	context.apply_brake(delta)
	context.apply_grip()
	context.apply_steering(delta)
