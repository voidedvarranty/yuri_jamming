class_name Inventory
extends Node

signal changed
signal item_added(item_id: StringName, amount: int)
signal item_removed(item_id: StringName, amount: int)
signal item_used(item_id: StringName)
signal item_crafted(item_id: StringName, amount: int)
signal item_dropped(item_id: StringName, node: Node3D)
signal equipped_changed(item_id: StringName)
signal opened
signal closed

## Player statistics changed by items' use effects. Leave empty to use the
## "StatisticList" node of the player this inventory belongs to.
@export var statistic_list: StatisticList
## Items the player starts with (item scene -> amount).
@export var starting_items: Dictionary[PackedScene, int] = {}
## How far in front of the camera dropped items appear.
@export var drop_distance: float = 1.2

var carried: Dictionary = {}
var on_mat: Dictionary = {}
var slot_order: Array[StringName] = []
var unseen: Dictionary = {}
var is_open := false
var equipped: StringName = &""


func _ready() -> void:
	ensure_action(&"inventory", KEY_I)
	ensure_action(&"interact", KEY_E)
	ensure_action(&"drop_item", KEY_G)

	ItemDatabase.ensure_loaded()
	changed.connect(_check_equipped)

	if statistic_list == null and get_parent() != null:
		statistic_list = get_parent().get_node_or_null("StatisticList") as StatisticList

	for scene in starting_items:
		add_item(ItemDatabase.id_for_scene(scene), starting_items[scene], false)


func get_definition(id: StringName) -> ItemDefinition:
	return ItemDatabase.get_item(id)


func count(id: StringName) -> int:
	return int(carried.get(id, 0))


func count_on_mat(id: StringName) -> int:
	return int(on_mat.get(id, 0))


func total(id: StringName) -> int:
	return count(id) + count_on_mat(id)


func has_item(id: StringName, amount: int = 1) -> bool:
	return count(id) >= amount


func space_for(id: StringName) -> int:
	var def := get_definition(id)
	if def == null:
		return 0
	if not def.has_carry_limit():
		return 1_000_000
	return maxi(def.max_carry - total(id), 0)


func is_full(id: StringName) -> bool:
	return space_for(id) <= 0


func add_item(id: StringName, amount: int = 1, mark_as_new: bool = true) -> int:
	if get_definition(id) == null:
		push_warning("Inventory: unknown item '%s'" % id)
		return 0
	var added := mini(amount, space_for(id))
	if added <= 0:
		return 0
	carried[id] = count(id) + added
	_give_slot(id)
	if mark_as_new:
		unseen[id] = true
	item_added.emit(id, added)
	changed.emit()
	return added


func remove_item(id: StringName, amount: int = 1) -> int:
	var removed := mini(amount, count(id))
	if removed <= 0:
		return 0
	carried[id] = count(id) - removed
	if carried[id] <= 0:
		carried.erase(id)
	item_removed.emit(id, removed)
	changed.emit()
	return removed


func pick_up(item: InventoryItem) -> bool:
	if item == null or not item.can_pick_up:
		return false
	var def := ItemDatabase.register_world_item(item)
	if add_item(def.id, 1) == 0:
		return false
	item.get_parent().queue_free()
	return true


func drop_item(id: StringName, amount: int = 1) -> int:
	var def := get_definition(id)
	if def == null:
		return 0
	var dropped := 0
	for i in mini(amount, count(id)):
		var node := def.instantiate()
		if node == null:
			break
		_get_world_parent().add_child(node)
		node.global_position = _get_drop_position() + Vector3(randf_range(-0.15, 0.15), 0.05 * i, randf_range(-0.15, 0.15))
		node.rotation.y = randf() * TAU
		dropped += 1
		item_dropped.emit(id, node)
	if dropped > 0:
		remove_item(id, dropped)
	return dropped


func use_item(id: StringName) -> bool:
	var def := get_definition(id)
	if def == null or not def.is_usable() or count(id) <= 0:
		return false
	if statistic_list != null:
		for stat_name in def.use_effects:
			if statistic_list.statistics.has(stat_name):
				statistic_list.change_value_of(stat_name, def.use_effects[stat_name])
	if def.consume_on_use:
		remove_item(id, 1)
	item_used.emit(id)
	return true


func equip(id: StringName) -> bool:
	var def := get_definition(id)
	if def == null or not def.can_hold or total(id) <= 0:
		return false
	if equipped != id:
		equipped = id
		equipped_changed.emit(id)
	return true


func unequip() -> void:
	if equipped == &"":
		return
	equipped = &""
	equipped_changed.emit(&"")


func is_equipped(id: StringName) -> bool:
	return equipped != &"" and equipped == id


func _check_equipped() -> void:
	if equipped != &"" and total(equipped) <= 0:
		unequip()


func move_to_mat(id: StringName, amount: int = 1) -> int:
	var moved := mini(amount, count(id))
	if moved <= 0:
		return 0
	carried[id] = count(id) - moved
	if carried[id] <= 0:
		carried.erase(id)
	on_mat[id] = count_on_mat(id) + moved
	changed.emit()
	return moved


func move_from_mat(id: StringName, amount: int = 1) -> int:
	var moved := mini(amount, count_on_mat(id))
	if moved <= 0:
		return 0
	on_mat[id] = count_on_mat(id) - moved
	if on_mat[id] <= 0:
		on_mat.erase(id)
	carried[id] = count(id) + moved
	changed.emit()
	return moved


func clear_mat() -> void:
	for id in on_mat.keys():
		move_from_mat(id, count_on_mat(id))


func get_craft_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if on_mat.is_empty():
		return options

	for recipe in ItemDatabase.get_recipes():
		var fits := true
		for id in on_mat:
			if count_on_mat(id) > int(recipe.ingredients.get(id, 0)):
				fits = false
				break
		if not fits:
			continue

		var have := 0
		for id in recipe.ingredients:
			have += mini(count_on_mat(id), int(recipe.ingredients[id]))

		options.append({
			"recipe": recipe,
			"progress": float(have) / float(recipe.total_needed),
			"ready": have == recipe.total_needed,
			"can_carry": _can_carry_result(recipe),
		})

	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["progress"] > b["progress"])
	return options


func get_ready_option() -> Dictionary:
	for option in get_craft_options():
		if option["ready"]:
			return option
	return {}


func craft() -> bool:
	var option := get_ready_option()
	if option.is_empty() or not option["can_carry"]:
		return false
	var recipe: ItemDatabase.Recipe = option["recipe"]

	for id in recipe.ingredients:
		on_mat[id] = count_on_mat(id) - int(recipe.ingredients[id])
		if on_mat[id] <= 0:
			on_mat.erase(id)

	on_mat[recipe.result_id] = count_on_mat(recipe.result_id) + recipe.result_count
	_give_slot(recipe.result_id)
	unseen[recipe.result_id] = true

	item_crafted.emit(recipe.result_id, recipe.result_count)
	changed.emit()
	return true


func _can_carry_result(recipe: ItemDatabase.Recipe) -> bool:
	var def := get_definition(recipe.result_id)
	if def == null:
		return false
	if not def.has_carry_limit():
		return true
	var used_up := int(recipe.ingredients.get(recipe.result_id, 0))
	return total(recipe.result_id) - used_up + recipe.result_count <= def.max_carry


func get_save_data() -> Dictionary:
	clear_mat()
	return {"carried": carried.duplicate(), "slot_order": slot_order.duplicate(), "equipped": String(equipped)}


func load_save_data(data: Dictionary) -> void:
	carried = (data.get("carried", {}) as Dictionary).duplicate()
	on_mat.clear()
	slot_order.clear()
	for id in data.get("slot_order", []):
		slot_order.append(StringName(id))
	changed.emit()
	var saved_equipped := StringName(data.get("equipped", ""))
	if saved_equipped != &"":
		equip(saved_equipped)
	else:
		unequip()


func _give_slot(id: StringName) -> void:
	if not slot_order.has(id):
		slot_order.append(id)


func _get_world_parent() -> Node:
	var scene := get_tree().current_scene
	if scene != null:
		return scene
	return get_tree().root


func _get_drop_position() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position - cam.global_basis.z * drop_distance
	var parent := get_parent() as Node3D
	if parent != null:
		return parent.global_position + Vector3.UP
	return Vector3.ZERO


static func ensure_action(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)
