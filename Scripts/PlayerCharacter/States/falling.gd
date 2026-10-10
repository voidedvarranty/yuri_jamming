extends State

var velocity_before_landing: float = 0.0


func physics_update(_delta: float) -> void:
	# move_and_slide zeroes velocity.y on the impact frame, so keep the last non-zero value
	if context.velocity.y != 0.0:
		velocity_before_landing = context.velocity.y

	# Touchdown -> Landed.
	if context.is_on_floor():
		transitioned.emit("landed")
