extends State

func enter() -> void:
	context.head_bob.land($"../Falling".velocity_before_landing)
	context.set_deferred("is_in_air", false)
