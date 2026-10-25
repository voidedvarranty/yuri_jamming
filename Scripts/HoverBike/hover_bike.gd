

class_name HoverBike
extends RigidBody3D

@export_group("Shape")
@export var body_half_length := 1.0   ## hover ray spread front/back
@export var body_half_width := 0.4    ## hover ray spread left/right
@export var ray_length_multiplier := 2.5


@export_group("Rider")
##Where the player sits. Move the node to change the seat position.
@export var seat: RemoteTransform3D
##Player must be inside this to get on. Its collision mask MUST!!! include the player's collision layer
@export var mount_area: Area3D
##Marker3D children are exit spots, tried in order until one is free
@export var exit_points: Node3D


@export_group("Camera")
##Third person camera. Its position and angle relative to the bike are kept while following.
@export var chase_camera: Camera3D
@export var cam_smoothing := 6.0

@onready var statistic_list: StatisticList = $StatisticList
@onready var state_engine: StateEngine = $StateEngine

var rider: CharacterBody3D = null


var base_fov := 75.0


var _rays: Array[RayCast3D] = []


var _ground_normal := Vector3.UP

var _cam_forward := Vector3.FORWARD
var _cam_offset := Vector3.ZERO
var _cam_rest_basis := Basis.IDENTITY


func _ready() -> void:
	can_sleep = false
	add_to_group(&"vehicles")
	_build_rays()
	_setup_chase_camera()
	if seat == null or mount_area == null:
		push_warning("HoverBike: assign seat and mount_area in the Inspector.")



func stat(id: String):
	return statistic_list.get_value_of(id)


func _physics_process(delta: float) -> void:
	_update_hover()

	statistic_list.set_value_of("forwardspeed", linear_velocity.dot(-global_basis.z))
	_apply_stability(delta)

	if chase_camera != null and chase_camera.current:
		_update_chase_camera(delta)


func drive(steer: float, throttle: float, boost: bool) -> void:
	statistic_list.set_value_of("inputdirection", Vector2(clampf(steer, -1.0, 1.0), clampf(throttle, -1.0, 1.0)))
	statistic_list.set_value_of("boosting", boost)


func _update_hover() -> void:
	var hover_height: float = stat("hoverheight")
	var spring: float = stat("springstrength")
	var damping: float = stat("springdamping")
	var up := global_basis.y
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * gravity_scale

	var n := float(_rays.size())
	var grounded := false
	var normal_sum := Vector3.ZERO

	for r in _rays:

		r.target_position = Vector3.DOWN * hover_height * ray_length_multiplier
		if not r.is_colliding():
			continue
		grounded = true

		normal_sum += r.get_collision_normal()

		var origin := r.global_position

		var compression := hover_height - origin.distance_to(r.get_collision_point())
		var offset := origin - global_position

		var point_vel := linear_velocity + angular_velocity.cross(offset)
		var up_speed := point_vel.dot(up)

		
		var force := (g + compression * spring - up_speed * damping) * mass / n
		apply_force(up * maxf(force, 0.0), offset)

	_ground_normal = normal_sum.normalized() if grounded else Vector3.UP
	statistic_list.set_value_of("grounded", grounded)


func _apply_stability(delta: float) -> void:
	var up := global_basis.y
	var forward := (-global_basis.z).normalized()
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	var max_lean: float = stat("leanangle")

	var yaw_rate := angular_velocity.dot(up)
	var fwd_speed: float = stat("forwardspeed")

	var lean := -clampf(atan(fwd_speed * yaw_rate / g), -max_lean, max_lean)


	var target_up := _ground_normal.rotated(forward, lean)

	angular_velocity += up.cross(target_up) * float(stat("uprightstrength")) * delta


	var tilt_part := angular_velocity - up * angular_velocity.dot(up)
	angular_velocity -= tilt_part * clampf(float(stat("uprightdamping")) * delta, 0.0, 1.0)


func apply_engine(accel_multiplier := 1.0, control := 1.0) -> void:
	var throttle: float = stat("inputdirection").y
	var fwd_speed: float = stat("forwardspeed")
	var accel: float = float(stat("engineaccel")) * accel_multiplier
	var top: float = float(stat("maxspeed")) * accel_multiplier

	if throttle > 0.0 and fwd_speed < top:
		apply_central_force(-global_basis.z * throttle * accel * mass * control)


func apply_brake(delta: float, control := 1.0) -> void:
	var up := global_basis.y
	var flat_vel := linear_velocity - up * linear_velocity.dot(up)
	var speed := flat_vel.length()
	if speed < 0.01:
		return
	var decel := minf(float(stat("brakeforce")), speed / delta)
	apply_central_force(-flat_vel / speed * decel * mass * control)


func apply_reverse(control := 1.0) -> void:
	var throttle: float = stat("inputdirection").y
	var fwd_speed: float = stat("forwardspeed")
	if throttle < 0.0 and fwd_speed > -float(stat("maxreversespeed")):
		apply_central_force(-global_basis.z * throttle * float(stat("reverseaccel")) * mass * control)


func apply_grip(control := 1.0) -> void:
	var right := global_basis.x
	apply_central_force(-right * linear_velocity.dot(right) * float(stat("lateralgrip")) * mass * control)


func apply_coast() -> void:
	var up := global_basis.y
	var flat_vel := linear_velocity - up * linear_velocity.dot(up)
	apply_central_force(-flat_vel * float(stat("idledrag")) * mass)


func apply_steering(delta: float, control := 1.0, direction := 1.0) -> void:
	var up := global_basis.y
	var steer: float = stat("inputdirection").x
	var fwd_speed: float = stat("forwardspeed")
	var speed_factor := clampf(absf(fwd_speed) / 5.0, 0.3, 1.0)

	var target_yaw := -steer * float(stat("turnspeed")) * speed_factor * direction
	var current_yaw := angular_velocity.dot(up)

	var response := clampf(float(stat("turnresponse")) * delta * control, 0.0, 1.0)
	angular_velocity += up * (target_yaw - current_yaw) * response


func get_active_camera() -> Camera3D:
	return get_viewport().get_camera_3d()


func can_mount(character: Node3D) -> bool:
	return rider == null and mount_area != null and character is PhysicsBody3D and mount_area.overlaps_body(character)


func can_dismount() -> bool:
	return linear_velocity.length() <= float(stat("maxdismountspeed"))


func mount(character: CharacterBody3D) -> void:
	rider = character
	if seat != null:
		seat.remote_path = seat.get_path_to(rider)
	if chase_camera != null:
		_snap_chase_camera()
	var active_cam := get_active_camera()
	if active_cam != null:
		base_fov = active_cam.fov
	state_engine.transition_to_new_state(&"riddenstateengine")


func dismount() -> void:
	if rider == null:
		return
	state_engine.transition_to_new_state(&"parked")
	if seat != null:
		seat.remote_path = NodePath()
	rider = null


func get_heading_yaw() -> float:
	var f := _flat_forward()
	return atan2(-f.x, -f.z)


func get_exit_position() -> Vector3:
	if exit_points == null:
		return global_position + Vector3.UP * 2.0
	var flat := Transform3D(Basis.looking_at(_flat_forward(), Vector3.UP), global_position)
	var to_bike := global_transform.affine_inverse()
	var space := get_world_3d().direct_space_state
	for point in exit_points.get_children():
		if not point is Node3D:
			continue
		var p: Vector3 = flat * (to_bike * (point as Node3D).global_position)
		var q := PhysicsRayQueryParameters3D.create(global_position, p)
		q.exclude = [get_rid()]
		if space.intersect_ray(q).is_empty():
			return p
	return global_position + Vector3.UP * 2.0


func _build_rays() -> void:
	for x in [-body_half_width, body_half_width]:
		for z in [-body_half_length, body_half_length]:
			var r := RayCast3D.new()
			r.position = Vector3(x, 0, z)
			add_child(r)
			_rays.append(r)


func _setup_chase_camera() -> void:
	if chase_camera == null:
		return
	var local := global_transform.affine_inverse() * chase_camera.global_transform
	_cam_offset = local.origin
	_cam_rest_basis = local.basis.orthonormalized()
	chase_camera.top_level = true
	if chase_camera.current:
		chase_camera.clear_current(true)
	_snap_chase_camera()


func _update_chase_camera(delta: float) -> void:
	var t := 1.0 - exp(-cam_smoothing * delta)
	_cam_forward = _cam_forward.slerp(_flat_forward(), t).normalized()
	var frame := Basis.looking_at(_cam_forward, Vector3.UP)
	chase_camera.global_position = chase_camera.global_position.lerp(global_position + frame * _cam_offset, t)
	chase_camera.global_basis = frame * _cam_rest_basis


func _snap_chase_camera() -> void:
	_cam_forward = _flat_forward()
	var frame := Basis.looking_at(_cam_forward, Vector3.UP)
	chase_camera.global_position = global_position + frame * _cam_offset
	chase_camera.global_basis = frame * _cam_rest_basis


func _flat_forward() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	if f.length_squared() < 0.001:
		return _cam_forward
	return f.normalized()
