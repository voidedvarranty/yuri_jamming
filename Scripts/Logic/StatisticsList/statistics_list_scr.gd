# StatisticList - container and lookup for Statistic child nodes.
#
# Runtime API (lookup id = Stat Id, or the node name lowercased):
#   get_value_of(id, "current" | "minimum" | "maximum")
#   set_value_of(id, value) / set_value_of(id, null, "minimum" | "maximum")
#   change_value_of(id, delta)            # statistic_value += delta
# Unknown ids push_error and return null.
#
# Editor: @tool so _get_property_list can mirror every child's editable properties
# as "<ChildName>/<property>" entries (editor-only usage, never stored on this node).
# _get/_set forward to the child, so edits made here persist on the children,
# undo/redo is recorded on this node, and the same works in the Remote tree at runtime.

@tool
extends Node
class_name StatisticList

# Child properties eligible for mirroring; each is shown only if the child currently exposes it in the editor.
const EDITABLE_PROPERTIES: Array[StringName] = [
	&"statistic_value",
	&"check_limits",
	&"minimum_statistic_value",
	&"maximum_statistic_value",
	&"forced_bool_value",
	&"min_length",
	&"max_length",
	&"locked",
	&"stat_id",
]

# lookup id -> Statistic.
var statistics: Dictionary = {}

func _ready() -> void:
	# Re-index on add/remove/reorder (also covers children added at runtime).
	child_order_changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	statistics.clear()
	for child in get_children():
		if child is Statistic:
			statistics[child.get_lookup_id()] = child
			_watch(child)
	# Refresh the mirrored Inspector entries.
	notify_property_list_changed()

func _watch(stat: Statistic) -> void:
	# Re-index on rename (lookup id may derive from the name) and on child property-list changes
	# (check_limits toggles min/max, stat_id / hide_in_list changes). Guarded against double connects.
	if not stat.renamed.is_connected(_rebuild):
		stat.renamed.connect(_rebuild)
	if not stat.property_list_changed.is_connected(_rebuild):
		stat.property_list_changed.connect(_rebuild)


func _get_stat(statistic_name: String) -> Statistic:
	if not statistics.has(statistic_name):
		push_error("StatisticList: unknown statistic '%s'" % statistic_name)
		return null
	return statistics[statistic_name]

func get_value_of(statistic_name: String, value_type: String = "current"):
	var stat := _get_stat(statistic_name)
	if stat == null:
		return null

	# Range queries are only valid on StatisticRanged subclasses.
	if value_type in ["maximum", "minimum"] and not ("maximum_statistic_value" in stat):
		push_error("StatisticList: '%s' has no min/max range" % statistic_name)
		return null

	match value_type:
		"maximum": return stat.maximum_statistic_value
		"minimum": return stat.minimum_statistic_value
		_: return stat.statistic_value

func change_value_of(statistic_name: String, change) -> void:
	var stat := _get_stat(statistic_name)
	if stat == null:
		return

	#if not (stat is StatisticNumber):
		#push_error("StatisticList: change_value_of only supports StatisticNumber ('%s' is %s)" % [statistic_name, stat.get_class()])
		#return

	# Uses the child's += operator, so it works for numbers and vectors; setters still clamp / honour Locked.
	stat.statistic_value += change

func set_value_of(statistic_name: String, value = null, value_type: String = "exact") -> void:
	var stat := _get_stat(statistic_name)
	if stat == null:
		return

	if value_type in ["maximum", "minimum"] and not ("maximum_statistic_value" in stat):
		push_error("StatisticList: '%s' has no min/max range" % statistic_name)
		return

	# Assigning through statistic_value runs the child's setter (limits, Locked, statistic_changed).
	match value_type:
		"maximum": stat.statistic_value = stat.maximum_statistic_value
		"minimum": stat.statistic_value = stat.minimum_statistic_value
		_: stat.statistic_value = value


func _get_property_list() -> Array[Dictionary]:
	# Category header, then one entry per mirrored property, grouped by child name via the '/' prefix.
	var props: Array[Dictionary] = []
	props.append({
		"name": "Statistics",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_CATEGORY,
	})

	for child in get_children():
		# Hidden statistics are skipped here only; they remain fully usable from code.
		if not child is Statistic or child.hide_in_list:
			continue

		# Only properties the child itself shows (PROPERTY_USAGE_EDITOR). Plain script vars such as min/max are
		# always in get_property_list() but are only editor-visible while check_limits is on.
		var child_props := {}
		for p in child.get_property_list():
			if p.usage & PROPERTY_USAGE_EDITOR:
				child_props[p.name] = p

		for prop_name in EDITABLE_PROPERTIES:
			if not child_props.has(prop_name):
				continue
			# Copy the child's type/hint, rename to '<Child>/<prop>', and mark editor-only so it isn't serialized here.
			var p: Dictionary = child_props[prop_name].duplicate()
			p.name = "%s/%s" % [child.name, prop_name]
			p.usage = PROPERTY_USAGE_EDITOR

			# Float values with active limits get a range slider.
			if prop_name == &"statistic_value" and child.check_limits \
					and typeof(child.get(prop_name)) == TYPE_FLOAT \
					and "minimum_statistic_value" in child:
				p.hint = PROPERTY_HINT_RANGE
				p.hint_string = "%s,%s,0.001" % [child.minimum_statistic_value, child.maximum_statistic_value]

			props.append(p)

	return props

# Returning null / false means 'not ours', letting normal property handling continue.
func _get(property: StringName):
	var target := _resolve(property)
	if target.is_empty():
		return null
	return target[0].get(target[1])

func _set(property: StringName, value) -> bool:
	var target := _resolve(property)
	if target.is_empty():
		return false
	target[0].set(target[1], value)
	return true

# Delegate the revert arrow to the child's own default.
func _property_can_revert(property: StringName) -> bool:
	var target := _resolve(property)
	if target.is_empty():
		return false
	return target[0].property_can_revert(target[1])

func _property_get_revert(property: StringName):
	var target := _resolve(property)
	if target.is_empty():
		return null
	return target[0].property_get_revert(target[1])

# "MovementSpeed/statistic_value" -> [MovementSpeed node, &"statistic_value"], or [] if not a mirrored property.
func _resolve(property: StringName) -> Array:
	var path := String(property)
	var slash := path.find("/")
	if slash == -1:
		return []
	var child := get_node_or_null(NodePath(path.substr(0, slash)))
	if not child is Statistic:
		return []
	var prop_name := StringName(path.substr(slash + 1))
	if not prop_name in EDITABLE_PROPERTIES:
		return []
	return [child, prop_name]
