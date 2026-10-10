extends State

func enter() -> void:
	#head dip scales with Falling.velocity_before_landing
	context.head_bob.land($"../Falling".velocity_before_landing)
	#the is_in_air setter triggers a root-engine transition, which must not run
	#while the InAirStateEngine is still inside this transition
	context.set_deferred("is_in_air", false)
