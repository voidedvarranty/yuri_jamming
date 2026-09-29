extends Control

# Key configuration panel.
# Builds the controls list from InputSettings, then lets the player rebind
# keyboard, mouse, and controller inputs.
# This scene assumes these unique nodes exist:
# ControlsList, RebindPromptLabel, and ResetControlsButton.

@export_group("Layout")
@export var action_label_min_width: float = 86.0
@export var binding_button_min_width: float = 82.0
@export var row_min_height: float = 22.0
@export var row_separation: int = 3

@export_group("Font")
# Makes the generated labels and buttons smaller than the current theme font.
# -2 means "2 points smaller".
@export var font_size_offset: int = -4
@export var minimum_font_size: int = 6

@export_group("Text")
@export var action_column_text: String = "Action"
@export var keyboard_column_text: String = "Keyboard"
@export var controller_column_text: String = "Pad"
@export var reset_button_text: String = "Reset controls"
@export var stop_rebind_button_text: String = "Stop rebind"
@export var waiting_for_keyboard_text: String = "Press key / mouse..."
@export var waiting_for_controller_text: String = "Press controller..."
@export var cancelled_text: String = "Cancelled"

@export_group("Behaviour")
@export var hide_prompt_when_not_rebinding: bool = true
@export var grab_focus_after_rebind: bool = true

# Stores the generated rebind buttons by action name.
var keyboard_buttons: Dictionary = {}
var controller_buttons: Dictionary = {}

# Used to return focus after rebinding.
var last_pressed_rebind_button: Button = null

@onready var controls_list: VBoxContainer = %ControlsList
@onready var rebind_prompt_label: Label = %RebindPromptLabel
@onready var reset_controls_button: Button = %ResetControlsButton


func _ready() -> void:
	rebind_prompt_label.text = ""
	rebind_prompt_label.visible = not hide_prompt_when_not_rebinding
	_apply_smaller_font(rebind_prompt_label)

	reset_controls_button.text = reset_button_text
	reset_controls_button.focus_mode = Control.FOCUS_ALL
	_apply_smaller_font(reset_controls_button)
	reset_controls_button.pressed.connect(_on_reset_controls_button_pressed)

	controls_list.add_theme_constant_override("separation", row_separation)

	InputSettings.bindings_changed.connect(_on_bindings_changed)
	InputSettings.rebind_started.connect(_on_rebind_started)
	InputSettings.rebind_finished.connect(_on_rebind_finished)
	InputSettings.rebind_cancelled.connect(_on_rebind_cancelled)

	_build_controls_list()


# Builds the whole controls table from InputSettings.
func _build_controls_list() -> void:
	keyboard_buttons.clear()
	controller_buttons.clear()

	for child: Node in controls_list.get_children():
		child.free()

	_add_header_row()

	for action_definition: Dictionary in InputSettings.get_action_definitions():
		var action_name: String = String(action_definition.get("action", ""))
		var action_label: String = String(action_definition.get("label", action_name))

		if not action_name.is_empty():
			_add_action_row(action_name, action_label)

	_update_all_binding_texts()


# Adds the top row: Action / Keyboard / Pad.
func _add_header_row() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.y = row_min_height

	row.add_child(_make_label(action_column_text, action_label_min_width, true))
	row.add_child(_make_label(keyboard_column_text, binding_button_min_width, true))
	row.add_child(_make_label(controller_column_text, binding_button_min_width, true))

	controls_list.add_child(row)


# Adds one action row with a keyboard button and a controller button.
func _add_action_row(action_name: String, action_label_text: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.y = row_min_height

	var action_label: Label = _make_label(
		action_label_text,
		action_label_min_width,
		false
	)
	var keyboard_button: Button = _make_rebind_button()
	var controller_button: Button = _make_rebind_button()

	keyboard_button.pressed.connect(
		_on_rebind_button_pressed.bind(
			action_name,
			InputSettings.SLOT_KEYBOARD_MOUSE,
			keyboard_button
		)
	)

	controller_button.pressed.connect(
		_on_rebind_button_pressed.bind(
			action_name,
			InputSettings.SLOT_CONTROLLER,
			controller_button
		)
	)

	row.add_child(action_label)
	row.add_child(keyboard_button)
	row.add_child(controller_button)

	keyboard_buttons[action_name] = keyboard_button
	controller_buttons[action_name] = controller_button

	controls_list.add_child(row)


# Makes a simple table label.
func _make_label(label_text: String, min_width: float, centred: bool) -> Label:
	var label: Label = Label.new()
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.custom_minimum_size.x = min_width
	_apply_smaller_font(label)

	if centred:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	return label


# Makes a button used for rebinding.
func _make_rebind_button() -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size.x = binding_button_min_width
	button.focus_mode = Control.FOCUS_ALL
	button.clip_text = true
	_apply_smaller_font(button)
	return button


# Applies a smaller font size based on the current theme font.
# Bit of a jank solution, but who cares.
func _apply_smaller_font(control: Control) -> void:
	var current_font_size: int = control.get_theme_font_size("font_size")
	var new_font_size: int = max(
		current_font_size + font_size_offset,
		minimum_font_size
	)

	control.add_theme_font_size_override("font_size", new_font_size)


# Starts rebinding for the selected action and slot.
func _on_rebind_button_pressed(
	action_name: String,
	slot_name: String,
	pressed_button: Button
) -> void:
	last_pressed_rebind_button = pressed_button
	InputSettings.start_rebind(action_name, slot_name)


# Reset button normally resets controls.
# During rebinding, it becomes a cancel button so nobody gets trapped waiting
# for controller input.
func _on_reset_controls_button_pressed() -> void:
	if InputSettings.is_rebinding:
		InputSettings.cancel_rebind()
		reset_controls_button.grab_focus()
		return

	InputSettings.reset_to_defaults()
	_update_all_binding_texts()

	if grab_focus_after_rebind:
		reset_controls_button.grab_focus()


# Updates all button texts when bindings change.
func _on_bindings_changed() -> void:
	_update_all_binding_texts()


# Shows the waiting prompt and disables rebind buttons while rebinding.
func _on_rebind_started(_action_name: String, slot_name: String) -> void:
	_set_rebinding_ui(true)

	if slot_name == InputSettings.SLOT_KEYBOARD_MOUSE:
		_show_prompt(waiting_for_keyboard_text)
	else:
		_show_prompt(waiting_for_controller_text)


# Updates the finished binding and restores the normal UI.
func _on_rebind_finished(action_name: String, _slot_name: String) -> void:
	_set_rebinding_ui(false)
	_update_binding_text(action_name)
	_clear_prompt()

	if grab_focus_after_rebind and last_pressed_rebind_button != null:
		last_pressed_rebind_button.grab_focus()


# Restores the normal UI after cancelling a rebind.
func _on_rebind_cancelled() -> void:
	_set_rebinding_ui(false)
	_show_prompt(cancelled_text)

	if grab_focus_after_rebind:
		reset_controls_button.grab_focus()


# Updates every generated binding button.
func _update_all_binding_texts() -> void:
	for action_definition: Dictionary in InputSettings.get_action_definitions():
		var action_name: String = String(action_definition.get("action", ""))

		if not action_name.is_empty():
			_update_binding_text(action_name)


# Updates one action row.
func _update_binding_text(action_name: String) -> void:
	var keyboard_button: Button = keyboard_buttons.get(action_name) as Button
	var controller_button: Button = controller_buttons.get(action_name) as Button

	if keyboard_button != null:
		keyboard_button.text = InputSettings.get_action_slot_text(
			action_name,
			InputSettings.SLOT_KEYBOARD_MOUSE
		)

	if controller_button != null:
		controller_button.text = InputSettings.get_action_slot_text(
			action_name,
			InputSettings.SLOT_CONTROLLER
		)


# Enables or disables rebind buttons and swaps the reset button text.
func _set_rebinding_ui(is_rebinding: bool) -> void:
	for button: Button in keyboard_buttons.values():
		button.disabled = is_rebinding

	for button: Button in controller_buttons.values():
		button.disabled = is_rebinding

	reset_controls_button.disabled = false
	reset_controls_button.text = (
		stop_rebind_button_text if is_rebinding else reset_button_text
	)


# Shows the prompt label.
func _show_prompt(prompt_text: String) -> void:
	rebind_prompt_label.text = prompt_text
	rebind_prompt_label.visible = true


# Clears the prompt label.
func _clear_prompt() -> void:
	rebind_prompt_label.text = ""
	rebind_prompt_label.visible = not hide_prompt_when_not_rebinding
