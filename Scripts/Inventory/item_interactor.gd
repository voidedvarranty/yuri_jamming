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
@export var prompt_font_size: int = 10

@export_group("Sounds")
@export var pickup_sound: AudioStream
@export var full_sound: AudioStream

var looked_at: InventoryItem

var _layer: CanvasLayer
var _prompt: Label
var _crosshair: Crosshair
var _message_timer := 0.0
var _search_shape := CapsuleShape3D.new()


func _ready() -> void:
	Inventory.ensure_action(interact_action, KEY_E)
	if inventory == null:
		inventory = get_parent() as Inventory
	if inventory != null:
		inventory.opened.connect(_hide_hud)
	_build_hud()


func _physics_process(delta: float) -> void:
	if hand != null and hand.is_inspecting():
		looked_at = null
		_hide_hud()
		return
	_crosshair.visible = show_crosshair

	looked_at = _find_item()
	_crosshair.highlighted = looked_at != null
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

	var def := ItemDatabase.register_world_item(looked_at)
	if inventory.pick_up(looked_at):
		_play(pickup_sound)
		looked_at = null
		_crosshair.highlighted = false
		_update_prompt()
	else:
		_play(full_sound)
		_show_message("Can't carry more %s" % def.display_name)


func _notification(what: int) -> void:
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

	var exclude: Array[RID] = []
	var body := _get_player_body()
	if body != null:
		exclude.append(body.get_rid())

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

	_search_shape.radius = radius
	_search_shape.height = maxf(max_reach, radius * 2.0 + 0.01)
	var side := direction.cross(Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT).normalized()
	var tube_basis := Basis(side, direction, side.cross(direction))
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _search_shape
	query.transform = Transform3D(tube_basis, from + direction * max_reach * 0.5)
	query.collision_mask = collision_mask
	query.exclude = exclude

	var best: InventoryItem = null
	var best_distance := INF
	for result in space.intersect_shape(query, 16):
		var item := InventoryItem.find_on(result["collider"])
		if item == null or not item.can_pick_up or item.get_item_root() == null:
			continue
		var to_item := item.get_item_root().global_position - from
		var along := to_item.dot(direction)
		if along <= 0.0 or along > max_reach + radius:
			continue
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


func _build_hud() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)

	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_crosshair = Crosshair.new()
	root.add_child(_crosshair)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.visible = false

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_prompt.add_theme_font_size_override("font_size", prompt_font_size)
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_prompt)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.position.y -= 24
	_prompt.visible = false


func _update_prompt() -> void:
	if not show_prompt or looked_at == null or not is_instance_valid(looked_at) or inventory == null:
		_prompt.visible = false
		return
	var def := ItemDatabase.register_world_item(looked_at)
	var text := "[%s] Take %s" % [action_key_text(interact_action), def.display_name]
	if def.has_carry_limit():
		text += "  %d/%d" % [inventory.total(def.id), def.max_carry]
		if inventory.is_full(def.id):
			text = "%s  (can't carry more)" % def.display_name
	_prompt.text = text
	_prompt.visible = true


func _show_message(text: String) -> void:
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
