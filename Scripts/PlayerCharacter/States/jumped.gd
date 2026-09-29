extends State

func enter() -> void:
	if context.velocity.y <= 0.0:
		transitioned.emit("falling")
		return
	context.head_bob.jump()


func physics_update(_delta: float) -> void:
	if context.velocity.y <= 0.0:
		transitioned.emit("falling")
