extends State

func enter() -> void:
	context.statistic_list.set_value_of("issprinting", true)


func exit() -> void:
	if context.is_on_floor():
		context.statistic_list.set_value_of("issprinting", false)


func physics_update(_delta: float) -> void:
	if context.statistic_list.get_value_of("inputdirection") == Vector2.ZERO:
		transitioned.emit("idle")
	elif not Input.is_action_pressed("sprint"):
		transitioned.emit("walking")
