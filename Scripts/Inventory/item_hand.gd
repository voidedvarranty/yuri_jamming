# ItemHand - first-person held item and inspect mode.
#
# The rig is a scene (hand_rig.tscn) placed under the player's Camera3D so it can be laid out
# in the editor relative to the view:
#   HandRig       made top_level at runtime. Copies the camera's global transform in NORMAL mode;
#                 during inspect it is pinned to the camera transform captured at the start, so
#                 rotating the camera does not drag the hand along.
#   RestPoint     Marker3D: hand transform while holding.
#   InspectPoint  Marker3D: hand transform while inspecting.
#   Hand          tweened between the two markers. Contains the arm model (replaceable).
#   Grip          item anchor, anywhere under Hand.
#   InspectPivot  child of Grip; accumulates the free inspect rotation, tweened back on exit.
#
# Inspect enter: compute where the item centre WILL be once the hand reaches InspectPoint,
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
## The hand rig (hand_rig.tscn). Leave empty to use a child named "HandRig" of the camera.
@export var rig: Node3D

@export_group("Input")
@export var inspect_action: StringName = &"inspect_item"
@export var put_away_action: StringName = &"put_away_item"
@export var drop_action: StringName = &"drop_item"

@export_group("Hand")
## Held items bigger than this (metres) are shrunk to fit the hand.
@export var max_item_size: float = 0.45

@export_group("Inspect")
@export var transition_time: float = 0.35
@export var rotate_sensitivity: float = 0.01
## Stops the player walking (and the head bobbing) while inspecting.
@export var freeze_player_while_inspecting: bool = true

var mode: Mode = Mode.NORMAL
var held_id: StringName = &""

var _player: Node
var _hand: Node3D
var _grip: Node3D
var _pivot: Node3D
var _item_node: Node3D
var _tween: Tween
# Hand transforms read from the RestPoint / InspectPoint markers.
var _rest := Transform3D.IDENTITY
var _inspect := Transform3D.IDENTITY
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

	if rig == null and camera != null:
		rig = camera.get_node_or_null("HandRig") as Node3D
	if not _setup_rig():
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		return

	if inventory != null:
		inventory.equipped_changed.connect(_on_equipped_changed)
		inventory.opened.connect(_on_inventory_opened)
		_on_equipped_changed(inventory.equipped)


func _process(_delta: float) -> void:
	if camera == null or not rig.visible:
		return
	# Updated in _process so the rig matches the camera at render rate.
	if mode == Mode.NORMAL:
		rig.global_transform = camera.global_transform
	else:
		rig.global_transform = _frozen_camera_transform


func _notification(what: int) -> void:
	# Owner disabled (e.g. mounted on the hover bike): abort inspect and hide the rig.
	if what == NOTIFICATION_DISABLED:
		_end_inspect_now()
		if rig != null:
			rig.visible = false
	elif what == NOTIFICATION_ENABLED:
		if rig != null:
			rig.visible = held_id != &""


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
	rig.global_transform = _frozen_camera_transform

	# 1. Target hand transform and the grip's offset within the hand (works for nested Grip nodes).
	var hand_end := _inspect
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
	_tween.tween_property(_hand, "position", _inspect.origin, transition_time)
	_tween.tween_property(_hand, "quaternion", _inspect.basis.get_rotation_quaternion(), transition_time)
	_tween.tween_method(_blend_camera.bind(_camera_rest, camera_target), 0.0, 1.0, transition_time)
	_tween.chain().tween_callback(func() -> void: mode = Mode.INSPECTING)


# Reverse all three motions in parallel, starting from wherever they currently are.
func stop_inspect() -> void:
	if mode != Mode.INSPECTING and mode != Mode.ENTERING:
		return
	mode = Mode.LEAVING
	_new_tween()
	_tween.tween_property(_pivot, "quaternion", Quaternion.IDENTITY, transition_time)
	_tween.tween_property(_hand, "position", _rest.origin, transition_time)
	_tween.tween_property(_hand, "quaternion", _rest.basis.get_rotation_quaternion(), transition_time)
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
	_hand.transform = _rest
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
		rig.visible = false
		return

	var node := def.instantiate()
	if node == null:
		rig.visible = false
		return
	# Display copy: no scripts, and the body is removed from the physics space (doesn't block raycasts).
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_pivot.add_child(node)
	_fit_item(node, def)
	_no_shadows(node)
	_item_node = node
	rig.visible = true


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


# Resolves the rig's nodes. Marker transforms are captured once; move the markers in the
# editor to change the hold / inspect poses.
func _setup_rig() -> bool:
	if rig == null:
		push_error("ItemHand: no hand rig. Add hand_rig.tscn under the player's camera, or set `rig`.")
		return false
	_hand = rig.get_node_or_null("Hand") as Node3D
	var rest_point := rig.get_node_or_null("RestPoint") as Node3D
	var inspect_point := rig.get_node_or_null("InspectPoint") as Node3D
	if _hand == null or rest_point == null or inspect_point == null:
		push_error("ItemHand: the rig needs Hand, RestPoint and InspectPoint nodes.")
		return false
	_grip = _hand.find_child("Grip", true, false) as Node3D
	if _grip == null:
		push_error("ItemHand: no node named Grip under the rig's Hand.")
		return false
	_pivot = _grip.get_node_or_null("InspectPivot") as Node3D
	if _pivot == null:
		push_error("ItemHand: Grip needs an InspectPivot child.")
		return false

	_rest = rest_point.transform
	_inspect = inspect_point.transform
	_hand.transform = _rest
	# The rig sits under the camera in the editor for layout; at runtime it is positioned manually.
	rig.top_level = true
	rig.visible = false
	return true


func _degrees_to_radians(degrees: Vector3) -> Vector3:
	return Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
