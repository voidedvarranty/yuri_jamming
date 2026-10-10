#Three independent layers are summed every physics tick, so none of them fight
# over the head transform:
#   1.Gait bob: figure-8 path is a vertical dip twice per stride, lateral sway and roll
#     once per stride. Speed/amount come from Idle/Walk/Run statistics and are
#     blended exponentially so mode changes never produce a discontinuity.
#     The phase accumulates so changing the
#     frequency only changes the rate, never the current position.
#   2.Idle breathing: the same vertical term with the Idle values (sway/roll faded out).
#   3.Impulse spring: under damped spring on Y axis excited by kick(),
#     used for jump bumps and fall-speed-scaled landing dips

class_name HeadBob
extends Node

# Emitted at each trough of the vertical bob while walking/running 
signal footstep

enum Mode { IDLE, WALK, RUN, AIR }

@export var player: CharacterBody3D
@export var head: Node3D

@export_group("Advanced")
## Side-to-side sway, as a fraction of the bob amount
@export var sway_ratio: float = 0.6
## Head tilt in degrees per metre of bob amount
@export var tilt_ratio: float = 18.0
## How fast the head settles after jumps and landings, higher = snappier
@export var spring_speed: float = 14.0
## Largest possible landing dip (metres)
@export var max_landing_dip: float = 0.15

var mode: Mode = Mode.IDLE

var _base_position := Vector3.ZERO
var _phase := 0.0
# Blended dips-per-second and amplitude currently in effect
var _speed := 0.0
var _amount := 0.0
#blend for the sway or roll layers
var _moving := 0.0
# Integer step index
var _last_step := 0
# Impulse spring state 
var _spring_offset := 0.0
var _spring_velocity := 0.0


func _ready() -> void:
	if player == null:
		player = get_parent() as CharacterBody3D
	if head == null and player != null:
		head = player.get_node_or_null("Neck/Head") as Node3D
	if head != null:
		# Rest position
		_base_position = head.position


func _physics_process(delta: float) -> void:
	if player == null or head == null:
		return
	# Freeze while the player is frozen so the camera stays put
	if not player.is_physics_processing():
		return

	mode = _current_mode()
	var target_speed := 0.0
	var target_amount := 0.0
	#per mode targets, AIR keeps the current rate and fades the amplitude out
	match mode:
		Mode.IDLE:
			target_speed = _stat("idlebobspeed", 0.5)
			target_amount = _stat("idlebobamount", 0.008)
		Mode.WALK:
			target_speed = _stat("walkbobspeed", 1.8)
			target_amount = _stat("walkbobamount", 0.035)
		Mode.RUN:
			target_speed = _stat("runbobspeed", 2.6)
			target_amount = _stat("runbobamount", 0.055)
		Mode.AIR:
			target_speed = _speed
			target_amount = 0.0

	#frame-rate independent exponential blend toward the targets
	var blend := 1.0 - exp(-_stat("bobsmoothing", 8.0) * delta)
	_speed = lerpf(_speed, target_speed, blend)
	_amount = lerpf(_amount, target_amount, blend)
	_moving = lerpf(_moving, 1.0 if mode == Mode.WALK or mode == Mode.RUN else 0.0, blend)

	_phase += _speed * PI * delta
	var step := floori((_phase - PI * 0.5) / PI)
	if step != _last_step:
		_last_step = step
		if _moving > 0.5 and mode != Mode.AIR:
			footstep.emit()

	var bob_y := _amount * (cos(_phase * 2.0) - 1.0) * 0.5
	#Lateral sway and roll at half the vertical frequenc faded by _moving
	var sway_x := _amount * sway_ratio * sin(_phase) * _moving
	var tilt := deg_to_rad(_amount * tilt_ratio) * -sin(_phase) * _moving

	# Damped spring
	var acceleration := -spring_speed * spring_speed * _spring_offset - 1.1 * spring_speed * _spring_velocity
	_spring_velocity += acceleration * delta
	_spring_offset += _spring_velocity * delta

	head.position = _base_position + Vector3(sway_x, bob_y + _spring_offset, 0.0)
	head.rotation.z = tilt


func _current_mode() -> Mode:
	#mode priority air > idle > run > walk
	if not player.is_on_floor():
		return Mode.AIR
	if Vector2(player.velocity.x, player.velocity.z).length() < 0.05:
		return Mode.IDLE
	if player.has_method("is_sprinting") and player.is_sprinting():
		return Mode.RUN
	return Mode.WALK


func kick(metres: float) -> void:
	# Velocity impulse sized
	_spring_velocity += metres * spring_speed * 1.6


func jump() -> void:
	kick(_stat("jumpkick", 0.05))


func land(fall_speed: float) -> void:
	# Dip proportional to impact speed, capped by max_landing_dip
	kick(-minf(absf(fall_speed) * _stat("landingdip", 0.012), max_landing_dip))


func _stat(stat_name: String, fallback: float) -> float:
	var stats = player.get("statistic_list") if player != null else null
	if stats is StatisticList and stats.statistics.has(stat_name):
		return float(stats.get_value_of(stat_name))
	return fallback
