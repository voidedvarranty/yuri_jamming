extends State

func enter() -> void:
	# Entering from Sprinting or Idle: ensure base speed and walk bob
	context.statistic_list.set_value_of("issprinting", false)


func physics_update(_delta: float) -> void:
	#no input -> Idle, sprint held -> Sprinting.
	if context.statistic_list.get_value_of("inputdirection") == Vector2.ZERO:
		transitioned.emit("idle")
	elif InputMap.has_action("sprint") and Input.is_action_pressed("sprint"):
		transitioned.emit("sprinting")
