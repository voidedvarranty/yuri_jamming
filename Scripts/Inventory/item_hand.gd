# ItemHand - first-person held item and inspect mode.
#
# Node chain (built at runtime): HandRig -> Hand -> Grip -> InspectPivot -> item instance.
#   HandRig  copies the camera's global transform in NORMAL mode. During inspect it is pinned
#            to the camera transform captured at the start, so rotating the camera does not
#            drag the hand along (the camera never "chases" the moving hand).
#   Hand     tweened between rest_offset and inspect_offset.
#   Grip     item anchor (a node named "Grip" inside hand_scene if provided).
#   Pivot    accumulates the free inspect rotation; tweened back to identity on exit.
#
# Inspect enter: compute where the item centre WILL be once the hand reaches inspect_offset,
# derive the camera rotation that centres that point, then tween hand + camera in parallel.
# Inspect exit: tween pivot, hand and camera back together. The player's physics is
# suspended meanwhile (stops movement, pitch clamping and head bob), and mouse motion is
# consumed in _input so the player's own mouse look never sees it.

class_name ItemHand
extends Node

# ENTERING/LEAVING are tween phases; input that toggles inspect is ignored during them.
enum Mode { NORMAL, ENTERING, INSPECTING, LEAVING }

@export var inventory: Inventory
## Leave empty to use the first Camera3D found in the player.
@export var camera: Camera3D
## Your own hand/arm model (optional). Add a Node3D called "Grip" where the item should sit.
## Leave empty for a simple placeholder arm.
@export var hand_scene: PackedScene

@export_group("Input")
@export var inspect_action: StringName = &"inspect_item"
@export var put_away_action: StringName = &"put_away_item"
@export var drop_action: StringName = &"drop_item"

@export_group("Hand")
## Where the hand rests, relative to the camera (x = right, y = up, -z = forward).
@export var rest_offset := Vector3(0.28, -0.26, -0.5)
@export var rest_rotation_degrees := Vector3(0.0, -8.0, 0.0)
## Held items bigger than this (metres) are shrunk to fit the hand.
@export var max_item_size: float = 0.45
@export var hand_color := Color(0.87, 0.68, 0.54)

@export_group("Inspect")
## Where the hand goes while inspecting - "a bit to the centre". The camera turns
## the rest of the way so the item ends up in the middle of the screen.
@export var inspect_offset := Vector3(0.12, -0.13, -0.42)
@export var inspect_rotation_degrees := Vector3(0.0, 0.0, 0.0)
@export var transition_time: float = 0.35
@export var rotate_sensitivity: float = 0.01
## Stops the player walking (and the head bobbing) while inspecting.
@export var freeze_player_while_inspecting: bool = true

var mode: Mode = Mode.NORMAL
var held_id: StringName = &""

var _player: Node
var _rig: Node3D
var _hand: Node3D
var _grip: Node3D
var _pivot: Node3D
var _item_node: Node3D
var _tween: Tween
# Rig anchor during inspect, and the camera rotation to restore on exit.
var _frozen_camera_transform := Transform3D.IDENTITY
var _camera_rest := Quaternion.IDENTITY


func _ready() -> void:
	Inventory.ensure_action(inspect_action, KEY_F)
	Inventory.ensure_action(put_away_action, KEY_X)
	Inventory.ensure_action(drop_action, KEY_G)

	if inventory == null:
		inventory = get_parent() as Inventory
	_player = inventory.get_parent() if inventory != null else get_parent()
	if camera == null and _player != null:
		# Default camera: first Camera3D under the player.
		for found in _player.find_children("*", "Camera3D", true, false):
			camera = found
			break

	_build_rig()

	if inventory != null:
		inventory.equipped_changed.connect(_on_equipped_changed)
		inventory.opened.connect(_on_inventory_opened)
		_on_equipped_changed(inventory.equipped)


func _process(_delta: float) -> void:
	if camera == null or not _rig.visible:
		return
	# Updated in _process so the rig matches the camera at render rate.
	if mode == Mode.NORMAL:
		_rig.global_transform = camera.global_transform
	else:
		_rig.global_transform = _frozen_camera_transform


func _notification(what: int) -> void:
	# Owner disabled (e.g. mounted on the hover bike): abort inspect and hide the rig.
	if what == NOTIFICATION_DISABLED:
		_end_inspect_now()
		if _rig != null:
			_rig.visible = false
	elif what == NOTIFICATION_ENABLED:
		if _rig != null:
			_rig.visible = held_id != &""


func _input(event: InputEvent) -> void:
	# _input runs before _unhandled_input, so consuming mouse motion here blocks the player's look.
	if mode == Mode.NORMAL or inventory == null or inventory.is_open:
		return
	if event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
		if mode == Mode.INSPECTING:
			_spin_item((event as InputEventMouseMotion).relative)
	elif mode == Mode.INSPECTING and (event.is_action_pressed(inspect_action) or _is_escape(event)):
		get_viewport().set_input_as_handled()
		stop_inspect()


# NORMAL mode only: inspect / put away / drop for the held item.
func _unhandled_input(event: InputEvent) -> void:
	if inventory == null or inventory.is_open or mode != Mode.NORMAL or held_id == &"":
		return
	if event.is_action_pressed(inspect_action):
		get_viewport().set_input_as_handled()
		start_inspect()
	elif event.is_action_pressed(put_away_action):
		get_viewport().set_input_as_handled()
		inventory.unequip()
	elif event.is_action_pressed(drop_action):
		get_viewport().set_input_as_handled()
		inventory.drop_item(held_id, 1)


func _is_escape(event: InputEvent) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE


func start_inspect() -> void:
	if mode != Mode.NORMAL or held_id == &"" or camera == null:
		return
	var body := _player as CharacterBody3D
	# Disallow inspect mid-air: suspending physics would leave the player hanging.
	if freeze_player_while_inspecting and body != null and not body.is_on_floor():
		return

	mode = Mode.ENTERING
	if freeze_player_while_inspecting and _player != null:
		# Only the player script's tick is suspended; its child nodes (state engine, HeadBob) keep processing,
		# and HeadBob checks is_physics_processing() to hold still.
		_player.set_physics_process(false)

	_frozen_camera_transform = camera.global_transform
	_camera_rest = camera.quaternion
	_rig.global_transform = _frozen_camera_transform

	# 1. Target hand transform and the grip's offset within the hand (works for nested Grip nodes).
	var hand_end := Transform3D(Basis.from_euler(_degrees_to_radians(inspect_rotation_degrees)), inspect_offset)
	var grip_in_hand := _hand.global_transform.affine_inverse() * _grip.global_transform
	# Item centre in grip/pivot space (pivot rotation is identity in NORMAL mode).
	var item_center_local := Vector3.ZERO
	if _item_node != null:
		item_center_local = _aabb_in_pivot(_item_node).get_center()
	# World-space point where the item centre will end up.
	var item_end := _frozen_camera_transform * hand_end * grip_in_hand * item_center_local

	# 2. Camera rotation (in its parent's space) that looks straight at that point.
	var camera_parent := camera.get_parent() as Node3D
	var target_local := camera_parent.global_transform.affine_inverse() * item_end
	var camera_target := Basis.looking_at((target_local - camera.position).normalized(), Vector3.UP).get_rotation_quaternion()

	# 3. Parallel tweens; mode switches to INSPECTING when they finish.
	_new_tween()
	_tween.tween_property(_hand, "position", inspect_offset, transition_time)
	_tween.tween_property(_hand, "quaternion", Quaternion.from_euler(_degrees_to_radians(inspect_rotation_degrees)), transition_time)
	_tween.tween_method(_blend_camera.bind(_camera_rest, camera_target), 0.0, 1.0, transition_time)
	_tween.chain().tween_callback(func() -> void: mode = Mode.INSPECTING)


# Reverse all three motions in parallel, starting from wherever they currently are.
func stop_inspect() -> void:
	if mode != Mode.INSPECTING and mode != Mode.ENTERING:
		return
	mode = Mode.LEAVING
	_new_tween()
	_tween.tween_property(_pivot, "quaternion", Quaternion.IDENTITY, transition_time)
	_tween.tween_property(_hand, "position", rest_offset, transition_time)
	_tween.tween_property(_hand, "quaternion", Quaternion.from_euler(_degrees_to_radians(rest_rotation_degrees)), transition_time)
	_tween.tween_method(_blend_camera.bind(camera.quaternion, _camera_rest), 0.0, 1.0, transition_time)
	_tween.chain().tween_callback(_finish_inspect)


func is_inspecting() -> bool:
	return mode != Mode.NORMAL


func _finish_inspect() -> void:
	mode = Mode.NORMAL
	if freeze_player_while_inspecting and _player != null:
		_player.set_physics_process(true)


# Immediate reset without tweens, used when the inventory opens or the held item changes.
func _end_inspect_now() -> void:
	if mode == Mode.NORMAL:
		return
	if _tween != null:
		_tween.kill()
	if camera != null:
		camera.quaternion = _camera_rest
	_pivot.quaternion = Quaternion.IDENTITY
	_hand.position = rest_offset
	_hand.quaternion = Quaternion.from_euler(_degrees_to_radians(rest_rotation_degrees))
	_finish_inspect()


# Quaternion slerp avoids Euler wrap-around issues.
func _blend_camera(weight: float, from: Quaternion, to: Quaternion) -> void:
	if camera != null:
		camera.quaternion = from.slerp(to, weight)


func _spin_item(relative: Vector2) -> void:
	var view := camera.global_basis.orthonormalized()
	# Rotate around the camera's screen axes in world space, unrestricted (full 360 on both axes).
	var spin := Basis(view.y, relative.x * rotate_sensitivity) * Basis(view.x, relative.y * rotate_sensitivity)
	_pivot.global_basis = (spin * _pivot.global_basis).orthonormalized()


func _new_tween() -> void:
	if _tween != null:
		_tween.kill()
	# Tweens are bound to this node, so they pause with the tree (inventory) and stop if the player is disabled.
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_equipped_changed(id: StringName) -> void:
	_end_inspect_now()
	if _item_node != null:
		_item_node.queue_free()
		_item_node = null
	held_id = id
	_pivot.quaternion = Quaternion.IDENTITY

	var def: ItemDefinition = null
	if id != &"":
		def = inventory.get_definition(id)
	if def == null:
		held_id = &""
		_rig.visible = false
		return

	var node := def.instantiate()
	if node == null:
		_rig.visible = false
		return
	# Display copy: no scripts, and the body is removed from the physics space (doesn't block raycasts).
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_pivot.add_child(node)
	_fit_item(node, def)
	_no_shadows(node)
	_item_node = node
	_rig.visible = true


func _on_inventory_opened() -> void:
	_end_inspect_now()


func _fit_item(node: Node3D, def: ItemDefinition) -> void:
	var basis := Basis.from_euler(_degrees_to_radians(def.hand_rotation))
	node.transform = Transform3D(basis, Vector3.ZERO)
	# Only shrink items larger than max_item_size, then apply the per-item hand_scale and centre on the grip.
	var box := _aabb_in_pivot(node)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var fit := 1.0
	if longest > max_item_size and longest > 0.0001:
		fit = max_item_size / longest
	node.transform = Transform3D(basis.scaled(Vector3.ONE * fit * def.hand_scale), Vector3.ZERO)
	box = _aabb_in_pivot(node)
	node.position = -box.get_center() + def.hand_offset


func _aabb_in_pivot(node: Node3D) -> AABB:
	# AABB of all GeometryInstance3D descendants, expressed in pivot space.
	var to_pivot := _pivot.global_transform.affine_inverse()
	var result := AABB()
	var has_any := false
	var nodes: Array[Node] = node.find_children("*", "GeometryInstance3D", true, false)
	if node is GeometryInstance3D:
		nodes.append(node)
	for found in nodes:
		var geometry := found as GeometryInstance3D
		var box: AABB = (to_pivot * geometry.global_transform) * geometry.get_aabb()
		if has_any:
			result = result.merge(box)
		else:
			result = box
			has_any = true
	return result


func _no_shadows(node: Node) -> void:
	for found in node.find_children("*", "GeometryInstance3D", true, false):
		(found as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "HandRig"
	_rig.top_level = true
	_rig.visible = false
	add_child(_rig)

	_hand = Node3D.new()
	_hand.name = "Hand"
	_hand.position = rest_offset
	_hand.rotation = _degrees_to_radians(rest_rotation_degrees)
	_rig.add_child(_hand)

	var model: Node3D = null
	if hand_scene != null:
		model = hand_scene.instantiate() as Node3D
	# Placeholder arm when no hand_scene is set (or it isn't a Node3D).
	if model == null:
		model = _make_placeholder_arm()
	_hand.add_child(model)
	_no_shadows(model)

	# Use the model's own Grip node if it has one.
	_grip = model.find_child("Grip", true, false) as Node3D
	if _grip == null:
		_grip = Node3D.new()
		_grip.name = "Grip"
		_hand.add_child(_grip)

	_pivot = Node3D.new()
	_pivot.name = "InspectPivot"
	_grip.add_child(_pivot)


func _make_placeholder_arm() -> Node3D:
	var arm := Node3D.new()
	arm.name = "PlaceholderArm"
	var material := StandardMaterial3D.new()
	material.albedo_color = hand_color
	material.roughness = 0.9

	var fist_mesh := BoxMesh.new()
	fist_mesh.size = Vector3(0.09, 0.08, 0.1)
	fist_mesh.material = material
	var fist := MeshInstance3D.new()
	fist.mesh = fist_mesh
	fist.position = Vector3(0.0, -0.05, 0.02)
	arm.add_child(fist)

	var forearm_mesh := BoxMesh.new()
	forearm_mesh.size = Vector3(0.065, 0.065, 0.34)
	forearm_mesh.material = material
	var forearm := MeshInstance3D.new()
	forearm.mesh = forearm_mesh
	forearm.position = Vector3(0.02, -0.07, 0.22)
	arm.add_child(forearm)
	return arm


func _degrees_to_radians(degrees: Vector3) -> Vector3:
	return Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
