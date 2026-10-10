extends State

func enter() -> void:
	#not ascending on entry = walked off an edge, not a jump.
	if context.velocity.y <= 0.0:
		transitioned.emit("falling")
		return
	context.head_bob.jump()


#spex reached -> Falling.
func physics_update(_delta: float) -> void:
	if context.velocity.y <= 0.0:
		transitioned.emit("falling")
