extends State

func enter() -> void:
	context.statistic_list.set_value_of("issprinting", false)


func physics_update(_delta: float) -> void:
	# Any movement input -> Walking
	if context.statistic_list.get_value_of("inputdirection") != Vector2.ZERO:
		transitioned.emit("walking")
