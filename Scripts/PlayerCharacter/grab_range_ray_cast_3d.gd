extends RayCast3D

@export var pickup_point: Marker3D
@export var pickup_group: StringName = &"CanBePickedUp"
## How strongly the object is pulled to the hold point.
@export var carry_strength: float = 12.0
@export var max_carry_speed: float = 8.0
## Let go if the object gets this far from the hold point (stuck behind something).
@export var break_distance: float = 2.5
@export var throw_force: float = 6.0

var currently_picked_up_object: RigidBody3D

var _player: CollisionObject3D
var _saved_gravity_scale := 1.0
var _saved_angular_damp := 0.0


func _ready() -> void:
	if pickup_point == null:
		pickup_point = get_node_or_null("HoldPositionMarker3D") as Marker3D
	var node := get_parent()
	while node != null:
		if node is CollisionObject3D:
			_player = node
			add_exception(_player)
			break
		node = node.get_parent()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("action_primary"):
		if currently_picked_up_object != null:
			drop()
		else:
			try_grab()
	elif event.is_action_pressed("action_secondary") and currently_picked_up_object != null:
		throw()


func _physics_process(_delta: float) -> void:
	if currently_picked_up_object == null:
		return
	if not is_instance_valid(currently_picked_up_object) or not currently_picked_up_object.is_inside_tree():
		currently_picked_up_object = null
		return

	var body := currently_picked_up_object
	var to_target := pickup_point.global_position - body.global_position
	if to_target.length() > break_distance:
		drop()
		return
	body.linear_velocity = (to_target * carry_strength).limit_length(max_carry_speed)
	body.angular_velocity = body.angular_velocity.lerp(Vector3.ZERO, 0.2)


func try_grab() -> bool:
	if pickup_point == null:
		return false
	force_raycast_update()
	var body := get_collider() as RigidBody3D
	if body == null or not body.is_in_group(pickup_group):
		return false

	currently_picked_up_object = body
	_saved_gravity_scale = body.gravity_scale
	_saved_angular_damp = body.angular_damp
	body.gravity_scale = 0.0
	body.angular_damp = 5.0
	body.sleeping = false
	if _player != null:
		body.add_collision_exception_with(_player)
	return true


func drop() -> void:
	var body := currently_picked_up_object
	currently_picked_up_object = null
	if body == null or not is_instance_valid(body):
		return
	body.gravity_scale = _saved_gravity_scale
	body.angular_damp = _saved_angular_damp
	if _player != null:
		body.remove_collision_exception_with(_player)


func throw() -> void:
	var body := currently_picked_up_object
	drop()
	if body != null and is_instance_valid(body):
		body.apply_central_impulse(-global_basis.z * throw_force * body.mass)
