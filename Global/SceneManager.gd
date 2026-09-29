extends Node

## Check the design bible on how to use this.

signal scene_load_started(scene_key: String, scene_path: String)
signal scene_load_finished(scene_key: String, scene_path: String)
signal scene_load_failed(scene_id_or_path: String)

signal overlay_loaded(overlay: Node, scene_key: String, scene_path: String)
signal overlay_cleared

@export_group("Loading")
@export var default_load_time: float = 0.0
@export var prevent_reloading_same_scene: bool = true
@export var loading_overlay_layer_number: int = 10000
@export var loading_enter_transition_method: StringName = &"start_enter_transition"
@export var loading_exit_transition_method: StringName = &"start_exit_transition"

@export_group("Scene Music")
@export var use_scene_music_manager: bool = true
@export var scene_music_manager_prepare_method: StringName = &"prepare_scene_music"
@export var scene_music_manager_play_prepared_method: StringName = &"play_prepared_scene_music"

@export_group("Overlays")
@export var overlay_layer_number: int = 100
@export var clear_overlay_when_changing_scene: bool = true
@export var add_overlay_input_blocker: bool = true

var scenes: Dictionary = {
	"main_menu": "res://Scenes/UI/Main Menu/main_menu.tscn",
	"groove": "res://Scenes/UI/PregameSound/sound_setup.tscn",
	"main": "res://Scenes/Main/main.tscn",
	"settings": "res://Scenes/UI/Settings/settings.tscn",
	"load_screen": "res://Scenes/UI/Loading Screen/loading.tscn",
	"credits": "res://Scenes/UI/Credits/credits.tscn",
	"lose_screen": "res://Scenes/UI/Lose/loss_screen.tscn",
	"win_screen": "res://Scenes/UI/Win/win_screen.tscn",
}

## The scene currently selected for loading.
var selected_scene_path: String = ""

## The key of the selected scene, if it has one.
var selected_scene_key: String = ""

## Minimum duration value for your loading overlay.
var load_time: float = 0.0

## The currently loaded scene.
var current_scene_path: String = ""
var current_scene_key: String = ""

## Prevents several scene changes from happening at the same time.
var is_changing_scene: bool = false

## Overlay state.
var _overlay_layer: CanvasLayer
var _active_overlay: Node
var _overlay_input_blocker: Control

## Loading overlay state.
var _loading_overlay_layer: CanvasLayer
var _active_loading_overlay: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Changes the entire scene.
func go(scene_id_or_path: String, duration: float = -1.0, force_reload: bool = false) -> void:
	load_scene(scene_id_or_path, duration, force_reload)


## Changes the entire scene.
func load_scene(
	scene_id_or_path: String, duration: float = -1.0, force_reload: bool = false
) -> void:
	if is_changing_scene:
		return

	var scene_path: String = get_scene_path(scene_id_or_path)

	if scene_path.is_empty():
		scene_load_failed.emit(scene_id_or_path)
		return

	if prevent_reloading_same_scene and not force_reload and scene_path == current_scene_path:
		return

	var safe_duration: float = _get_safe_duration(duration)

	selected_scene_path = scene_path
	selected_scene_key = get_scene_key_from_path(scene_path)
	load_time = safe_duration
	is_changing_scene = true

	scene_load_started.emit(selected_scene_key, selected_scene_path)

	if clear_overlay_when_changing_scene:
		_clear_overlay_without_signal()

	var used_loading_overlay: bool = false
	var loading_started_msec: int = Time.get_ticks_msec()

	if safe_duration > 0.0 and has_scene_key("load_screen"):
		var loading_screen_path: String = get_scene_path("load_screen")

		if not loading_screen_path.is_empty() and scene_path != loading_screen_path:
			used_loading_overlay = await _show_loading_overlay(loading_screen_path)
			loading_started_msec = Time.get_ticks_msec()

	_prepare_scene_music_for_selected_scene()

	if used_loading_overlay:
		await _play_loading_overlay_enter_transition()

	var success: bool = await _change_scene_to_path(scene_path)

	if not success:
		if used_loading_overlay:
			clear_loading_overlay()

		is_changing_scene = false
		scene_load_failed.emit(scene_id_or_path)
		return

	scene_load_finished.emit(current_scene_key, current_scene_path)

	if used_loading_overlay:
		await _wait_for_minimum_loading_time(loading_started_msec, safe_duration)
		await get_tree().process_frame
		_play_prepared_scene_music()
		await _play_loading_overlay_exit_transition()
		clear_loading_overlay()
	else:
		_play_prepared_scene_music()

	is_changing_scene = false


## Reloads the current scene.
func reload(duration: float = -1.0) -> void:
	var scene_to_reload: String = current_scene_path

	if scene_to_reload.is_empty() and get_tree().current_scene != null:
		scene_to_reload = get_tree().current_scene.scene_file_path

	if scene_to_reload.is_empty():
		push_error("Cannot reload because no current scene is known.")
		return

	load_scene(scene_to_reload, duration, true)


## Adds a scene on top of the current scene.
func overlay(scene_id_or_path: String) -> void:
	show_overlay_scene(scene_id_or_path)


## Adds a scene on top of the current scene.
##
## Useful for pause menus, popups, tutorials, dialogue boxes, or temporary UI.
func show_overlay_scene(scene_id_or_path: String) -> void:
	var scene_path: String = get_scene_path(scene_id_or_path)

	if scene_path.is_empty():
		return

	var packed_scene: PackedScene = _get_packed_scene(scene_path)

	if packed_scene == null:
		return

	_clear_overlay_without_signal()

	await get_tree().process_frame

	var layer: CanvasLayer = _get_overlay_layer()

	if add_overlay_input_blocker:
		_create_overlay_input_blocker(layer)

	var scene_instance: Node = packed_scene.instantiate()

	layer.add_child(scene_instance)
	_fit_control_to_screen(scene_instance)

	_active_overlay = scene_instance
	overlay_loaded.emit(scene_instance, get_scene_key_from_path(scene_path), scene_path)


## Closes the current overlay.
func clear_overlay() -> void:
	var had_overlay: bool = _remove_active_overlay()

	if had_overlay:
		overlay_cleared.emit()


## Returns true if an overlay is currently open.
func has_overlay() -> bool:
	return _active_overlay != null and is_instance_valid(_active_overlay)


## Returns the active overlay node.
func get_active_overlay() -> Node:
	if not has_overlay():
		return null

	return _active_overlay


## Returns true if the loading overlay is currently open.
func has_loading_overlay() -> bool:
	return _active_loading_overlay != null and is_instance_valid(_active_loading_overlay)


## Closes the loading overlay.
func clear_loading_overlay() -> void:
	if has_loading_overlay():
		_active_loading_overlay.queue_free()

	_active_loading_overlay = null


## Adds or replaces a scene in the scene registry.
func register_scene(scene_key: String, scene_path: String) -> void:
	if scene_key.is_empty():
		push_error("Scene key cannot be empty.")
		return

	if not _is_valid_scene_path(scene_path):
		push_error("Invalid scene path for key '%s': %s" % [scene_key, scene_path])
		return

	scenes[scene_key] = scene_path


## Removes a scene from the scene registry.
func unregister_scene(scene_key: String) -> void:
	if not scenes.has(scene_key):
		return

	scenes.erase(scene_key)


## Returns true if a scene key exists in the scene dictionary.
func has_scene_key(scene_key: String) -> bool:
	return scenes.has(scene_key)


## Returns all registered scene keys.
func get_scene_keys() -> Array[String]:
	var keys: Array[String] = []

	for key in scenes.keys():
		keys.append(String(key))

	keys.sort()
	return keys


## Returns the path for a scene key, UID, or res path.
func get_scene_path(scene_id_or_path: String) -> String:
	if scenes.has(scene_id_or_path):
		return String(scenes[scene_id_or_path])

	if _is_valid_scene_path(scene_id_or_path):
		return scene_id_or_path

	push_error(
		(
			"Unknown scene key or path: '%s'. Available keys: %s"
			% [scene_id_or_path, ", ".join(get_scene_keys())]
		)
	)
	return ""


## Returns the key for a scene path, if it exists in scenes.
func get_scene_key_from_path(scene_path: String) -> String:
	for scene_key in scenes.keys():
		if String(scenes[scene_key]) == scene_path:
			return String(scene_key)

	return ""


## Returns true if the given scene is currently active.
func is_current_scene(scene_id_or_path: String) -> bool:
	var scene_path: String = get_scene_path(scene_id_or_path)

	if scene_path.is_empty():
		return false

	return current_scene_path == scene_path


## Returns the scene key currently selected for loading.
func get_selected_scene_key() -> String:
	return selected_scene_key


## Returns the scene path currently selected for loading.
func get_selected_scene_path() -> String:
	return selected_scene_path


## Internally changes to a specific scene path.
func _change_scene_to_path(scene_path: String) -> bool:
	var packed_scene: PackedScene = _get_packed_scene(scene_path)

	if packed_scene == null:
		return false

	var error: Error = get_tree().change_scene_to_packed(packed_scene)

	if error != OK:
		push_error("Scene change failed with error: %s" % error)
		return false

	await get_tree().scene_changed

	current_scene_path = scene_path
	current_scene_key = get_scene_key_from_path(scene_path)

	return true


## Gets the load duration.
func _get_safe_duration(duration: float) -> float:
	var safe_duration: float = duration

	if safe_duration < 0.0:
		safe_duration = default_load_time

	if safe_duration < 0.0:
		safe_duration = 0.0

	return safe_duration


## Shows the loading screen as a mega overlay.
func _show_loading_overlay(scene_path: String) -> bool:
	var packed_scene: PackedScene = _get_packed_scene(scene_path)

	if packed_scene == null:
		return false

	clear_loading_overlay()

	var layer: CanvasLayer = _get_loading_overlay_layer()
	var scene_instance: Node = packed_scene.instantiate()

	layer.add_child(scene_instance)
	_fit_control_to_screen(scene_instance)

	_active_loading_overlay = scene_instance

	await get_tree().process_frame

	return true


## Plays the loading overlay enter transition before the scene changes.
func _play_loading_overlay_enter_transition() -> void:
	if not has_loading_overlay():
		return

	if not _active_loading_overlay.has_method(loading_enter_transition_method):
		push_error(
			"Loading overlay root needs a '%s' function." % String(loading_enter_transition_method)
		)
		return

	await _active_loading_overlay.call(loading_enter_transition_method)


## Plays the loading overlay exit transition after the new scene is ready.
func _play_loading_overlay_exit_transition() -> void:
	if not has_loading_overlay():
		return

	if not _active_loading_overlay.has_method(loading_exit_transition_method):
		push_error(
			"Loading overlay root needs a '%s' function." % String(loading_exit_transition_method)
		)
		return

	await _active_loading_overlay.call(loading_exit_transition_method)


## Waits until the loading overlay has been visible for at least the requested duration.
func _wait_for_minimum_loading_time(started_msec: int, minimum_duration: float) -> void:
	if minimum_duration <= 0.0:
		return

	var elapsed_seconds: float = float(Time.get_ticks_msec() - started_msec) / 1000.0
	var remaining_seconds: float = minimum_duration - elapsed_seconds

	if remaining_seconds <= 0.0:
		return

	await get_tree().create_timer(remaining_seconds).timeout


## Prepares the music rule for the selected scene.
## This usually fades out the current music at the start of the visual transition.
func _prepare_scene_music_for_selected_scene() -> void:
	if not use_scene_music_manager:
		return

	var scene_music_manager: Node = get_node_or_null("/root/SceneMusicManager")

	if scene_music_manager == null:
		return

	if not scene_music_manager.has_method(scene_music_manager_prepare_method):
		push_error(
			"SceneMusicManager needs a '%s' function." % String(scene_music_manager_prepare_method)
		)
		return

	scene_music_manager.call(
		scene_music_manager_prepare_method, selected_scene_key, selected_scene_path
	)


## Starts the prepared music for the new scene.
## This should happen when the new scene starts being revealed.
func _play_prepared_scene_music() -> void:
	if not use_scene_music_manager:
		return

	var scene_music_manager: Node = get_node_or_null("/root/SceneMusicManager")

	if scene_music_manager == null:
		return

	if not scene_music_manager.has_method(scene_music_manager_play_prepared_method):
		push_error(
			(
				"SceneMusicManager needs a '%s' function."
				% String(scene_music_manager_play_prepared_method)
			)
		)
		return

	scene_music_manager.call(scene_music_manager_play_prepared_method)


## Creates a transparent full-screen blocker behind the active overlay.
## This prevents clicks from leaking into the scene underneath.
func _create_overlay_input_blocker(layer: CanvasLayer) -> void:
	_clear_overlay_input_blocker()

	var blocker: ColorRect = ColorRect.new()
	blocker.name = "OverlayInputBlocker"
	blocker.color = Color(0.0, 0.0, 0.0, 0.0)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.process_mode = Node.PROCESS_MODE_ALWAYS

	layer.add_child(blocker)

	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.position = Vector2.ZERO
	blocker.rotation = 0.0
	blocker.scale = Vector2.ONE
	blocker.pivot_offset = Vector2.ZERO

	_overlay_input_blocker = blocker


## Removes the transparent full-screen overlay input blocker.
func _clear_overlay_input_blocker() -> void:
	if _overlay_input_blocker != null and is_instance_valid(_overlay_input_blocker):
		_overlay_input_blocker.queue_free()

	_overlay_input_blocker = null


## Removes the active overlay without emitting overlay_cleared.
func _clear_overlay_without_signal() -> void:
	_remove_active_overlay()


## Removes the active overlay and returns whether there was one.
func _remove_active_overlay() -> bool:
	var had_overlay: bool = has_overlay()

	if had_overlay:
		_active_overlay.queue_free()

	_active_overlay = null

	_clear_overlay_input_blocker()

	return had_overlay


## Loads a scene path and checks whether it is actually a PackedScene.
func _get_packed_scene(scene_path: String) -> PackedScene:
	var resource: Resource = load(scene_path)

	if resource == null:
		push_error("Could not load scene: %s" % scene_path)
		return null

	var packed_scene: PackedScene = resource as PackedScene

	if packed_scene == null:
		push_error("Resource is not a PackedScene: %s" % scene_path)
		return null

	return packed_scene


## Gets or creates the overlay CanvasLayer.
func _get_overlay_layer() -> CanvasLayer:
	if _overlay_layer != null and is_instance_valid(_overlay_layer):
		_reset_canvas_layer_transform(_overlay_layer)
		return _overlay_layer

	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "SceneOverlayLayer"
	_overlay_layer.layer = overlay_layer_number
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS

	get_tree().root.add_child(_overlay_layer)

	_reset_canvas_layer_transform(_overlay_layer)

	return _overlay_layer


## Gets or creates the loading overlay CanvasLayer.
func _get_loading_overlay_layer() -> CanvasLayer:
	if _loading_overlay_layer != null and is_instance_valid(_loading_overlay_layer):
		_reset_canvas_layer_transform(_loading_overlay_layer)
		return _loading_overlay_layer

	_loading_overlay_layer = CanvasLayer.new()
	_loading_overlay_layer.name = "SceneLoadingOverlayLayer"
	_loading_overlay_layer.layer = loading_overlay_layer_number
	_loading_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS

	get_tree().root.add_child(_loading_overlay_layer)

	_reset_canvas_layer_transform(_loading_overlay_layer)

	return _loading_overlay_layer


## Resets a CanvasLayer so UI does not inherit weird transform behaviour.
func _reset_canvas_layer_transform(layer: CanvasLayer) -> void:
	layer.follow_viewport_enabled = false
	layer.offset = Vector2.ZERO
	layer.rotation = 0.0
	layer.scale = Vector2.ONE


## If the overlay root is a Control node, stretch it to the full screen.
func _fit_control_to_screen(scene_instance: Node) -> void:
	if not scene_instance is Control:
		return

	var control: Control = scene_instance as Control
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.position = Vector2.ZERO
	control.rotation = 0.0
	control.scale = Vector2.ONE
	control.pivot_offset = Vector2.ZERO


## Returns true if the string looks like a loadable scene path.
func _is_valid_scene_path(scene_path: String) -> bool:
	if scene_path.begins_with("uid://"):
		return true

	if scene_path.begins_with("res://"):
		return true

	return false
