extends CharacterBody3D

@onready var statistic_list: StatisticList = $StatisticList
@onready var player_main_state_engine: StateEngine = $StateEngine
@onready var grab_range_ray_cast_3d: RayCast3D = $Neck/Head/Camera3D/GrabRangeRayCast3D
@onready var head: Node3D = $Neck/Head
@onready var camera: Camera3D = $Neck/Head/Camera3D
@onready var head_bob: HeadBob = $HeadBob

var mouse_sensitivity: float:
	get:
		return _stat("mousesensitivity", 0.003)

var is_in_air: bool = false:
	set(new_value):
		if new_value:
			player_main_state_engine.transition_to_new_state("inairstateengine")
		else:
			player_main_state_engine.transition_to_new_state("normalstateengine")
			statistic_list.set_value_of("jumpstaken", 0.0)
		is_in_air = new_value


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotation.x -= event.relative.y * mouse_sensitivity


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	statistic_list.set_value_of("inputdirection", input)
	var falling_speed: float = statistic_list.get_value_of("movementdirection").y
	if is_on_floor() and falling_speed < 0.0:
		falling_speed = 0.0
	statistic_list.set_value_of("movementdirection", (transform.basis * Vector3(input.x, 0, input.y)).normalized() + Vector3(0, falling_speed, 0))

	if statistic_list.get_value_of("jumpstaken") < statistic_list.get_value_of("jumpstaken", "maximum") and Input.is_action_just_pressed("jump"):
		statistic_list.change_value_of("jumpstaken", 1)
		statistic_list.change_value_of("movementdirection", Vector3(0, statistic_list.get_value_of("jumpheight"), 0))

	if not is_on_floor():
		statistic_list.change_value_of("movementdirection", Vector3(0, -_stat("gravity", 6.0) * delta, 0))
		if is_in_air == false:
			is_in_air = true

	var max_look := deg_to_rad(_stat("maxlookangle", 89.0))
	camera.rotation.x = clamp(camera.rotation.x, -max_look, max_look)

	var speed: float = statistic_list.get_value_of("movementspeed")
	if is_sprinting():
		speed *= _stat("sprintmultiplier", 1.0)

	var movement: Vector3 = statistic_list.get_value_of("movementdirection")
	if movement != Vector3.ZERO:
		velocity.x = movement.x * speed
		velocity.y = movement.y
		velocity.z = movement.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()


func is_sprinting() -> bool:
	return statistic_list.statistics.has("issprinting") and statistic_list.get_value_of("issprinting")


func _stat(stat_name: String, fallback: float) -> float:
	if statistic_list != null and statistic_list.statistics.has(stat_name):
		return float(statistic_list.get_value_of(stat_name))
	return fallback
