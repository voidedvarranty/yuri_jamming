class_name HoverBike
extends RigidBody3D

enum CameraMode { FIRST_PERSON, THIRD_PERSON }

@export_group("Input Actions")
@export var mount_action: StringName = &"interact"
@export var throttle_action: StringName = &"move_up"
@export var brake_action: StringName = &"move_down"
@export var left_action: StringName = &"move_left"
@export var right_action: StringName = &"move_right"
@export var boost_action: StringName = &"jump"

@export_group("Shape")
@export var body_half_length := 1.0   ## hover ray spread front/back
@export var body_half_width := 0.4    ## hover ray spread left/right
@export var ray_length_multiplier := 2.5

@export_group("Rider")
## Where the player's origin (middle of the capsule) sits, relative to the bike.
@export var seat_offset := Vector3(0, 0.5, 0.2)
@export var dismount_offset := Vector3(-1.4, 0.4, 0)
@export var mount_radius := 2.5
@export_flags_3d_physics var mount_detect_mask := 1  ## must include the player's collision layer
## Node on the rider that turns left/right for head look (PlayerCharacter uses "Neck").
@export var rider_neck_path: NodePath = ^"Neck"

@export_group("Camera")
@export var camera_mode: CameraMode = CameraMode.FIRST_PERSON
@export var max_look_yaw_degrees := 110.0
@export var cam_distance := 6.0
@export var cam_height := 2.2
@export var cam_smoothing := 6.0
@export var cam_fov := 75.0

@onready var statistic_list: StatisticList = $StatisticList
@onready var state_engine: StateEngine = $StateEngine

var rider: CharacterBody3D = null
var chase_camera: Camera3D
var base_fov := 75.0

var _rays: Array[RayCast3D] = []
var _seat: RemoteTransform3D
var _mount_area: Area3D
var _previous_camera: Camera3D

var _rider_saved_process_mode := Node.PROCESS_MODE_INHERIT
var _rider_camera: Camera3D
var _rider_neck: Node3D
var _look_yaw := 0.0
var _look_pitch := 0.0
var _mouse_sensitivity := 0.003

var _ground_normal := Vector3.UP
var _cam_forward := Vector3.FORWARD


func _ready() -> void:
	can_sleep = false
	_ensure_mount_action()
	_build_rays()
	_build_seat()
	_build_mount_area()
	_build_chase_camera()


func stat(id: String):
	return statistic_list.get_value_of(id)


func _physics_process(delta: float) -> void:
	_read_input()
	_update_hover()
	statistic_list.set_value_of("forwardspeed", linear_velocity.dot(-global_basis.z))
	_apply_stability(delta)
	if rider != null and camera_mode == CameraMode.THIRD_PERSON:
		_update_chase_camera(delta)


func _read_input() -> void:
	if rider == null:
		return
	statistic_list.set_value_of("inputdirection", Vector2(
		Input.get_axis(left_action, right_action),
		Input.get_axis(brake_action, throttle_action)
	))
	statistic_list.set_value_of("boosting", Input.is_action_pressed(boost_action))


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


func _unhandled_input(event: InputEvent) -> void:
	if rider != null and camera_mode == CameraMode.FIRST_PERSON \
			and event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var max_yaw := deg_to_rad(max_look_yaw_degrees)
		_look_yaw = clampf(_look_yaw - event.relative.x * _mouse_sensitivity, -max_yaw, max_yaw)
		_look_pitch = clampf(_look_pitch - event.relative.y * _mouse_sensitivity, deg_to_rad(-89), deg_to_rad(89))
		_apply_head_look()
		return

	if not event.is_action_pressed(mount_action):
		return

	if rider != null:
		if linear_velocity.length() <= float(stat("maxdismountspeed")):
			dismount()
			get_viewport().set_input_as_handled()
		return

	var active_cam := get_active_camera()
	if active_cam == null:
		return
	for body in _mount_area.get_overlapping_bodies():
		if body is CharacterBody3D and body.is_ancestor_of(active_cam):
			mount(body)
			get_viewport().set_input_as_handled()
			return


func mount(character: CharacterBody3D) -> void:
	rider = character
	rider.velocity = Vector3.ZERO

	_rider_saved_process_mode = rider.process_mode
	rider.process_mode = Node.PROCESS_MODE_DISABLED
	_seat.remote_path = _seat.get_path_to(rider)

	_previous_camera = get_active_camera()
	_rider_camera = _previous_camera if rider.is_ancestor_of(_previous_camera) else null
	_rider_neck = rider.get_node_or_null(rider_neck_path) as Node3D
	_look_yaw = 0.0
	_look_pitch = _rider_camera.rotation.x if _rider_camera else 0.0
	var sens = rider.get("mouse_sensitivity")
	_mouse_sensitivity = float(sens) if sens != null else 0.003
	_apply_head_look()

	if camera_mode == CameraMode.THIRD_PERSON:
		_snap_chase_camera()
		chase_camera.make_current()
	base_fov = get_active_camera().fov

	state_engine.transition_to_new_state(&"riddenstateengine")


func dismount() -> void:
	if rider == null:
		return
	state_engine.transition_to_new_state(&"parked")
	_seat.remote_path = NodePath()

	var f := _flat_forward()
	rider.global_position = _find_exit_position()
	rider.rotation = Vector3(0.0, atan2(-f.x, -f.z) + _look_yaw, 0.0)
	rider.velocity = Vector3.ZERO
	if _rider_neck:
		_rider_neck.rotation.y = 0.0

	var rider_stats = rider.get("statistic_list")
	if rider_stats is StatisticList:
		rider_stats.set_value_of("movementdirection", Vector3.ZERO)

	rider.process_mode = _rider_saved_process_mode

	if camera_mode == CameraMode.THIRD_PERSON and is_instance_valid(_previous_camera):
		_previous_camera.make_current()

	rider = null
	_rider_camera = null
	_rider_neck = null


func _apply_head_look() -> void:
	if _rider_neck:
		_rider_neck.rotation.y = _look_yaw
	if _rider_camera:
		_rider_camera.rotation.x = _look_pitch


func _find_exit_position() -> Vector3:
	var flat := Transform3D(Basis.looking_at(_flat_forward(), Vector3.UP), global_position)
	var candidates: Array[Vector3] = [
		dismount_offset,
		Vector3(-dismount_offset.x, dismount_offset.y, dismount_offset.z),
		Vector3(0, dismount_offset.y + 1.5, 0),
	]
	var space := get_world_3d().direct_space_state
	for off in candidates:
		var p: Vector3 = flat * off
		var q := PhysicsRayQueryParameters3D.create(global_position, p)
		q.exclude = [get_rid()]
		if space.intersect_ray(q).is_empty():
			return p
	return global_position + Vector3.UP * 2.0


func _ensure_mount_action() -> void:
	if InputMap.has_action(mount_action):
		return
	InputMap.add_action(mount_action)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	InputMap.action_add_event(mount_action, ev)


func _build_rays() -> void:
	for x in [-body_half_width, body_half_width]:
		for z in [-body_half_length, body_half_length]:
			var r := RayCast3D.new()
			r.position = Vector3(x, 0, z)
			add_child(r)
			_rays.append(r)


func _build_seat() -> void:
	_seat = RemoteTransform3D.new()
	_seat.name = "Seat"
	_seat.position = seat_offset
	_seat.update_scale = false
	add_child(_seat)


func _build_mount_area() -> void:
	_mount_area = Area3D.new()
	_mount_area.collision_layer = 0
	_mount_area.collision_mask = mount_detect_mask
	_mount_area.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = mount_radius
	shape.shape = sphere
	_mount_area.add_child(shape)
	add_child(_mount_area)


func _build_chase_camera() -> void:
	chase_camera = Camera3D.new()
	chase_camera.fov = cam_fov
	chase_camera.top_level = true
	add_child(chase_camera)
	_snap_chase_camera()


func _update_chase_camera(delta: float) -> void:
	var t := 1.0 - exp(-cam_smoothing * delta)
	_cam_forward = _cam_forward.slerp(_flat_forward(), t).normalized()
	var target := global_position - _cam_forward * cam_distance + Vector3.UP * cam_height
	chase_camera.global_position = chase_camera.global_position.lerp(target, t)
	chase_camera.look_at(global_position + Vector3.UP, Vector3.UP)


func _snap_chase_camera() -> void:
	_cam_forward = _flat_forward()
	chase_camera.global_position = global_position - _cam_forward * cam_distance + Vector3.UP * cam_height
	chase_camera.look_at(global_position + Vector3.UP, Vector3.UP)


func _flat_forward() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	if f.length_squared() < 0.001:
		return _cam_forward
	return f.normalized()
