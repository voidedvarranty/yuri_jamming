extends Control

# Settings menu. BUT MUCH shorter

@export_group("Scene")
@export var main_menu_scene: String = "main_menu"
@export var win_screen_scene: String = "win_screen"
@export var lose_screen_scene: String = "lose_screen"
@export var scene_transition_duration: float = 0.0

@export_group("Debug")
@export var show_debug_button: bool = false

@export_group("Panel Rotation")
@export var starting_panel_index: int = 0
@export var panel_transition_duration: float = 0.38
@export var panel_rotation_angle_degrees: float = 55.0
@export var fake_pivot_x_offset: float = 180.0
@export_range(0.0, 1.0, 0.01) var fake_pivot_y_ratio: float = 0.5
@export var inactive_panel_scale: Vector2 = Vector2(0.94, 0.94)
@export var active_panel_scale: Vector2 = Vector2.ONE

@export_group("Panel Landing Juice")
@export var use_panel_landing_juice: bool = true
@export var panel_landing_overshoot_degrees: float = 3.5
@export var panel_landing_punch_scale: float = 1.025
@export var panel_landing_settle_duration: float = 0.10
@export var panel_land_sound: AudioStream

@export_group("Active Category Button")
@export var use_active_button_visuals: bool = true
@export var active_button_modulate: Color = Color.WHITE
@export var inactive_button_modulate: Color = Color(0.65, 0.65, 0.65, 1.0)

@export_group("Focus")
@export var focus_sound_button_on_start: bool = true
@export var focus_clicked_category_button: bool = true

@export_group("UI Sounds")
@export var click_sound: AudioStream
@export var hover_sound: AudioStream

@export_group("Button Juice")
@export var button_hover_scale: Vector2 = Vector2(1.06, 1.06)
@export var button_down_scale: Vector2 = Vector2(0.94, 0.94)
@export var button_up_scale: Vector2 = Vector2(1.08, 1.08)
@export var button_hover_duration: float = 0.10
@export var button_down_duration: float = 0.06
@export var button_up_duration: float = 0.08

@export_group("Slider Visual Padding")
@export_range(0.0, 0.25, 0.01) var slider_visual_edge_padding: float = 0.05

@export_group("Percentage Labels")
@export var show_slider_percentage_labels: bool = true
@export var percentage_label_min_width: float = 50.0
@export var percentage_label_suffix: String = "%"

# Page dictionaries use:
# "button": Button
# "panel": Control
var pages: Array[Dictionary] = []

# Slider dictionaries use:
# "slider": HSlider
# "property": String
# "setter": StringName
# "label": String
var volume_sliders: Array[Dictionary] = []

var current_panel_index: int = 0
var is_switching_panel: bool = false
var is_setting_control_values: bool = false

var panel_home_position: Vector2 = Vector2.ZERO
var panel_tween: Tween = null
var panel_landing_tween: Tween = null

var button_tweens: Dictionary[Button, Tween] = {}
var slider_percentage_labels: Dictionary[HSlider, Label] = {}

@onready var sound_settings_button: Button = %SoundSettingsButton
@onready var display_settings_button: Button = %DisplaySettingsButton
@onready var key_configuration_button: Button = %KeyConfigurationButton
@onready var debug_button: Button = %DebugButton
@onready var back_button: Button = %BackButton

@onready var content_root: Control = %ContentRoot

@onready var sound_settings_panel: Control = %SoundSettingsPanel
@onready var display_settings_panel: Control = %DisplaySettingsPanel
@onready var key_configuration_panel: Control = %KeyConfigurationPanel
@onready var debug_panel: Control = %DebugPanel

@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider

@onready var fullscreen_button: BaseButton = %FullscreenButton
@onready var reset_settings_button: Button = %ResetSettingsButton
@onready var delete_save_button: Button = %DeleteSaveButton
@onready var win_button: Button = %WinButton
@onready var lose_button: Button = %LoseButton


# Sets up the settings menu after the UI has had one frame to size itself.
func _ready() -> void:
	await get_tree().process_frame

	_setup_pages()
	_setup_sliders()
	_connect_buttons()
	_setup_button_juice()
	_load_saved_values()
	_show_starting_panel()

	if focus_sound_button_on_start:
		sound_settings_button.grab_focus()


# PAGE SETUP


# Creates the list of settings pages and hides all panels at the start.
func _setup_pages() -> void:
	pages = [
		{"button": sound_settings_button, "panel": sound_settings_panel},
		{"button": display_settings_button, "panel": display_settings_panel},
		{"button": key_configuration_button, "panel": key_configuration_panel},
	]

	debug_button.visible = show_debug_button

	if show_debug_button:
		pages.append({"button": debug_button, "panel": debug_panel})
	else:
		_set_panel_state(debug_panel, false)

	for page: Dictionary in pages:
		var button: Button = page["button"] as Button
		var panel: Control = page["panel"] as Control

		button.focus_mode = Control.FOCUS_ALL
		_set_panel_state(panel, false)


# Shows the starting panel without animating.
func _show_starting_panel() -> void:
	if pages.is_empty():
		return

	current_panel_index = clampi(starting_panel_index, 0, pages.size() - 1)

	for index: int in range(pages.size()):
		var panel: Control = pages[index]["panel"] as Control
		_set_panel_state(panel, index == current_panel_index)

	_update_active_button_visuals()


# Handles clicking a category button.
func _on_page_button_pressed(target_index: int) -> void:
	if focus_clicked_category_button:
		var button: Button = pages[target_index]["button"] as Button
		button.grab_focus()

	show_settings_panel(target_index)


# Rotates from the current settings panel to another one.
func show_settings_panel(target_index: int) -> void:
	if (
		pages.is_empty()
		or is_switching_panel
		or target_index == current_panel_index
		or target_index < 0
		or target_index >= pages.size()
	):
		return

	is_switching_panel = true

	if panel_tween != null:
		panel_tween.kill()

	if panel_landing_tween != null:
		panel_landing_tween.kill()

	var old_panel: Control = pages[current_panel_index]["panel"] as Control
	var new_panel: Control = pages[target_index]["panel"] as Control

	var direction: int = _get_rotation_direction(current_panel_index, target_index)
	var old_end_rotation: float = panel_rotation_angle_degrees * float(direction)
	var new_start_rotation: float = -panel_rotation_angle_degrees * float(direction)
	var new_end_rotation: float = 0.0
	var new_end_scale: Vector2 = active_panel_scale

	if use_panel_landing_juice:
		new_end_rotation = panel_landing_overshoot_degrees * float(direction)
		new_end_scale = active_panel_scale * panel_landing_punch_scale

	_prepare_panel_for_tween(old_panel, 0.0, active_panel_scale, 1.0)
	_prepare_panel_for_tween(new_panel, new_start_rotation, inactive_panel_scale, 0.0)

	panel_tween = create_tween()
	panel_tween.set_parallel(true)
	panel_tween.set_trans(Tween.TRANS_QUART)
	panel_tween.set_ease(Tween.EASE_OUT)

	panel_tween.tween_property(
		old_panel, "rotation_degrees", old_end_rotation, panel_transition_duration
	)
	panel_tween.tween_property(old_panel, "modulate:a", 0.0, panel_transition_duration)
	panel_tween.tween_property(old_panel, "scale", inactive_panel_scale, panel_transition_duration)

	panel_tween.tween_property(
		new_panel, "rotation_degrees", new_end_rotation, panel_transition_duration
	)
	panel_tween.tween_property(new_panel, "modulate:a", 1.0, panel_transition_duration)
	panel_tween.tween_property(new_panel, "scale", new_end_scale, panel_transition_duration)

	await panel_tween.finished

	current_panel_index = target_index

	_set_panel_state(old_panel, false)
	_set_panel_state(new_panel, true)
	_update_active_button_visuals()
	play_sfx(panel_land_sound)

	if use_panel_landing_juice and panel_landing_settle_duration > 0.0:
		panel_landing_tween = create_tween()
		panel_landing_tween.set_parallel(true)
		panel_landing_tween.set_trans(Tween.TRANS_BACK)
		panel_landing_tween.set_ease(Tween.EASE_OUT)

		panel_landing_tween.tween_property(
			new_panel, "rotation_degrees", 0.0, panel_landing_settle_duration
		)
		panel_landing_tween.tween_property(
			new_panel, "scale", active_panel_scale, panel_landing_settle_duration
		)

		await panel_landing_tween.finished

	new_panel.rotation_degrees = 0.0
	new_panel.scale = active_panel_scale

	panel_tween = null
	panel_landing_tween = null
	is_switching_panel = false


# Prepares a panel before it enters or leaves with the rotation animation.
func _prepare_panel_for_tween(
	panel: Control, rotation_degrees: float, panel_scale: Vector2, alpha: float
) -> void:
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.position = panel_home_position
	panel.pivot_offset = _get_fake_pivot_point() - panel_home_position
	panel.rotation_degrees = rotation_degrees
	panel.scale = panel_scale
	panel.visible = true
	panel.modulate.a = alpha
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE


# Applies the final active or inactive state of a panel.
func _set_panel_state(panel: Control, is_active: bool) -> void:
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.position = panel_home_position
	panel.pivot_offset = _get_fake_pivot_point() - panel_home_position
	panel.rotation_degrees = 0.0
	panel.scale = active_panel_scale if is_active else inactive_panel_scale
	panel.visible = is_active
	panel.modulate.a = 1.0 if is_active else 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP if is_active else Control.MOUSE_FILTER_IGNORE


# Gets the fake pivot point used for the rotating panel effect.
func _get_fake_pivot_point() -> Vector2:
	var root_size: Vector2 = content_root.size

	if root_size == Vector2.ZERO:
		root_size = get_viewport_rect().size

	return Vector2(root_size.x + fake_pivot_x_offset, root_size.y * fake_pivot_y_ratio)


# Decides which direction the panels should rotate.
func _get_rotation_direction(from_index: int, to_index: int) -> int:
	var page_count: int = pages.size()
	var forward_steps: int = (to_index - from_index + page_count) % page_count
	var backward_steps: int = (from_index - to_index + page_count) % page_count

	if forward_steps <= backward_steps:
		return 1

	return -1


# Updates the category button colours.
func _update_active_button_visuals() -> void:
	for index: int in range(pages.size()):
		var button: Button = pages[index]["button"] as Button

		if not use_active_button_visuals:
			button.modulate = Color.WHITE
		elif index == current_panel_index:
			button.modulate = active_button_modulate
		else:
			button.modulate = inactive_button_modulate


# SLIDERS / SETTINGS


# Sets up the volume sliders and their optional percentage labels.
func _setup_sliders() -> void:
	volume_sliders = [
		{
			"slider": master_slider,
			"property": "master_volume",
			"setter": "set_master_volume",
			"label": "MasterPercentageLabel",
		},
		{
			"slider": music_slider,
			"property": "music_volume",
			"setter": "set_music_volume",
			"label": "MusicPercentageLabel",
		},
		{
			"slider": sfx_slider,
			"property": "sfx_volume",
			"setter": "set_sfx_volume",
			"label": "SFXPercentageLabel",
		},
	]

	for item: Dictionary in volume_sliders:
		var slider: HSlider = item["slider"] as HSlider

		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value_changed.connect(
			_on_volume_slider_changed.bind(slider, StringName(String(item["setter"])))
		)

		if show_slider_percentage_labels:
			var label_name: String = String(item["label"])
			var parent_node: Node = slider.get_parent()
			var percentage_label: Label = parent_node.get_node_or_null(label_name) as Label

			if percentage_label == null:
				percentage_label = Label.new()
				percentage_label.name = label_name
				parent_node.add_child(percentage_label)

			percentage_label.custom_minimum_size.x = percentage_label_min_width
			percentage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			percentage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

			slider_percentage_labels[slider] = percentage_label

	fullscreen_button.toggled.connect(_on_fullscreen_button_toggled)


# Loads saved settings from GameData into the menu controls.
func _load_saved_values() -> void:
	is_setting_control_values = true

	for item: Dictionary in volume_sliders:
		var slider: HSlider = item["slider"] as HSlider
		var property_name: String = String(item["property"])

		slider.value = volume_to_slider_value(float(GameData.get(property_name)))

	fullscreen_button.button_pressed = GameData.fullscreen

	is_setting_control_values = false

	for item: Dictionary in volume_sliders:
		_update_slider_label(item["slider"] as HSlider)


# Updates a volume setting when one of the sliders changes.
func _on_volume_slider_changed(value: float, slider: HSlider, setter_method: StringName) -> void:
	_update_slider_label(slider)

	if not is_setting_control_values:
		GameData.call(setter_method, slider_value_to_volume(value))


# Updates fullscreen when the fullscreen button is toggled.
func _on_fullscreen_button_toggled(button_pressed: bool) -> void:
	if not is_setting_control_values:
		GameData.set_fullscreen(button_pressed)


# Updates the percentage label next to a slider.
func _update_slider_label(slider: HSlider) -> void:
	var percentage_label: Label = slider_percentage_labels.get(slider) as Label

	if percentage_label == null:
		return

	var volume_value: float = slider_value_to_volume(slider.value)
	percentage_label.text = str(roundi(volume_value * 100.0)) + percentage_label_suffix


# Converts visual slider value to actual volume.
func slider_value_to_volume(slider_value: float) -> float:
	var padding: float = clampf(slider_visual_edge_padding, 0.0, 0.49)

	if slider_value <= padding:
		return 0.0

	if slider_value >= 1.0 - padding:
		return 1.0

	return inverse_lerp(padding, 1.0 - padding, slider_value)


# Converts actual volume to visual slider value.
func volume_to_slider_value(volume: float) -> float:
	var padding: float = clampf(slider_visual_edge_padding, 0.0, 0.49)
	var clamped_volume: float = clampf(volume, 0.0, 1.0)

	if clamped_volume <= 0.0:
		return padding

	if clamped_volume >= 1.0:
		return 1.0 - padding

	return lerpf(padding, 1.0 - padding, clamped_volume)


# BUTTONS


# Connects all normal menu buttons.
func _connect_buttons() -> void:
	for index: int in range(pages.size()):
		var button: Button = pages[index]["button"] as Button
		button.pressed.connect(_on_page_button_pressed.bind(index))

	back_button.pressed.connect(_go_to_scene.bind(main_menu_scene))
	win_button.pressed.connect(_go_to_scene.bind(win_screen_scene))
	lose_button.pressed.connect(_go_to_scene.bind(lose_screen_scene))

	reset_settings_button.pressed.connect(_reset_audio_settings)
	delete_save_button.pressed.connect(_reset_all_settings)


# Goes to another scene through SceneManager.
func _go_to_scene(scene_key: String) -> void:
	SceneManager.go(scene_key, scene_transition_duration)


# Resets only the audio settings.
func _reset_audio_settings() -> void:
	GameData.reset_audio_settings()
	_load_saved_values()


# Resets all saved settings.
func _reset_all_settings() -> void:
	GameData.reset_all_settings()
	_load_saved_values()


# Adds hover/click animation to every button in this scene.
func _setup_button_juice() -> void:
	for node: Node in find_children("*", "Button", true, false):
		var button: Button = node as Button

		if button == null:
			continue

		button.pivot_offset = button.size / 2.0

		button.mouse_entered.connect(_on_button_mouse_entered.bind(button))
		button.mouse_exited.connect(_on_button_mouse_exited.bind(button))
		button.button_down.connect(_on_button_down.bind(button))
		button.button_up.connect(_on_button_up.bind(button))


# Plays hover sound and grows the button a little.
func _on_button_mouse_entered(button: Button) -> void:
	play_sfx(hover_sound)
	_animate_button(button, button_hover_scale, button_hover_duration)


# Shrinks the button back to normal after hover.
func _on_button_mouse_exited(button: Button) -> void:
	_animate_button(button, Vector2.ONE, button_hover_duration)


# Plays click sound and squashes the button.
func _on_button_down(button: Button) -> void:
	play_sfx(click_sound)
	_animate_button(button, button_down_scale, button_down_duration)


# Pops the button up again when released.
func _on_button_up(button: Button) -> void:
	if button.get_global_rect().has_point(get_global_mouse_position()):
		_animate_button(button, button_up_scale, button_up_duration)
	else:
		_animate_button(button, Vector2.ONE, button_up_duration)


# Tweens a button to the given scale.
func _animate_button(button: Button, target_scale: Vector2, duration: float) -> void:
	if button_tweens.has(button):
		var old_tween: Tween = button_tweens[button] as Tween

		if old_tween != null:
			old_tween.kill()

	var tween: Tween = create_tween()
	button_tweens[button] = tween

	(
		tween
		. tween_property(button, "scale", target_scale, duration)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


# Plays a UI sound if one is assigned.
func play_sfx(sound: AudioStream) -> void:
	if sound != null:
		SfxPlayer.play(sound)

#Comment
#test
