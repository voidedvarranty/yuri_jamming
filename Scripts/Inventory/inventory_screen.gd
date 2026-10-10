# InventoryScreen - The Forest-style 3D inventory view (CanvasLayer, PROCESS_MODE_ALWAYS).
#
# Rendering: a SubViewport with its own World3D (own_world_3d, transparent background) holds a
# tarp, a crafting mat, a light and an orthographic camera. Each carried item is shown as real
# instances of its own scene (ItemDefinition.instantiate), set to PROCESS_MODE_DISABLED so they
# are display-only, auto-fitted to their slot and stacked into small piles.
#
# Layout: the tarp is a slot_columns x slot_rows grid minus the cells covered by the mat; each
# item id keeps the slot matching its index in Inventory.slot_order. The mat has its own grid
# and is re-laid out whenever the set of ids on it changes.
#
# Picking: no physics. Each model caches a world AABB, and the mouse ray from the inventory
# camera is tested against those AABBs (nearest hit wins).
#
# Sync: models are created/removed incrementally per (id, on_mat) group on Inventory.changed.
# Everything is cleared on close and rebuilt on open.
#
# Pause interplay: with pause_game_while_open, the tree is paused while open. If something else
# unpauses it (e.g. the pause menu's toggle), _process detects that and closes the screen.

class_name InventoryScreen
extends CanvasLayer

@export var inventory: Inventory

@export_group("Input")
@export var toggle_action: StringName = &"inventory"
@export var drop_action: StringName = &"drop_item"
@export var craft_action: StringName = &"jump"
## The Forest pauses in single player. Untick to keep the world running
## (the player is frozen instead).
@export var pause_game_while_open: bool = true

# World-space metres inside the inventory's own SubViewport world.
@export_group("Layout")
## Size of the tarp in metres (16:9 fits the screen best).
@export var tarp_size := Vector2(4.8, 2.7)
@export var mat_size := Vector2(1.7, 1.0)
## The tarp is split into spots; spots under the mat are skipped.
@export var slot_columns: int = 8
@export var slot_rows: int = 4
@export var mat_columns: int = 4
@export var mat_rows: int = 2
## Every model is scaled so its longest side is about this long (metres).
@export var item_fit_size: float = 0.4
## Most copies of one item shown in a pile (e.g. 30 arrows still show 10 models).
@export var max_models_per_item: int = 10
@export_range(20.0, 90.0) var camera_pitch_degrees: float = 60.0

@export_group("Look")
@export var tarp_color := Color(0.16, 0.33, 0.52)
@export var mat_color := Color(0.66, 0.55, 0.4)
@export var background_dim := Color(0, 0, 0, 0.5)
@export var hover_color := Color(1.0, 0.85, 0.25, 0.45)
@export var new_item_color := Color(1.0, 1.0, 1.0, 0.45)
@export var ui_font_size: int = 10
@export var tooltip_delay: float = 0.2

@export_group("Sounds")
@export var open_sound: AudioStream
@export var close_sound: AudioStream
@export var move_sound: AudioStream
@export var craft_sound: AudioStream
@export var use_sound: AudioStream
@export var fail_sound: AudioStream

var is_open := false


# One display instance plus its cached world AABB (for picking) and geometry list (for overlays).
class ItemModel:
	var node: Node3D
	var id: StringName
	var on_mat: bool
	var aabb: AABB
	var geometry: Array[GeometryInstance3D] = []


var _ui: Control
var _container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _items_root: Node3D
var _cog: CraftingCog
var _tooltip: PanelContainer
var _tooltip_label: Label
var _recipe_panel: PanelContainer
var _recipe_label: Label
var _hint_label: Label

# "<id>|0" = tarp pile, "<id>|1" = mat pile -> Array[ItemModel].
var _models: Dictionary = {}
var _slot_centers: Array[Vector3] = []
var _mat_centers: Array[Vector3] = []
var _slot_cell := Vector2.ONE
var _mat_cell := Vector2.ONE
# Ids on the mat in layout order; a change triggers a mat re-layout.
var _mat_layout: Array = []
var _warned_full_tarp := false

var _hovered: ItemModel
var _hover_group := ""
var _hover_time := 0.0
var _hover_material: StandardMaterial3D
var _new_material: StandardMaterial3D
var _craft_options: Array[Dictionary] = []

# Hold-to-batch state for right click (locked to the item first clicked).
var _right_held := false
var _right_timer := 0.0
var _right_repeat := 0.0
var _batch_id: StringName = &""
var _batch_from_mat := false

var _saved_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _player_saved_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _time := 0.0


func _ready() -> void:
	layer = 50
	# Must keep running while the tree is paused, and while the player (our ancestor) is disabled.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	if inventory == null:
		inventory = get_parent() as Inventory
	Inventory.ensure_action(toggle_action, KEY_I)
	Inventory.ensure_action(drop_action, KEY_G)

	_build_scene()
	_compute_layout()

	# React to data changes and crafting events from the model.
	if inventory != null:
		inventory.changed.connect(_on_inventory_changed)
		inventory.item_crafted.connect(_on_item_crafted)
	else:
		push_error("InventoryScreen needs an Inventory (make it a child of the Inventory node).")


func open() -> void:
	if is_open or inventory == null:
		return
	is_open = true
	inventory.is_open = true

	# Free the cursor for the UI; restored on close.
	_saved_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if pause_game_while_open:
		get_tree().paused = true
	else:
		_set_player_frozen(true)

	visible = true
	# Full rebuild on open: the bag may have changed while closed.
	_clear_all_models()
	_sync_all()
	_update_craft_ui()
	_play(open_sound)
	inventory.opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	inventory.is_open = false
	# Return mat items before hiding (the capacity invariant guarantees they fit).
	inventory.clear_mat()

	visible = false
	_right_held = false
	_hovered = null
	_hover_group = ""
	_tooltip.visible = false
	_clear_all_models()

	# Never leave the cursor visible in gameplay, even if it was visible when opening.
	Input.mouse_mode = _saved_mouse_mode if _saved_mouse_mode != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED
	if pause_game_while_open:
		get_tree().paused = false
	else:
		_set_player_frozen(false)

	_play(close_sound)
	inventory.closed.emit()


func _can_open() -> bool:
	# Blocked over the pause menu (tree already paused) and while the player is disabled (mounted).
	return inventory != null and not get_tree().paused and inventory.can_process()


func _set_player_frozen(frozen: bool) -> void:
	var player := inventory.get_parent()
	if player == null:
		return
	# Only used when pause_game_while_open is off: freeze the player instead of the whole tree.
	if frozen:
		_player_saved_process_mode = player.process_mode
		player.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		player.process_mode = _player_saved_process_mode


func _input(event: InputEvent) -> void:
	# Closed: only the toggle action matters. _input runs before the player's handlers, so we can consume it.
	if not is_open:
		if event.is_action_pressed(toggle_action) and _can_open():
			get_viewport().set_input_as_handled()
			open()
		return

	# Mouse buttons are read directly (not actions) and consumed so nothing behind the UI sees them.
	if event.is_action_pressed(toggle_action) or _is_escape(event):
		get_viewport().set_input_as_handled()
		close()
		return

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT:
			_right_held = mouse.pressed
			if mouse.pressed:
				_on_right_click()
			get_viewport().set_input_as_handled()
		elif mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			_on_left_click()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(drop_action):
		_on_drop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(craft_action):
		_try_craft()
		get_viewport().set_input_as_handled()


func _is_escape(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	return key.pressed and not key.echo and key.keycode == KEY_ESCAPE


func _on_right_click() -> void:
	_right_timer = 0.0
	_right_repeat = 0.0
	_batch_id = &""

	# Cog takes priority over items for both mouse buttons.
	if _cog.is_mouse_over():
		_try_craft()
		return

	var model := _pick_model()
	if model == null:
		return
	# Remember what was clicked; holding the button repeats this exact move (see _continue_batch).
	_batch_id = model.id
	_batch_from_mat = model.on_mat
	_move_one(model.id, model.on_mat)


func _continue_batch() -> void:
	if _batch_id == &"":
		return
	# Stop batching once that pile is exhausted, instead of moving whatever is under the cursor next.
	if not _move_one(_batch_id, _batch_from_mat):
		_batch_id = &""


func _move_one(id: StringName, from_mat: bool) -> bool:
	var moved := inventory.move_from_mat(id) if from_mat else inventory.move_to_mat(id)
	if moved > 0:
		_play(move_sound)
	return moved > 0


func _on_left_click() -> void:
	if _cog.is_mouse_over():
		_try_craft()
		return
	var model := _pick_model()
	if model == null or model.on_mat:
		return
	var def := inventory.get_definition(model.id)
	if def == null:
		return
	# Usable items are consumed; holdable items toggle equip, as in The Forest.
	if def.is_usable():
		if inventory.use_item(model.id):
			_play(use_sound)
	elif def.can_hold:
		if inventory.is_equipped(model.id):
			inventory.unequip()
		else:
			inventory.equip(model.id)
		_play(move_sound)


func _on_drop() -> void:
	# Drop over the mat (or nothing) returns the whole mat; over a tarp item it drops one into the world.
	if _hovered == null or _hovered.on_mat:
		if not inventory.on_mat.is_empty():
			inventory.clear_mat()
			_play(move_sound)
		return
	if inventory.drop_item(_hovered.id, 1) > 0:
		_play(move_sound)


func _try_craft() -> void:
	if inventory.craft():
		_cog.play_craft_effect()
		_play(craft_sound)
	# Ready but blocked by capacity -> failure sound.
	elif not inventory.get_ready_option().is_empty():
		_play(fail_sound)


func _process(delta: float) -> void:
	if not is_open:
		return
	# Another system unpaused the tree: treat it as a close.
	if pause_game_while_open and not get_tree().paused:
		close()
		return

	_time += delta
	_place_camera()
	_update_hover(delta)
	_position_overlay_ui()
	_update_tooltip()

	# Hold-to-batch: 0.35 s initial delay, then one move every 0.07 s.
	if _right_held:
		_right_timer += delta
		if _right_timer > 0.35:
			_right_repeat -= delta
			if _right_repeat <= 0.0:
				_right_repeat = 0.07
				_continue_batch()

	# Pulse the 'new item' overlay.
	_new_material.albedo_color.a = new_item_color.a * (0.35 + 0.65 * (0.5 + 0.5 * sin(_time * 4.0)))


func _update_hover(delta: float) -> void:
	var model := _pick_model()
	var group := "" if model == null else _group_key(model.id, model.on_mat)
	_hovered = model
	if group != _hover_group:
		_hover_group = group
		_hover_time = 0.0
		# Hovering a new item marks it as seen (stops its shine).
		if model != null and not model.on_mat and inventory.unseen.has(model.id):
			inventory.unseen.erase(model.id)
		_refresh_overlays()
	else:
		_hover_time += delta
	_cog.hovered = _cog.is_mouse_over()


func _on_inventory_changed() -> void:
	if not is_open:
		return
	_sync_all()
	_update_craft_ui()
	_refresh_overlays()


func _on_item_crafted(id: StringName, _amount: int) -> void:
	if is_open:
		call_deferred("_pop_group", _group_key(id, true))


func _sync_all() -> void:
	# Tarp: one group per known id, at its permanent slot. Ids beyond the slot count aren't shown (warns once).
	for i in inventory.slot_order.size():
		var id: StringName = inventory.slot_order[i]
		if i >= _slot_centers.size():
			if not _warned_full_tarp:
				_warned_full_tarp = true
				push_warning("InventoryScreen: more item types than spots on the tarp - raise slot_columns / slot_rows.")
			continue
		_sync_group(id, false, inventory.count(id), _slot_centers[i], _slot_cell)

	# Mat: rebuild every mat group if the set/order of ids changed, otherwise sync counts in place.
	var mat_ids: Array = inventory.on_mat.keys()
	if mat_ids != _mat_layout:
		for key in _models.keys():
			if String(key).ends_with("|1"):
				_clear_group(key)
		_mat_layout = mat_ids.duplicate()
	for j in mini(mat_ids.size(), _mat_centers.size()):
		_sync_group(mat_ids[j], true, inventory.count_on_mat(mat_ids[j]), _mat_centers[j], _mat_cell)


func _sync_group(id: StringName, on_mat: bool, amount: int, center: Vector3, cell: Vector2) -> void:
	var key := _group_key(id, on_mat)
	var list: Array = _models.get(key, [])
	# Large stacks are capped visually; the tooltip shows the real count.
	var wanted := mini(amount, max_models_per_item)
	while list.size() < wanted:
		var model := _make_model(id, on_mat, list.size(), center, cell)
		if model == null:
			break
		list.append(model)
	while list.size() > wanted:
		var old: ItemModel = list.pop_back()
		if _hovered == old:
			_hovered = null
		old.node.queue_free()
	if list.is_empty():
		_models.erase(key)
	else:
		_models[key] = list


func _make_model(id: StringName, on_mat: bool, index: int, center: Vector3, cell: Vector2) -> ItemModel:
	var def := inventory.get_definition(id)
	if def == null:
		return null
	var node := def.instantiate()
	if node == null:
		return null

	# Display copy: scripts don't run and any body is removed from physics. (_ready still runs on add_child.)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_items_root.add_child(node)

	var rot := def.inventory_rotation
	# Deterministic per-index yaw (golden angle + id hash) so piles look natural but stable between rebuilds.
	var turn := fposmod(float(index) * 2.39996 + float(absi(hash(id)) % 628) * 0.01, TAU)
	var basis := Basis(Vector3.UP, turn) * Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	node.transform = Transform3D(basis, Vector3.ZERO)

	# Uniform scale so the longest side matches the cell (or item_fit_size), then the per-item multiplier.
	var box := _visual_aabb(node)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest <= 0.0001:
		longest = 0.3
	var fit := minf(item_fit_size, minf(cell.x, cell.y) * 0.9)
	node.transform = Transform3D(basis.scaled(Vector3.ONE * (fit / longest * def.inventory_scale)), Vector3.ZERO)

	# Pile layout: 9 offsets within the cell, then additional layers stacked upward.
	var pattern: Array[Vector2] = [
		Vector2(0, 0), Vector2(-1, -0.8), Vector2(1, 0.7), Vector2(0.9, -0.9), Vector2(-0.9, 0.9),
		Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0),
	]
	var spread: Vector2 = pattern[index % pattern.size()] * cell * 0.18
	var pile_layer := floori(float(index) / float(pattern.size()))
	box = _visual_aabb(node)
	var ground := center.y + 0.004 + float(index) * 0.01 + float(pile_layer) * box.size.y * 0.6
	# Centre on the slot horizontally and rest the AABB bottom on the tarp.
	node.position = Vector3(
		center.x + spread.x - box.get_center().x,
		ground - box.position.y,
		center.z + spread.y - box.get_center().z
	)

	var model := ItemModel.new()
	model.node = node
	model.id = id
	model.on_mat = on_mat
	# Cache the final world AABB for picking; collect geometry for overlay highlighting.
	model.aabb = _visual_aabb(node)
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		model.geometry.append(child as GeometryInstance3D)
	if node is GeometryInstance3D:
		model.geometry.append(node as GeometryInstance3D)
	_apply_overlay(model)
	return model


func _visual_aabb(root: Node3D) -> AABB:
	# GeometryInstance3D only, so lights/particles with large AABBs don't inflate the bounds.
	var nodes: Array[Node] = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		nodes.append(root)
	var result := AABB()
	var has_any := false
	for node in nodes:
		var geometry := node as GeometryInstance3D
		if not geometry.is_visible_in_tree():
			continue
		var box: AABB = geometry.global_transform * geometry.get_aabb()
		if has_any:
			result = result.merge(box)
		else:
			result = box
			has_any = true
	if not has_any:
		result = AABB(root.global_position - Vector3.ONE * 0.1, Vector3.ONE * 0.2)
	return result


func _clear_group(key: String) -> void:
	for model in _models.get(key, []):
		if _hovered == model:
			_hovered = null
		if is_instance_valid(model.node):
			model.node.queue_free()
	_models.erase(key)


func _clear_all_models() -> void:
	for key in _models.keys():
		_clear_group(key)
	_models.clear()
	_mat_layout = []
	_hovered = null
	_hover_group = ""


func _pop_group(key: String) -> void:
	for model in _models.get(key, []):
		var node: Node3D = model.node
		if not is_instance_valid(node):
			continue
		# Scale-in pop for freshly crafted items (deferred until after the sync that created them).
		var full_scale := node.scale
		node.scale = full_scale * 0.4
		var tween := create_tween()
		tween.tween_property(node, "scale", full_scale, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _group_key(id: StringName, on_mat: bool) -> String:
	return "%s|%d" % [id, 1 if on_mat else 0]


func _apply_overlay(model: ItemModel) -> void:
	var overlay: Material = null
	# Hover highlight takes priority over the 'new' shine; both use material_overlay (additive, unshaded).
	if _group_key(model.id, model.on_mat) == _hover_group:
		overlay = _hover_material
	elif not model.on_mat and inventory.unseen.has(model.id):
		overlay = _new_material
	for geometry in model.geometry:
		if is_instance_valid(geometry):
			geometry.material_overlay = overlay


func _refresh_overlays() -> void:
	for list in _models.values():
		for model in list:
			_apply_overlay(model)


func _mouse_viewport_position() -> Vector2:
	var local := _container.get_local_mouse_position()
	if _container.size.x <= 0.0 or _container.size.y <= 0.0:
		return Vector2(-1, -1)
	# Container space -> SubViewport pixel space (they differ if stretch_shrink is used).
	return local * Vector2(_viewport.size) / _container.size


func _pick_model() -> ItemModel:
	var local := _container.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, _container.size).has_point(local):
		return null
	var vp_pos := _mouse_viewport_position()
	var from := _camera.project_ray_origin(vp_pos)
	var direction := _camera.project_ray_normal(vp_pos)

	var best: ItemModel = null
	var best_distance := INF
	for list in _models.values():
		for model in list:
			# Ray vs AABB per model; nearest hit along the ray wins (top of a pile).
			var hit = model.aabb.intersects_ray(from, direction)
			if hit == null:
				continue
			var distance := from.distance_to(hit)
			if distance < best_distance:
				best_distance = distance
				best = model
	return best


func _mouse_over_mat() -> bool:
	var vp_pos := _mouse_viewport_position()
	var from := _camera.project_ray_origin(vp_pos)
	var direction := _camera.project_ray_normal(vp_pos)
	if absf(direction.y) < 0.0001:
		return false
	# Intersect the mouse ray with the tarp plane (y = 0).
	var point := from + direction * (-from.y / direction.y)
	return absf(point.x) <= mat_size.x * 0.5 and absf(point.z) <= mat_size.y * 0.5


func _world_to_ui(point: Vector3) -> Vector2:
	if _viewport.size.x <= 0 or _viewport.size.y <= 0:
		return Vector2.ZERO
	var vp := _camera.unproject_position(point)
	return _container.position + vp * _container.size / Vector2(_viewport.size)


func _update_craft_ui() -> void:
	_craft_options = inventory.get_craft_options()
	if _craft_options.is_empty():
		_cog.state = CraftingCog.CogState.HIDDEN
		_recipe_label.text = ""
		return

	# Options are sorted by progress; the first one drives the cog.
	var best: Dictionary = _craft_options[0]
	if best["ready"]:
		_cog.state = CraftingCog.CogState.READY if best["can_carry"] else CraftingCog.CogState.BLOCKED
	else:
		_cog.state = CraftingCog.CogState.PARTIAL
		_cog.progress = best["progress"]

	# One line per distinct product: ready / blocked, or progress plus what's still missing.
	var lines := PackedStringArray(["Can craft:"])
	var seen := {}
	for option in _craft_options:
		var recipe: ItemDatabase.Recipe = option["recipe"]
		var def := inventory.get_definition(recipe.result_id)
		if def == null:
			continue
		var product := def.display_name
		if recipe.result_count > 1:
			product += " x%d" % recipe.result_count
		if seen.has(product):
			continue
		seen[product] = true
		if option["ready"]:
			lines.append(("> %s  (click cog)" % product) if option["can_carry"] else ("%s  (can't carry more)" % product))
		else:
			var have := roundi(float(option["progress"]) * recipe.total_needed)
			lines.append("%s  %d/%d  needs: %s" % [product, have, recipe.total_needed, _missing_text(recipe)])
	_recipe_label.text = "\n".join(lines)
	_recipe_panel.reset_size()


func _missing_text(recipe: ItemDatabase.Recipe) -> String:
	var parts := PackedStringArray()
	for id in recipe.ingredients:
		var missing := int(recipe.ingredients[id]) - inventory.count_on_mat(id)
		if missing > 0:
			var def := inventory.get_definition(id)
			var item_name := def.display_name if def != null else String(id)
			parts.append("%d %s" % [missing, item_name])
	return ", ".join(parts)


func _position_overlay_ui() -> void:
	# Cog sits just below the mat's front edge, projected into UI space every frame.
	var cog_point := _world_to_ui(Vector3(0, 0, mat_size.y * 0.5 + 0.12))
	_cog.position = cog_point - _cog.size * 0.5

	# Recipe list only while pointing at the cog or the mat, to keep the tarp readable.
	var show_list := not _craft_options.is_empty() and (_cog.is_mouse_over() or _mouse_over_mat())
	_recipe_panel.visible = show_list
	if show_list:
		var top_right := _world_to_ui(Vector3(mat_size.x * 0.5, 0, -mat_size.y * 0.5))
		var max_position := _ui.size - _recipe_panel.size
		_recipe_panel.position = Vector2(minf(top_right.x + 6.0, max_position.x), clampf(top_right.y, 0.0, max_position.y))


func _update_tooltip() -> void:
	# Tooltip after a short hover delay (0.2 s, as in The Forest); hidden over the cog.
	if _hovered == null or _hover_time < tooltip_delay or _cog.is_mouse_over():
		_tooltip.visible = false
		return
	var def := inventory.get_definition(_hovered.id)
	if def == null:
		_tooltip.visible = false
		return

	var title := def.display_name
	if def.has_carry_limit():
		title += "   %d/%d" % [inventory.total(def.id), def.max_carry]
	else:
		title += "   x%d" % inventory.total(def.id)
	if inventory.is_equipped(def.id):
		title += "   (in hand)"
	var lines := PackedStringArray([title])
	if def.description != "":
		lines.append(def.description)

	var drop_key := ItemInteractor.action_key_text(drop_action)
	var actions := PackedStringArray()
	if _hovered.on_mat:
		actions.append("RMB take back")
		actions.append("%s return all" % drop_key)
	else:
		actions.append("RMB to mat")
		if def.is_usable():
			actions.append("LMB use")
		elif def.can_hold:
			actions.append("LMB put away" if inventory.is_equipped(def.id) else "LMB hold")
		actions.append("%s drop" % drop_key)
	lines.append("   ".join(actions))

	_tooltip_label.text = "\n".join(lines)
	_tooltip.visible = true
	_tooltip.reset_size()
	# Offset from the cursor and clamped to stay on screen.
	var mouse := _ui.get_local_mouse_position() + Vector2(10, 10)
	var max_position := _ui.size - _tooltip.size
	_tooltip.position = Vector2(minf(mouse.x, max_position.x), minf(mouse.y, max_position.y))


func _build_scene() -> void:
	_ui = Control.new()
	_ui.name = "UI"
	_ui.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_ui)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = background_dim
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_container = SubViewportContainer.new()
	# stretch keeps the SubViewport size equal to the container (base resolution, pixelated like the game).
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_container)
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_viewport = SubViewport.new()
	# Separate World3D: item copies never interact with or appear in the game world.
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_container.add_child(_viewport)

	var environment := Environment.new()
	# Clear-colour background + transparent_bg lets the dimmed game show around the tarp.
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_viewport.add_child(world_environment)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, 35, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	_viewport.add_child(light)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.1
	_camera.far = 50.0
	_viewport.add_child(_camera)
	_camera.make_current()
	_place_camera()

	# Tarp border, tarp, mat (slightly raised to avoid z-fighting).
	_viewport.add_child(_make_plane(tarp_size + Vector2(0.12, 0.12), tarp_color.darkened(0.35), -0.004))
	_viewport.add_child(_make_plane(tarp_size, tarp_color, 0.0))
	_viewport.add_child(_make_plane(mat_size, mat_color, 0.002))

	_items_root = Node3D.new()
	_items_root.name = "Items"
	_viewport.add_child(_items_root)

	_hover_material = _make_overlay_material(hover_color)
	_new_material = _make_overlay_material(new_item_color)

	_cog = CraftingCog.new()
	_ui.add_child(_cog)

	_recipe_panel = _make_panel(false)
	_recipe_label = _recipe_panel.get_child(0) as Label
	_recipe_panel.visible = false
	_ui.add_child(_recipe_panel)

	_tooltip = _make_panel(true)
	_tooltip_label = _tooltip.get_child(0) as Label
	_tooltip.visible = false
	_ui.add_child(_tooltip)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", ui_font_size)
	_hint_label.add_theme_constant_override("outline_size", 4)
	_hint_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.text = "RMB: to/from mat    Cog or %s: craft    LMB: use / hold    %s: drop    %s: close" % [
		ItemInteractor.action_key_text(craft_action),
		ItemInteractor.action_key_text(drop_action),
		ItemInteractor.action_key_text(toggle_action),
	]
	_ui.add_child(_hint_label)
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_label.position.y -= 4


func _compute_layout() -> void:
	_slot_centers.clear()
	_mat_centers.clear()

	_slot_cell = Vector2(tarp_size.x / slot_columns, tarp_size.y / slot_rows)
	# Skip tarp cells that overlap the mat (shrunk by 1 cm to ignore edge-touching cells).
	var mat_rect := Rect2(-mat_size * 0.5, mat_size)
	for row in slot_rows:
		for column in slot_columns:
			var x := -tarp_size.x * 0.5 + (column + 0.5) * _slot_cell.x
			var z := -tarp_size.y * 0.5 + (row + 0.5) * _slot_cell.y
			var cell_rect := Rect2(Vector2(x, z) - _slot_cell * 0.5, _slot_cell).grow(-0.01)
			if cell_rect.intersects(mat_rect):
				continue
			_slot_centers.append(Vector3(x, 0.0, z))

	_mat_cell = Vector2(mat_size.x / mat_columns, mat_size.y / mat_rows)
	for row in mat_rows:
		for column in mat_columns:
			_mat_centers.append(Vector3(
				-mat_size.x * 0.5 + (column + 0.5) * _mat_cell.x,
				0.002,
				-mat_size.y * 0.5 + (row + 0.5) * _mat_cell.y
			))


func _place_camera() -> void:
	var pitch := deg_to_rad(camera_pitch_degrees)
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
	_camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * 10.0
	var aspect := float(_viewport.size.x) / maxf(1.0, float(_viewport.size.y))
	var needed_height := tarp_size.y * sin(pitch) + 0.4 * cos(pitch)
	# Ortho size (vertical extent) chosen so both the tilted tarp depth and the full width fit.
	_camera.size = maxf(needed_height, (tarp_size.x + 0.15) / maxf(aspect, 0.1)) * 1.06


func _make_plane(plane_size: Vector2, color: Color, height: float) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = plane_size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position.y = height
	return instance


func _make_overlay_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Additive, unshaded overlay: brightens the model without hiding its texture.
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	return material


func _make_panel(word_wrap: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.1, 0.85)
	style.border_color = Color(0.9, 0.85, 0.6, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", ui_font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if word_wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 150
	panel.add_child(label)
	return panel


func _play(sound: AudioStream) -> void:
	if sound == null:
		return
	var sfx := get_node_or_null("/root/SfxPlayer")
	if sfx == null or not sfx.has_method("play"):
		return
	# Audio players under a paused node stop; the SFX autoload must keep running while the tree is paused.
	sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	sfx.play(sound)
