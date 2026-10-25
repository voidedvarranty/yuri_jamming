extends State

enum CameraMode { FIRST_PERSON, THIRD_PERSON }

@export var interact_action: StringName = &"interact"
@export var throttle_action: StringName = &"move_up"
@export var brake_action: StringName = &"move_down"
@export var left_action: StringName = &"move_left"
@export var right_action: StringName = &"move_right"
@export var boost_action: StringName = &"jump"
##Switch between first person and the vehicle's chase camera. Empty = no switching key.
@export var toggle_camera_action: StringName = &""

@export var camera_mode: CameraMode = CameraMode.FIRST_PERSON
@export var max_look_yaw_degrees := 110.0
##How far away the player can be when looking at a vehicle to get on it (metres)
@export var mount_reach := 3.0
##Nodes switched off while riding (inventory, grab stick...)
@export var disable_while_riding: Array[Node] = []

var _neck: Node3D
var _collision: CollisionShape3D
var _saved_modes: Array[Node.ProcessMode] = []


func setup(injected_context: Node) -> void:
	super(injected_context)
	_neck = context.get_node_or_null("Neck") as Node3D
	_collision = context.get_node_or_null("CollisionShape3D") as CollisionShape3D


func _unhandled_input(event: InputEvent) -> void:
	if context == null:
		return
	if context.vehicle == null:
		if event.is_action_pressed(interact_action):
			var bike := _find_vehicle()
			if bike != null:
				get_viewport().set_input_as_handled()
				context.vehicle = bike
				transitioned.emit("riding")
		return

	if event is InputEventMouseMotion and camera_mode == CameraMode.FIRST_PERSON \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var max_yaw := deg_to_rad(max_look_yaw_degrees)
		var max_pitch := deg_to_rad(context._stat("maxlookangle", 89.0))
		if _neck != null:
			_neck.rotation.y = clampf(_neck.rotation.y - event.relative.x * context.mouse_sensitivity, -max_yaw, max_yaw)
		context.camera.rotation.x = clampf(context.camera.rotation.x - event.relative.y * context.mouse_sensitivity, -max_pitch, max_pitch)
	elif event.is_action_pressed(interact_action):
		get_viewport().set_input_as_handled()
		if context.vehicle.can_dismount():
			_get_off()
	elif toggle_camera_action != &"" and InputMap.has_action(toggle_camera_action) and event.is_action_pressed(toggle_camera_action):
		get_viewport().set_input_as_handled()
		camera_mode = CameraMode.THIRD_PERSON if camera_mode == CameraMode.FIRST_PERSON else CameraMode.FIRST_PERSON
		_apply_camera()


func enter() -> void:
	var bike: HoverBike = context.vehicle
	if bike == null:
		return
	context.velocity = Vector3.ZERO
	if _collision != null:
		_collision.disabled = true
	_saved_modes.clear()
	for node in disable_while_riding:
		if node == null:
			_saved_modes.append(Node.PROCESS_MODE_INHERIT)
			continue
		if node.has_method("drop"):
			node.drop()
		_saved_modes.append(node.process_mode)
		node.process_mode = Node.PROCESS_MODE_DISABLED
	_apply_camera()
	bike.mount(context)


func physics_update(_delta: float) -> void:
	var bike: HoverBike = context.vehicle
	if bike == null:
		return
	bike.drive(
		Input.get_axis(left_action, right_action),
		Input.get_axis(brake_action, throttle_action),
		Input.is_action_pressed(boost_action)
	)


func exit() -> void:
	var bike: HoverBike = context.vehicle
	if bike == null:
		return
	bike.drive(0.0, 0.0, false)
	bike.dismount()
	context.camera.make_current()

	var look_yaw := _neck.rotation.y if _neck != null else 0.0
	context.global_position = bike.get_exit_position()
	context.rotation = Vector3(0.0, bike.get_heading_yaw() + look_yaw, 0.0)
	context.velocity = Vector3.ZERO
	if _neck != null:
		_neck.rotation.y = 0.0
	context.statistic_list.set_value_of("movementdirection", Vector3.ZERO)

	if _collision != null:
		_collision.disabled = false
	for i in disable_while_riding.size():
		var node := disable_while_riding[i]
		if node != null and i < _saved_modes.size():
			node.process_mode = _saved_modes[i]
	context.vehicle = null


func _get_off() -> void:
	context.is_in_air = false


func _apply_camera() -> void:
	var bike: HoverBike = context.vehicle
	if camera_mode == CameraMode.THIRD_PERSON and bike != null and bike.chase_camera != null:
		bike.chase_camera.make_current()
	else:
		context.camera.make_current()


func _find_vehicle() -> HoverBike:
	var cam: Camera3D = context.camera
	var from := cam.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * mount_reach)
	query.exclude = [context.get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var node: Node = hit["collider"]
	while node != null and not node is HoverBike:
		node = node.get_parent()
	var bike := node as HoverBike
	if bike != null and bike.can_mount(context):
		return bike
	return null
