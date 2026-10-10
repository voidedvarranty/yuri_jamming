# Boosting - boost action held with forward throttle on the ground.
# Scales acceleration and top speed by BoostMultiplier and kicks the camera FOV.
# FOV targets are absolute (base_fov + kick / base_fov) and the previous tween is killed,
# so rapid boost toggling can't accumulate FOV drift.

extends State

@export var fov_kick: float = 12.0
@export var fov_tween_time: float = 0.25

# Camera captured on enter so exit() restores the same one even if the active camera changed.
var _camera: Camera3D
var _tween: Tween

func enter() -> void:
	_camera = context.get_active_camera()
	_tween_fov(context.base_fov + fov_kick)

func exit() -> void:
	_tween_fov(context.base_fov)

func physics_update(delta: float) -> void:
	var stats: StatisticList = context.statistic_list
	var input: Vector2 = stats.get_value_of("inputdirection")

	# Leaving the ground or releasing boost/throttle ends the boost.
	if not stats.get_value_of("grounded"):
		transitioned.emit("airborne")
		return
	if not stats.get_value_of("boosting") or input.y <= 0.0:
		transitioned.emit("cruising")
		return

	# Multiplier applies to both acceleration and the speed cap.
	context.apply_engine(stats.get_value_of("boostmultiplier"))
	context.apply_grip()
	context.apply_steering(delta)

func _tween_fov(target: float) -> void:
	if not is_instance_valid(_camera):
		return
	# Kill the in-flight tween before starting a new one.
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_camera, "fov", target, fov_tween_time)
