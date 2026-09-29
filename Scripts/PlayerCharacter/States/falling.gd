extends State

var velocity_before_landing: float = 0.0


func physics_update(_delta: float) -> void:
	if context.velocity.y != 0.0:
		velocity_before_landing = context.velocity.y

	if context.is_on_floor():
		transitioned.emit("landed")
