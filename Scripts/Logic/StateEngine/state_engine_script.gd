extends State
class_name StateEngine

signal entered_new_state(state_name: StringName)

@export var initial_state: State

@export var actor: Node

var current_state: State:
	get:
		return _current_state

var _current_state: State
var _states: Dictionary = {}
var _is_transitioning := false

func _ready() -> void:
	
	if not is_root() and actor == null:
		actor = get_root_engine().actor
		
	await actor.ready
	
	for child in get_children():
		if child is State:
			_states[String(child.name).to_lower()] = child
			child.transitioned.connect(transition_to_new_state)
			if actor:
				child.setup(actor)

	if is_root():
		enter()

func is_root() -> bool:
	return not (get_parent() is StateEngine)

func get_root_engine() -> StateEngine:
	var engine: StateEngine = self
	
	while not engine.is_root():
		engine = engine.get_parent() as StateEngine
		
	return engine

func _process(delta: float) -> void:
	if _current_state:
		_current_state.update(delta)

func _physics_process(delta: float) -> void:
	if _current_state:
		_current_state.physics_update(delta)

func enter() -> void:
	
	if _current_state != null:
		return
		
	if initial_state == null:
		push_warning("StateEngine at %s has no initial_state assigned." % get_path())
		return
		
	if initial_state.get_parent() != self:
		push_warning("StateEngine at %s: initial_state (%s) is not a direct child of this engine." % [get_path(), initial_state.name])
		return

	_current_state = initial_state
	initial_state.enter()
	entered_new_state.emit(_current_state.name)

func exit() -> void:
	if _current_state:
		await _current_state.exit()
	_current_state = null

func transition_to_new_state(new_state_name: StringName) -> void:
	if new_state_name == &"" or _is_transitioning:
		return

	var key := String(new_state_name).to_lower()
	var new_state: State = _states.get(key)

	if new_state == null:
		push_warning("StateEngine: no state named '%s' under %s" % [new_state_name, get_path()])
		return
	if new_state == _current_state:
		return

	_is_transitioning = true

	if _current_state:
		await _current_state.exit()

	_current_state = new_state
	new_state.enter()
	entered_new_state.emit(_current_state.name)

	_is_transitioning = false

func get_current_state_name() -> StringName:
	return _current_state.name if _current_state else &""
