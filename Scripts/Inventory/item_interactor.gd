# ItemInteractor - world pickup (interact action), centre crosshair and on-screen prompt.
#
# Target selection (_find_item), evaluated every physics tick:
#   1. Exact: a ray from the active camera; if it hits an item, that item wins.
#   2. Forgiving: a capsule ("tube") of radius PickupRadius along the same ray. Candidates are scored
#      by perpendicular distance from the aim line; anything farther than the ray's blocking hit
#      (+0.3 m) is rejected, so items can't be grabbed through walls.
# Reach and radius come from the player's PickupReach / PickupRadius statistics when present.
#
# The HUD (crosshair + prompt label) lives in the scene; assign it via `crosshair` / `prompt`.
# HUD is hidden while paused (inventory/pause menu), while the owner is disabled (hover bike),
# and while ItemHand is inspecting.

class_name ItemInteractor
extends Node

@export var inventory: Inventory
## Optional: no picking things up while inspecting the held item.
@export var hand: ItemHand
@export var interact_action: StringName = &"interact"
## How far the player can reach, in metres (overridden by the PickupReach statistic).
@export var reach: float = 2.5
## How far from the crosshair an item can be and still count (overridden by PickupRadius).
@export var pickup_radius: float = 0.25
@export_flags_3d_physics var collision_mask: int = 0xFFFFFFFF
@export var show_prompt: bool = true
@export var show_crosshair: bool = true

@export_group("HUD")
@export var crosshair: Crosshair
@export var prompt: Label

@export_group("Sounds")
@export var pickup_sound: AudioStream
@export var full_sound: AudioStream

var looked_at: InventoryItem

var _prompt: Label
var _crosshair: Crosshair
var _message_timer := 0.0
# Reused query shape (resized per tick) to avoid allocating every frame.
var _search_shape := CapsuleShape3D.new()


func _ready() -> void:
	Inventory.ensure_action(interact_action, KEY_E)
	if inventory == null:
		inventory = get_parent() as Inventory
	if inventory != null:
		# Hide immediately on open; NOTIFICATION_PAUSED follows when the tree pauses.
		inventory.opened.connect(_hide_hud)
	_crosshair = crosshair
	_prompt = prompt
	if _crosshair == null or _prompt == null:
		push_warning("ItemInteractor: crosshair / prompt not assigned; pickups work without a HUD.")
	_hide_hud()


func _physics_process(delta: float) -> void:
	# No pickups or HUD while inspecting (the camera is aimed at the held item).
	if hand != null and hand.is_inspecting():
		looked_at = null
		_hide_hud()
		return
	looked_at = _find_item()
	# Re-shown every active tick, which also restores it after pause/disable ends.
	if _crosshair != null:
		_crosshair.visible = show_crosshair
		_crosshair.highlighted = looked_at != null
	# A temporary message (e.g. 'Can't carry more') holds the prompt until it expires.
	if _message_timer > 0.0:
		_message_timer -= delta
		return
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(interact_action):
		return
	if looked_at == null or not is_instance_valid(looked_at) or inventory == null:
		return
	get_viewport().set_input_as_handled()

	# Resolve the definition before pick_up(), which frees the world node on success.
	var def := ItemDatabase.register_world_item(looked_at)
	if inventory.pick_up(looked_at):
		_play(pickup_sound)
		looked_at = null
		if _crosshair != null:
			_crosshair.highlighted = false
		_update_prompt()
	else:
		_play(full_sound)
		_show_message("Can't carry more %s" % def.display_name)


func _notification(what: int) -> void:
	# There is no matching 'show' here: the next active physics tick restores the HUD.
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_DISABLED:
		_hide_hud()


func _find_item() -> InventoryItem:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return null
	var max_reach := _stat("pickupreach", reach)
	var radius := _stat("pickupradius", pickup_radius)
	var from := cam.global_position
	var direction := (-cam.global_basis.z).normalized()
	var space := cam.get_world_3d().direct_space_state

	# Exclude the player's own body from both queries.
	var exclude: Array[RID] = []
	var body := _get_player_body()
	if body != null:
		exclude.append(body.get_rid())

	# Step 1: exact hit. A non-item hit becomes the occlusion distance for step 2.
	var ray := PhysicsRayQueryParameters3D.create(from, from + direction * max_reach, collision_mask, exclude)
	var hit := space.intersect_ray(ray)
	var blocked_at := INF
	if not hit.is_empty():
		var direct := InventoryItem.find_on(hit["collider"])
		if direct != null and direct.can_pick_up:
			return direct
		blocked_at = from.distance_to(hit["position"])

	if radius <= 0.0:
		return null

	# Step 2: capsule centred halfway along the ray, long axis aligned with the aim direction.
	_search_shape.radius = radius
	_search_shape.height = maxf(max_reach, radius * 2.0 + 0.01)
	# Build an orthonormal basis with Y = aim direction (capsules are Y-aligned).
	# Fall back to RIGHT as the helper axis when looking almost straight up/down.
	var side := direction.cross(Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT).normalized()
	var tube_basis := Basis(side, direction, side.cross(direction))
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _search_shape
	query.transform = Transform3D(tube_basis, from + direction * max_reach * 0.5)
	query.collision_mask = collision_mask
	query.exclude = exclude

	var best: InventoryItem = null
	var best_distance := INF
	# Score by distance from the aim line, using the item root's origin.
	for result in space.intersect_shape(query, 16):
		var item := InventoryItem.find_on(result["collider"])
		if item == null or not item.can_pick_up or item.get_item_root() == null:
			continue
		var to_item := item.get_item_root().global_position - from
		var along := to_item.dot(direction)
		if along <= 0.0 or along > max_reach + radius:
			continue
		# Behind whatever the exact ray hit -> occluded. 0.3 m slack lets items lying on the hit floor count.
		if along > blocked_at + 0.3:
			continue
		var off_aim := (to_item - direction * along).length()
		if off_aim < best_distance:
			best_distance = off_aim
			best = item
	return best


func _stat(stat_name: String, fallback: float) -> float:
	if inventory != null and inventory.statistic_list != null and inventory.statistic_list.statistics.has(stat_name):
		return float(inventory.statistic_list.get_value_of(stat_name))
	return fallback


func _get_player_body() -> CollisionObject3D:
	var node: Node = inventory if inventory != null else self
	while node != null:
		if node is CollisionObject3D:
			return node
		node = node.get_parent()
	return null


func _update_prompt() -> void:
	if _prompt == null:
		return
	if not show_prompt or looked_at == null or not is_instance_valid(looked_at) or inventory == null:
		_prompt.visible = false
		return
	var def := ItemDatabase.register_world_item(looked_at)
	var text := "[%s] Take %s" % [action_key_text(interact_action), def.display_name]
	if def.has_carry_limit():
		text += "  %d/%d" % [inventory.total(def.id), def.max_carry]
		# Full items show a non-actionable prompt instead of the key hint.
		if inventory.is_full(def.id):
			text = "%s  (can't carry more)" % def.display_name
	_prompt.text = text
	_prompt.visible = true


func _show_message(text: String) -> void:
	if _prompt == null:
		return
	_prompt.text = text
	_prompt.visible = true
	_message_timer = 1.2


func _hide_hud() -> void:
	if _prompt != null:
		_prompt.visible = false
	if _crosshair != null:
		_crosshair.visible = false
		_crosshair.highlighted = false


func _play(sound: AudioStream) -> void:
	if sound == null:
		return
	var sfx := get_node_or_null("/root/SfxPlayer")
	if sfx != null and sfx.has_method("play"):
		sfx.play(sound)


# First key/mouse binding of an action as display text; used by all prompts and hints.
static func action_key_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key: InputEventKey = event
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return OS.get_keycode_string(code)
		if event is InputEventMouseButton:
			match (event as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:
					return "LMB"
				MOUSE_BUTTON_RIGHT:
					return "RMB"
			return "Mouse"
	return "?"
