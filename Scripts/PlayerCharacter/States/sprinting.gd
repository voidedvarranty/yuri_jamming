extends State

func enter() -> void:
	context.statistic_list.set_value_of("issprinting", true)


#only clear on the ground, leaving the NormalStateEngine because of a jump
#keeps IsSprinting set, so run speed is carried through the air. Idle/Walking clear it after landing.
func exit() -> void:
	if context.is_on_floor():
		context.statistic_list.set_value_of("issprinting", false)


func physics_update(_delta: float) -> void:
	#no input -> Idle, sprint released -> Walking
	if context.statistic_list.get_value_of("inputdirection") == Vector2.ZERO:
		transitioned.emit("idle")
	elif not Input.is_action_pressed("sprint"):
		transitioned.emit("walking")
