extends Node

# InputSettings handles rebindable controls.
# Default controls come from Project Settings > Input Map.
# Saved custom controls come from GameData.

signal bindings_changed
signal rebind_started(action_name: String, slot_name: String)
signal rebind_finished(action_name: String, slot_name: String)
signal rebind_cancelled

enum BindingType {
	KEY,
	MOUSE_BUTTON,
	JOY_BUTTON,
	JOY_AXIS,
}

const SLOT_KEYBOARD_MOUSE: String = "keyboard_mouse"
const SLOT_CONTROLLER: String = "controller"
const INPUT_SLOTS: Array[String] = [
	SLOT_KEYBOARD_MOUSE,
	SLOT_CONTROLLER,
]

@export_range(0.1, 1.0, 0.01) var controller_axis_deadzone: float = 0.55
@export var ignore_frames_after_starting_rebind: int = 2
@export var ignore_mouse_click_that_started_rebind: bool = true

var is_rebinding: bool = false
var rebind_action_name: String = ""
var rebind_slot_name: String = ""
var rebind_ignore_frames: int = 0
var is_waiting_for_mouse_release_before_binding: bool = false
var is_pushing_bindings_to_game_data: bool = false

# Only labels. The actual default controls should be set in Project Settings > Input Map.
var action_definitions: Array[Dictionary] = [
	{"action": "move_left", "label": "Move left"},
	{"action": "move_right", "label": "Move right"},
	{"action": "move_up", "label": "Move up"},
	{"action": "move_down", "label": "Move down"},
	{"action": "action_primary", "label": "Primary action"},
	{"action": "action_secondary", "label": "Secondary action"},
	{"action": "pause", "label": "Pause"},
]

# Stored at startup before saved bindings are applied. Reset controls uses this.
var default_bindings: Dictionary = {}


# Sets up input actions, remembers defaults, then applies saved bindings.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not GameData.input_bindings_changed.is_connected(_on_game_data_input_bindings_changed):
		GameData.input_bindings_changed.connect(_on_game_data_input_bindings_changed)

	_ensure_actions_exist()
	_store_default_bindings_from_input_map()

	if GameData.input_bindings.is_empty():
		apply_bindings(default_bindings.duplicate(true), true)
	else:
		apply_bindings(GameData.input_bindings, true)


# Counts down the small delay after starting a rebind.
func _process(_delta: float) -> void:
	if rebind_ignore_frames > 0:
		rebind_ignore_frames -= 1


# Captures the next valid input while rebinding.
func _input(event: InputEvent) -> void:
	if not is_rebinding:
		return

	if rebind_ignore_frames > 0:
		return

	if _should_cancel_rebind(event):
		cancel_rebind()
		get_viewport().set_input_as_handled()
		return

	if _should_ignore_mouse_event_until_release(event):
		get_viewport().set_input_as_handled()
		return

	var binding: Dictionary = _event_to_binding(event, rebind_slot_name)

	if binding.is_empty():
		return

	_apply_rebind(rebind_action_name, rebind_slot_name, binding)
	get_viewport().set_input_as_handled()


# Gives UI scripts the action list.
func get_action_definitions() -> Array[Dictionary]:
	return action_definitions


# Gets the display label for an action.
func get_action_label(action_name: String) -> String:
	for action_definition: Dictionary in action_definitions:
		if String(action_definition.get("action", "")) == action_name:
			return String(action_definition.get("label", action_name))

	return action_name


# Starts rebinding one action slot.
func start_rebind(action_name: String, slot_name: String) -> void:
	if is_rebinding:
		cancel_rebind()

	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	is_rebinding = true
	rebind_action_name = action_name
	rebind_slot_name = slot_name
	rebind_ignore_frames = ignore_frames_after_starting_rebind
	is_waiting_for_mouse_release_before_binding = false

	if ignore_mouse_click_that_started_rebind and slot_name == SLOT_KEYBOARD_MOUSE:
		is_waiting_for_mouse_release_before_binding = _any_mouse_button_pressed()

	rebind_started.emit(action_name, slot_name)


# Cancels the current rebind.
func cancel_rebind() -> void:
	_clear_rebind_state()
	rebind_cancelled.emit()


# Restores the original Input Map defaults.
func reset_to_defaults(should_clear_saved_bindings: bool = true) -> void:
	apply_bindings(default_bindings.duplicate(true), true)

	if should_clear_saved_bindings:
		is_pushing_bindings_to_game_data = true
		GameData.clear_input_bindings()
		is_pushing_bindings_to_game_data = false


# Applies a full bindings dictionary to InputMap.
func apply_bindings(bindings: Dictionary, should_emit_signal: bool = true) -> void:
	_ensure_actions_exist()

	for action_definition: Dictionary in action_definitions:
		var action_name: String = String(action_definition.get("action", ""))

		if action_name.is_empty():
			continue

		InputMap.action_erase_events(action_name)

		for slot_name: String in INPUT_SLOTS:
			var binding: Dictionary = _get_binding_from_table(bindings, action_name, slot_name)

			if binding.is_empty():
				binding = _get_binding_from_table(default_bindings, action_name, slot_name)

			_add_binding_to_input_map(action_name, binding)

	if should_emit_signal:
		bindings_changed.emit()


# Reads the current InputMap into a saveable dictionary.
func get_current_bindings() -> Dictionary:
	var current_bindings: Dictionary = {}

	for action_definition: Dictionary in action_definitions:
		var action_name: String = String(action_definition.get("action", ""))

		if action_name.is_empty():
			continue

		current_bindings[action_name] = {}

		for slot_name: String in INPUT_SLOTS:
			current_bindings[action_name][slot_name] = get_action_slot_binding(
				action_name, slot_name
			)

	return current_bindings


# Gets the current binding for one action slot.
func get_action_slot_binding(action_name: String, slot_name: String) -> Dictionary:
	if not InputMap.has_action(action_name):
		return {}

	for input_event: InputEvent in InputMap.action_get_events(action_name):
		if _event_belongs_to_slot(input_event, slot_name):
			return _input_event_to_binding(input_event)

	return {}


# Gets readable text for one action slot.
func get_action_slot_text(action_name: String, slot_name: String) -> String:
	var binding: Dictionary = get_action_slot_binding(action_name, slot_name)

	if binding.is_empty():
		return "Unbound"

	return _binding_to_display_text(binding)


# Reacts when GameData changes input bindings.
func _on_game_data_input_bindings_changed(new_input_bindings: Dictionary) -> void:
	if is_pushing_bindings_to_game_data:
		return

	if new_input_bindings.is_empty():
		apply_bindings(default_bindings.duplicate(true), true)
	else:
		apply_bindings(new_input_bindings, true)


# Stores the original Project Settings > Input Map controls.
func _store_default_bindings_from_input_map() -> void:
	default_bindings.clear()

	for action_definition: Dictionary in action_definitions:
		var action_name: String = String(action_definition.get("action", ""))

		if action_name.is_empty():
			continue

		default_bindings[action_name] = {}

		for slot_name: String in INPUT_SLOTS:
			default_bindings[action_name][slot_name] = get_action_slot_binding(
				action_name, slot_name
			)


# Gets one valid binding from a bindings dictionary.
func _get_binding_from_table(
	bindings: Dictionary, action_name: String, slot_name: String
) -> Dictionary:
	if not bindings.has(action_name):
		return {}

	if not (bindings[action_name] is Dictionary):
		return {}

	var action_bindings: Dictionary = bindings[action_name] as Dictionary

	if not action_bindings.has(slot_name):
		return {}

	if not (action_bindings[slot_name] is Dictionary):
		return {}

	var binding: Dictionary = (action_bindings[slot_name] as Dictionary).duplicate(true)

	if _get_binding_type(binding) == -1:
		return {}

	return binding


# Makes sure every action exists in the InputMap.
func _ensure_actions_exist() -> void:
	for action_definition: Dictionary in action_definitions:
		var action_name: String = String(action_definition.get("action", ""))

		if action_name.is_empty():
			continue

		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)


# Converts a live input event into a saveable binding.
func _event_to_binding(event: InputEvent, slot_name: String) -> Dictionary:
	var binding: Dictionary = {}

	if slot_name == SLOT_KEYBOARD_MOUSE:
		if event is InputEventKey:
			var key_event: InputEventKey = event as InputEventKey

			if key_event.pressed and not key_event.echo:
				binding = {
					"type": BindingType.KEY,
					"code": _get_key_identity(key_event),
				}

		elif event is InputEventMouseButton:
			var mouse_event: InputEventMouseButton = event as InputEventMouseButton

			if mouse_event.pressed:
				binding = {
					"type": BindingType.MOUSE_BUTTON,
					"button": int(mouse_event.button_index),
				}

	elif slot_name == SLOT_CONTROLLER:
		if event is InputEventJoypadButton:
			var button_event: InputEventJoypadButton = event as InputEventJoypadButton

			if button_event.pressed:
				binding = {
					"type": BindingType.JOY_BUTTON,
					"button": int(button_event.button_index),
				}

		elif event is InputEventJoypadMotion:
			var motion_event: InputEventJoypadMotion = event as InputEventJoypadMotion

			if absf(motion_event.axis_value) >= controller_axis_deadzone:
				binding = {
					"type": BindingType.JOY_AXIS,
					"axis": int(motion_event.axis),
					"direction": signf(motion_event.axis_value),
				}

	return binding

# Converts an InputMap event into a saveable binding.
func _input_event_to_binding(input_event: InputEvent) -> Dictionary:
	if input_event is InputEventKey:
		var key_event: InputEventKey = input_event as InputEventKey

		return {
			"type": BindingType.KEY,
			"code": _get_key_identity(key_event),
		}

	if input_event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = input_event as InputEventMouseButton

		return {
			"type": BindingType.MOUSE_BUTTON,
			"button": int(mouse_event.button_index),
		}

	if input_event is InputEventJoypadButton:
		var button_event: InputEventJoypadButton = input_event as InputEventJoypadButton

		return {
			"type": BindingType.JOY_BUTTON,
			"button": int(button_event.button_index),
		}

	if input_event is InputEventJoypadMotion:
		var motion_event: InputEventJoypadMotion = input_event as InputEventJoypadMotion

		return {
			"type": BindingType.JOY_AXIS,
			"axis": int(motion_event.axis),
			"direction": signf(motion_event.axis_value),
		}

	return {}


# Converts a saved binding into an InputEvent.
func _binding_to_input_event(binding: Dictionary) -> InputEvent:
	match _get_binding_type(binding):
		BindingType.KEY:
			var key_event: InputEventKey = InputEventKey.new()
			var keycode: Key = int(binding.get("code", KEY_NONE)) as Key
			key_event.keycode = keycode
			key_event.physical_keycode = keycode
			key_event.pressed = true
			key_event.device = -1
			return key_event

		BindingType.MOUSE_BUTTON:
			var mouse_event: InputEventMouseButton = InputEventMouseButton.new()
			var mouse_button: MouseButton = (
				int(binding.get("button", MOUSE_BUTTON_LEFT)) as MouseButton
			)
			mouse_event.button_index = mouse_button
			mouse_event.pressed = true
			mouse_event.device = -1
			return mouse_event

		BindingType.JOY_BUTTON:
			var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
			var joy_button: JoyButton = int(binding.get("button", JOY_BUTTON_A)) as JoyButton
			button_event.button_index = joy_button
			button_event.pressed = true
			button_event.device = -1
			return button_event

		BindingType.JOY_AXIS:
			var motion_event: InputEventJoypadMotion = InputEventJoypadMotion.new()
			var joy_axis: JoyAxis = int(binding.get("axis", JOY_AXIS_LEFT_X)) as JoyAxis
			motion_event.axis = joy_axis
			motion_event.axis_value = signf(float(binding.get("direction", 1.0)))
			motion_event.device = -1
			return motion_event

	return null


# Gets the binding type.
func _get_binding_type(binding: Dictionary) -> int:
	if binding.is_empty():
		return -1

	var raw_type: Variant = binding.get("type", -1)

	if raw_type is int:
		return int(raw_type)

	return -1


# Checks whether an InputEvent belongs to keyboard/mouse or controller.
func _event_belongs_to_slot(input_event: InputEvent, slot_name: String) -> bool:
	if slot_name == SLOT_KEYBOARD_MOUSE:
		return input_event is InputEventKey or input_event is InputEventMouseButton

	if slot_name == SLOT_CONTROLLER:
		return input_event is InputEventJoypadButton or input_event is InputEventJoypadMotion

	return false


# Uses physical keycode where possible, so WASD stays position-based.
func _get_key_identity(key_event: InputEventKey) -> int:
	if key_event.physical_keycode != KEY_NONE:
		return int(key_event.physical_keycode)

	return int(key_event.keycode)


# Finishes a rebind and saves it.
func _apply_rebind(action_name: String, slot_name: String, binding: Dictionary) -> void:
	_remove_same_slot_events_from_action(action_name, slot_name)
	_remove_duplicate_binding_from_all_actions(binding)
	_add_binding_to_input_map(action_name, binding)

	_clear_rebind_state()

	is_pushing_bindings_to_game_data = true
	GameData.set_input_bindings(get_current_bindings())
	is_pushing_bindings_to_game_data = false

	bindings_changed.emit()
	rebind_finished.emit(action_name, slot_name)


# Clears the active rebind state.
func _clear_rebind_state() -> void:
	is_rebinding = false
	rebind_action_name = ""
	rebind_slot_name = ""
	rebind_ignore_frames = 0
	is_waiting_for_mouse_release_before_binding = false


# Adds one binding to the InputMap.
func _add_binding_to_input_map(action_name: String, binding: Dictionary) -> void:
	if binding.is_empty():
		return

	var input_event: InputEvent = _binding_to_input_event(binding)

	if input_event == null:
		return

	InputMap.action_add_event(action_name, input_event)


# Removes the old keyboard/mouse or controller binding from one action.
func _remove_same_slot_events_from_action(action_name: String, slot_name: String) -> void:
	if not InputMap.has_action(action_name):
		return

	for existing_event: InputEvent in InputMap.action_get_events(action_name):
		if _event_belongs_to_slot(existing_event, slot_name):
			InputMap.action_erase_event(action_name, existing_event)


# Removes the same binding from all actions.
func _remove_duplicate_binding_from_all_actions(binding: Dictionary) -> void:
	for action_definition: Dictionary in action_definitions:
		var action_name: String = String(action_definition.get("action", ""))

		if action_name.is_empty():
			continue

		if not InputMap.has_action(action_name):
			continue

		for existing_event: InputEvent in InputMap.action_get_events(action_name):
			var existing_binding: Dictionary = _input_event_to_binding(existing_event)

			if _bindings_are_same(existing_binding, binding):
				InputMap.action_erase_event(action_name, existing_event)


# Checks if two bindings use the same input.
func _bindings_are_same(first_binding: Dictionary, second_binding: Dictionary) -> bool:
	var first_type: int = _get_binding_type(first_binding)
	var second_type: int = _get_binding_type(second_binding)

	if first_type == -1 or first_type != second_type:
		return false

	match first_type:
		BindingType.KEY:
			return (
				int(first_binding.get("code", KEY_NONE))
				== int(second_binding.get("code", KEY_NONE))
			)

		BindingType.MOUSE_BUTTON:
			return int(first_binding.get("button", -1)) == int(second_binding.get("button", -2))

		BindingType.JOY_BUTTON:
			return int(first_binding.get("button", -1)) == int(second_binding.get("button", -2))

		BindingType.JOY_AXIS:
			return (
				int(first_binding.get("axis", -1)) == int(second_binding.get("axis", -2))
				and (
					signf(float(first_binding.get("direction", 0.0)))
					== signf(float(second_binding.get("direction", 0.0)))
				)
			)

	return false


# Ignores the mouse click that opened the rebind button.
func _should_ignore_mouse_event_until_release(event: InputEvent) -> bool:
	if not is_waiting_for_mouse_release_before_binding:
		return false

	if not (event is InputEventMouseButton):
		return false

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton

	if not mouse_event.pressed:
		if not _any_mouse_button_pressed():
			is_waiting_for_mouse_release_before_binding = false

		return true

	return true


# Checks if any common mouse button is pressed.
func _any_mouse_button_pressed() -> bool:
	return (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	)


# Lets Escape / B cancel rebinding, unless those buttons are being rebound.
func _should_cancel_rebind(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey

		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			return rebind_action_name != "pause"

	if event is InputEventJoypadButton:
		var button_event: InputEventJoypadButton = event as InputEventJoypadButton

		if button_event.pressed and button_event.button_index == JOY_BUTTON_B:
			return rebind_action_name != "action_secondary"

	return false


# Converts a binding into readable text for the settings UI.
func _binding_to_display_text(binding: Dictionary) -> String:
	match _get_binding_type(binding):
		BindingType.KEY:
			return OS.get_keycode_string(int(binding.get("code", KEY_NONE)))

		BindingType.MOUSE_BUTTON:
			return _mouse_button_to_text(int(binding.get("button", MOUSE_BUTTON_LEFT)))

		BindingType.JOY_BUTTON:
			return _joypad_button_to_text(int(binding.get("button", JOY_BUTTON_A)))

		BindingType.JOY_AXIS:
			return _joypad_axis_to_text(
				int(binding.get("axis", JOY_AXIS_LEFT_X)), float(binding.get("direction", 1.0))
			)

	return "Unknown"


# Converts mouse button IDs to readable text.
func _mouse_button_to_text(button_index: int) -> String:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return "Mouse left"
		MOUSE_BUTTON_RIGHT:
			return "Mouse right"
		MOUSE_BUTTON_MIDDLE:
			return "Mouse middle"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel down"

	return "Mouse %s" % button_index


# Converts controller button IDs to readable text.
func _joypad_button_to_text(button_index: int) -> String:
	var button_text: String = ""

	match button_index:
		JOY_BUTTON_A:
			button_text = "A / Cross"
		JOY_BUTTON_B:
			button_text = "B / Circle"
		JOY_BUTTON_X:
			button_text = "X / Square"
		JOY_BUTTON_Y:
			button_text = "Y / Triangle"
		JOY_BUTTON_BACK:
			button_text = "Back"
		JOY_BUTTON_GUIDE:
			button_text = "Guide"
		JOY_BUTTON_START:
			button_text = "Start"
		JOY_BUTTON_LEFT_STICK:
			button_text = "L Stick"
		JOY_BUTTON_RIGHT_STICK:
			button_text = "R Stick"
		JOY_BUTTON_LEFT_SHOULDER:
			button_text = "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			button_text = "RB"
		JOY_BUTTON_DPAD_UP:
			button_text = "D-Pad Up"
		JOY_BUTTON_DPAD_DOWN:
			button_text = "D-Pad Down"
		JOY_BUTTON_DPAD_LEFT:
			button_text = "D-Pad Left"
		JOY_BUTTON_DPAD_RIGHT:
			button_text = "D-Pad Right"
		_:
			button_text = "Button %s" % button_index

	return button_text

# Converts controller axis IDs to readable text.
func _joypad_axis_to_text(axis: int, direction: float) -> String:
	var axis_text: String = ""

	match axis:
		JOY_AXIS_LEFT_X:
			axis_text = "Left Stick Left" if direction < 0.0 else "Left Stick Right"

		JOY_AXIS_LEFT_Y:
			axis_text = "Left Stick Up" if direction < 0.0 else "Left Stick Down"

		JOY_AXIS_RIGHT_X:
			axis_text = "Right Stick Left" if direction < 0.0 else "Right Stick Right"

		JOY_AXIS_RIGHT_Y:
			axis_text = "Right Stick Up" if direction < 0.0 else "Right Stick Down"

		JOY_AXIS_TRIGGER_LEFT:
			axis_text = "Left Trigger"

		JOY_AXIS_TRIGGER_RIGHT:
			axis_text = "Right Trigger"

		_:
			axis_text = "Axis %s %s" % [axis, signf(direction)]

	return axis_text
