extends Control

# Main menu script.
# Handles scene buttons, button sounds, button juice, and important DVD donkey.
# This scene assumes the required UI nodes exist.

@export_group("Scenes")
@export var new_game_scene: String = "main"
@export var settings_scene: String = "settings"
@export var credits_scene: String = "credits"

@export_group("Scene Transitions")
@export var new_game_transition_duration: float = 1.0
@export var settings_transition_duration: float = 0.0
@export var credits_transition_duration: float = 1.0

@export_group("UI Sounds")
@export var click_sound: AudioStream
@export var hover_sound: AudioStream
@export var new_game_sound: AudioStream

@export_group("Button Juice")
@export var button_hover_scale: Vector2 = Vector2(1.06, 1.06)
@export var button_down_scale: Vector2 = Vector2(0.94, 0.94)
@export var button_up_scale: Vector2 = Vector2(1.08, 1.08)
@export var button_hover_duration: float = 0.10
@export var button_down_duration: float = 0.06
@export var button_up_duration: float = 0.08

#region Donkey Shit

@export_group("Donkey DVD")
@export var animate_donkey: bool = true
@export var donkey_start_velocity: Vector2 = Vector2(170.0, 125.0)
@export var donkey_min_scale: float = 0.05
@export var donkey_max_scale: float = 0.30
@export var donkey_scale_speed: float = 0.3

@export_group("Donkey Mitosis")
@export var duplicate_donkey_at_max_scale: bool = true
@export var max_donkeys: int = 5
@export_range(0.8, 1.0, 0.01) var duplicate_scale_threshold: float = 0.98
@export_range(0.0, 0.9, 0.01) var duplicate_reset_threshold: float = 0.75
@export var duplicate_angle_degrees: float = 38.0
@export var duplicate_velocity_multiplier: float = 1.02

# Stores every donkey and its personal velocity / scale timing.
var donkey_entries: Array[Dictionary] = []

#endregion

# Stores active button tweens so new animations can cancel old ones.
var button_tweens: Dictionary[Button, Tween] = {}


@onready var new_game_button: Button = %NewGameButton
@onready var credits_button: Button = $VBoxContainer/Load
@onready var settings_button: Button = %SettingsButton
@onready var donkey: TextureRect = %Donkey

func _ready() -> void:
	get_tree().paused = false

	# Wait one frame so buttons have their final size before setting pivot offsets.
	await get_tree().process_frame

	_setup_buttons()
	_setup_donkey()


func _process(delta: float) -> void:
	if animate_donkey:
		_update_donkeys(delta)


func _on_new_game_button_pressed() -> void:
	play_sfx(new_game_sound)
	SceneManager.go(new_game_scene, new_game_transition_duration)


func _on_settings_button_pressed() -> void:
	play_sfx(click_sound)
	SceneManager.go(settings_scene, settings_transition_duration)


# This is still named "load" so existing editor signal connections do not break.
# In this template, the old Load button is used as Credits.
func _on_load_pressed() -> void:
	play_sfx(click_sound)
	SceneManager.go(credits_scene, credits_transition_duration)


# Sets button text, pivots, and hover/click signals.
func _setup_buttons() -> void:
	new_game_button.text = "New game"
	credits_button.text = "Credits"
	settings_button.text = "Settings"

	for node: Node in find_children("*", "Button", true, false):
		var button: Button = node as Button

		if button == null:
			continue

		button.pivot_offset = button.size / 2.0

		var mouse_entered_callable: Callable = _on_button_mouse_entered.bind(button)
		var mouse_exited_callable: Callable = _on_button_mouse_exited.bind(button)
		var button_down_callable: Callable = _on_button_down.bind(button)
		var button_up_callable: Callable = _on_button_up.bind(button)

		if not button.mouse_entered.is_connected(mouse_entered_callable):
			button.mouse_entered.connect(mouse_entered_callable)

		if not button.mouse_exited.is_connected(mouse_exited_callable):
			button.mouse_exited.connect(mouse_exited_callable)

		if not button.button_down.is_connected(button_down_callable):
			button.button_down.connect(button_down_callable)

		if not button.button_up.is_connected(button_up_callable):
			button.button_up.connect(button_up_callable)


func _on_button_mouse_entered(button: Button) -> void:
	play_sfx(hover_sound)
	_animate_button(button, button_hover_scale, button_hover_duration)


func _on_button_mouse_exited(button: Button) -> void:
	_animate_button(button, Vector2.ONE, button_hover_duration)


func _on_button_down(button: Button) -> void:
	play_sfx(click_sound)
	_animate_button(button, button_down_scale, button_down_duration)


func _on_button_up(button: Button) -> void:
	if button.get_global_rect().has_point(get_global_mouse_position()):
		_animate_button(button, button_up_scale, button_up_duration)
	else:
		_animate_button(button, Vector2.ONE, button_up_duration)


# Tweens a button to a target scale.
func _animate_button(button: Button, target_scale: Vector2, duration: float) -> void:
	if button == null:
		return

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


#region Donkey Shit


# Prepares the first donkey.
func _setup_donkey() -> void:
	if donkey == null:
		return

	donkey_entries.clear()
	_prepare_donkey_visuals(donkey)

	donkey_entries.append(
		{
			"node": donkey,
			"velocity": donkey_start_velocity,
			"scale_time": 0.0,
			"has_duplicated_this_peak": false
		}
	)


# Makes a donkey ignore mouse input and scale around its centre.
func _prepare_donkey_visuals(donkey_node: TextureRect) -> void:
	donkey_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	donkey_node.pivot_offset = donkey_node.size / 2.0
	donkey_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


# Updates all donkeys, then duplicates any donkey that reached peak scale.
func _update_donkeys(delta: float) -> void:
	var entries_to_duplicate: Array[Dictionary] = []

	for entry: Dictionary in donkey_entries:
		var donkey_node: TextureRect = entry["node"] as TextureRect

		if donkey_node == null or donkey_node.size == Vector2.ZERO:
			continue

		var velocity: Vector2 = entry["velocity"] as Vector2
		var scale_time: float = float(entry["scale_time"])
		var has_duplicated_this_peak: bool = bool(entry["has_duplicated_this_peak"])

		scale_time += delta * donkey_scale_speed

		var scale_alpha: float = (sin(scale_time) + 1.0) * 0.5
		var current_scale: float = lerpf(donkey_min_scale, donkey_max_scale, scale_alpha)

		donkey_node.scale = Vector2(current_scale, current_scale)
		donkey_node.position += velocity * delta

		velocity = _bounce_donkey_inside_screen(donkey_node, velocity)

		var should_duplicate: bool = (
			duplicate_donkey_at_max_scale
			and scale_alpha >= duplicate_scale_threshold
			and not has_duplicated_this_peak
		)

		if should_duplicate:
			has_duplicated_this_peak = true
			entries_to_duplicate.append(entry)

		if scale_alpha <= duplicate_reset_threshold:
			has_duplicated_this_peak = false

		entry["velocity"] = velocity
		entry["scale_time"] = scale_time
		entry["has_duplicated_this_peak"] = has_duplicated_this_peak

	for entry: Dictionary in entries_to_duplicate:
		_duplicate_donkey_from_entry(entry)


# Keeps the donkey inside the screen and reverses velocity when it hits an edge.
func _bounce_donkey_inside_screen(donkey_node: TextureRect, velocity: Vector2) -> Vector2:
	var screen_size: Vector2 = size

	if screen_size == Vector2.ZERO:
		screen_size = get_viewport_rect().size

	var visual_size: Vector2 = donkey_node.size * donkey_node.scale
	var visual_top_left: Vector2 = (
		donkey_node.position
		+ donkey_node.pivot_offset
		- donkey_node.pivot_offset * donkey_node.scale
	)
	var visual_bottom_right: Vector2 = visual_top_left + visual_size

	if visual_top_left.x <= 0.0:
		donkey_node.position.x -= visual_top_left.x
		velocity.x = absf(velocity.x)

	if visual_bottom_right.x >= screen_size.x:
		donkey_node.position.x -= visual_bottom_right.x - screen_size.x
		velocity.x = -absf(velocity.x)

	if visual_top_left.y <= 0.0:
		donkey_node.position.y -= visual_top_left.y
		velocity.y = absf(velocity.y)

	if visual_bottom_right.y >= screen_size.y:
		donkey_node.position.y -= visual_bottom_right.y - screen_size.y
		velocity.y = -absf(velocity.y)

	return velocity


# Duplicates a donkey and sends the clone in a slightly different direction.
func _duplicate_donkey_from_entry(source_entry: Dictionary) -> void:
	if donkey_entries.size() >= max_donkeys:
		return

	var source_donkey: TextureRect = source_entry["node"] as TextureRect

	if source_donkey == null or source_donkey.get_parent() == null:
		return

	var new_donkey: TextureRect = source_donkey.duplicate() as TextureRect

	if new_donkey == null:
		return

	source_donkey.get_parent().add_child(new_donkey)

	new_donkey.name = "DonkeyClone"
	new_donkey.position = source_donkey.position
	new_donkey.scale = source_donkey.scale
	new_donkey.rotation = source_donkey.rotation
	new_donkey.z_index = source_donkey.z_index

	_prepare_donkey_visuals(new_donkey)

	var direction_multiplier: float = 1.0

	if donkey_entries.size() % 2 == 0:
		direction_multiplier = -1.0

	var source_velocity: Vector2 = source_entry["velocity"] as Vector2
	var new_velocity: Vector2 = source_velocity.rotated(
		deg_to_rad(duplicate_angle_degrees * direction_multiplier)
	)
	new_velocity *= duplicate_velocity_multiplier

	donkey_entries.append(
		{
			"node": new_donkey,
			"velocity": new_velocity,
			"scale_time": float(source_entry["scale_time"]) + 1.0,
			"has_duplicated_this_peak": true
		}
	)


#endregion


# Plays a UI sound if one is assigned.
func play_sfx(sound: AudioStream) -> void:
	if sound != null:
		SfxPlayer.play(sound)
