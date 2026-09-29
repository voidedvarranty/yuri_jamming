class_name ItemDatabase
extends RefCounted

const ITEM_FOLDERS: Array[String] = ["res://Scenes/Items"]


class Recipe:
	var result_id: StringName
	var result_count: int = 1
	var ingredients: Dictionary = {}
	var total_needed: int = 0


static var _items: Dictionary = {}
static var _path_to_id: Dictionary = {}
static var _recipes: Array = []
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var found_recipes: Array[Dictionary] = []

	for folder in ITEM_FOLDERS:
		for path in _find_scenes(folder):
			var packed := load(path) as PackedScene
			if packed == null:
				continue
			var root := packed.instantiate()
			var item := get_item_node(root)
			if item != null:
				var def := _register(item, packed)
				for recipe_node in _get_recipe_nodes(item):
					found_recipes.append({
						"result": def.id,
						"count": recipe_node.result_count,
						"ingredients": recipe_node.ingredients.duplicate(),
					})
			root.free()

	for data in found_recipes:
		var recipe := Recipe.new()
		recipe.result_id = data["result"]
		recipe.result_count = data["count"]
		var valid := true
		var ingredients: Dictionary = data["ingredients"]
		for ingredient_scene in ingredients:
			var ingredient_id := id_for_scene(ingredient_scene)
			var amount := int(ingredients[ingredient_scene])
			if ingredient_id == &"" or amount <= 0:
				push_warning("ItemDatabase: a recipe for '%s' has an ingredient that isn't an item scene." % recipe.result_id)
				valid = false
				break
			recipe.ingredients[ingredient_id] = int(recipe.ingredients.get(ingredient_id, 0)) + amount
			recipe.total_needed += amount
		if valid and recipe.total_needed > 0:
			_recipes.append(recipe)


static func get_item(id: StringName) -> ItemDefinition:
	ensure_loaded()
	return _items.get(id)


static func get_all_items() -> Array:
	ensure_loaded()
	return _items.values()


static func get_recipes() -> Array:
	ensure_loaded()
	return _recipes


static func id_for_scene(packed: PackedScene) -> StringName:
	if packed == null:
		return &""
	if _path_to_id.has(packed.resource_path):
		return _path_to_id[packed.resource_path]
	var root := packed.instantiate()
	var item := get_item_node(root)
	var id: StringName = &""
	if item != null:
		id = _register(item, packed).id
	root.free()
	return id


static func register_world_item(item: InventoryItem) -> ItemDefinition:
	ensure_loaded()
	var id := item.get_item_id()
	if _items.has(id):
		return _items[id]

	var def := ItemDefinition.from_item(item)
	var root := item.get_parent()
	if root.scene_file_path != "":
		def.scene = load(root.scene_file_path) as PackedScene
		_path_to_id[root.scene_file_path] = id
	if def.scene == null:
		def.template = root.duplicate() as Node3D
	_items[id] = def
	return def


static func get_item_node(root: Node) -> InventoryItem:
	if root == null:
		return null
	for child in root.get_children():
		if child is InventoryItem:
			return child
	return null


static func _get_recipe_nodes(item: InventoryItem) -> Array[CraftingRecipe]:
	var result: Array[CraftingRecipe] = []
	for child in item.get_children():
		if child is CraftingRecipe:
			result.append(child)
	return result


static func _register(item: InventoryItem, packed: PackedScene) -> ItemDefinition:
	var id := item.get_item_id()
	_path_to_id[packed.resource_path] = id
	if _items.has(id):
		return _items[id]
	var def := ItemDefinition.from_item(item)
	def.scene = packed
	_items[id] = def
	return def


static func _find_scenes(folder: String) -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(folder):
		return result
	for entry in ResourceLoader.list_directory(folder):
		var path := folder.path_join(entry)
		if entry.ends_with("/"):
			result.append_array(_find_scenes(path.trim_suffix("/")))
		elif entry.ends_with(".tscn") or entry.ends_with(".scn"):
			result.append(path)
	return result
