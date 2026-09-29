extends Control

# This is the loading / transition overlay.
# It fades to black when entering, then reveals the next scene.
# If cutout_texture is assigned, the reveal uses a shader cut-out shape.
# If cutout_texture is empty, it just fades back out normally.

@export var cutout_texture: Texture2D

@export_group("Transition Timing")
# How long it takes to fade to black before the new scene appears. Exported for tweaking.
@export var fade_to_black_duration: float = 0.35

# How long it takes to reveal the new scene. Exported for tweaking.
@export var reveal_duration: float = 0.75

@export_group("Cut-out")
# Starting size of the cut-out reveal. Exported for tweaking.
@export var start_reveal_scale: float = 0.01

# Final size of the cut-out reveal. Exported for tweaking.
@export var end_reveal_scale: float = 4.0

# Where the reveal starts on the screen.
# Vector2(0.5, 0.5) means the centre of the screen. Exported for tweaking.
@export var reveal_center: Vector2 = Vector2(0.5, 0.5)

# Controls which parts of the cut-out texture count as visible. Exported for tweaking.
@export_range(0.0, 1.0, 0.01) var alpha_threshold: float = 0.5

# Softens the edge of the cut-out. Exported for tweaking.
@export_range(0.0, 0.25, 0.01) var edge_softness: float = 0.03

@export_group("Nodes")
# The ColorRect that covers the screen.
# This needs a ShaderMaterial assigned in the inspector. Exported for easier use in code.
@export var overlay_rect: ColorRect

# Duplicated material used by this transition.
# This avoids editing the original shared material resource.
var transition_material: ShaderMaterial = null

# Current transition tween.
# Stored so we can kill it before starting a new one.
var transition_tween: Tween = null


func _ready() -> void:
	# Keep the loading screen running even when the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if not _setup_overlay_rect():
		return

	_apply_shader_settings()
	_set_fade_alpha(0.0)
	_set_reveal_enabled(false)
	_set_reveal_scale(start_reveal_scale)


func _notification(what: int) -> void:
	# Re-apply aspect ratio settings if the window size changes.
	if what == NOTIFICATION_RESIZED:
		_apply_shader_settings()


# Sets up the overlay rect and gives it its own material instance.
func _setup_overlay_rect() -> bool:
	if overlay_rect == null:
		#Pushing errors is usually good.
		#It allows you to see when things go wrong in the debugger.
		#USEFUL PATTERN :D
		push_error("LoadingScreen needs an overlay_rect assigned.")
		return false

	overlay_rect.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var source_material: ShaderMaterial = overlay_rect.material as ShaderMaterial

	if source_material == null:
		push_error("overlay_rect needs a ShaderMaterial.")
		return false

	transition_material = source_material.duplicate() as ShaderMaterial
	overlay_rect.material = transition_material

	return true


# Fades the overlay to black before the scene changes underneath.
func start_enter_transition() -> void:
	if transition_material == null:
		return

	_kill_transition_tween()

	_apply_shader_settings()
	_set_reveal_enabled(false)
	_set_reveal_scale(start_reveal_scale)
	_set_fade_alpha(0.0)

	transition_tween = create_tween()
	transition_tween.tween_method(_set_fade_alpha, 0.0, 1.0, max(fade_to_black_duration, 0.0))

	await transition_tween.finished

	_set_fade_alpha(1.0)
	transition_tween = null


# Reveals the new scene after it has loaded underneath.
func start_exit_transition() -> void:
	if transition_material == null:
		return

	_kill_transition_tween()

	_apply_shader_settings()
	_set_fade_alpha(1.0)

	if cutout_texture == null:
		await _fade_back_without_cutout()
		return

	await _reveal_with_cutout()


# Used when there is no cut-out texture.
# Plain boring fade. Perfectly valid.
func _fade_back_without_cutout() -> void:
	transition_tween = create_tween()
	transition_tween.tween_method(_set_fade_alpha, 1.0, 0.0, max(reveal_duration, 0.0))

	await transition_tween.finished

	_set_fade_alpha(0.0)
	transition_tween = null


# Uses the shader mask to reveal the new scene with a growing cut-out.
func _reveal_with_cutout() -> void:
	_set_reveal_enabled(true)
	_set_reveal_scale(start_reveal_scale)

	transition_tween = create_tween()
	transition_tween.tween_method(
		_set_reveal_scale, start_reveal_scale, end_reveal_scale, max(reveal_duration, 0.0)
	)

	await transition_tween.finished

	_set_reveal_scale(end_reveal_scale)
	transition_tween = null


# Sends all exported shader settings to the material.
func _apply_shader_settings() -> void:
	if transition_material == null:
		return

	transition_material.set_shader_parameter("mask_texture", cutout_texture)
	transition_material.set_shader_parameter("reveal_center", reveal_center)
	transition_material.set_shader_parameter("alpha_threshold", alpha_threshold)
	transition_material.set_shader_parameter("edge_softness", edge_softness)
	transition_material.set_shader_parameter("screen_aspect", _get_screen_aspect())
	transition_material.set_shader_parameter("mask_aspect", _get_mask_aspect())


# Gets the current viewport aspect ratio. #Makes this not break when changing resolutions etc.
func _get_screen_aspect() -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	var safe_height: float = max(viewport_size.y, 1.0)

	return viewport_size.x / safe_height


# Gets the cut-out texture aspect ratio.
func _get_mask_aspect() -> float:
	if cutout_texture == null:
		return 1.0

	var texture_height: float = max(float(cutout_texture.get_height()), 1.0)

	return float(cutout_texture.get_width()) / texture_height


# Sets the black overlay opacity.
func _set_fade_alpha(value: float) -> void:
	if transition_material == null:
		return

	transition_material.set_shader_parameter("fade_alpha", clampf(value, 0.0, 1.0))


# Enables or disables the cut-out reveal.
func _set_reveal_enabled(value: bool) -> void:
	if transition_material == null:
		return

	transition_material.set_shader_parameter("reveal_enabled", value)


# Sets the current reveal size.
func _set_reveal_scale(value: float) -> void:
	if transition_material == null:
		return

	transition_material.set_shader_parameter("reveal_scale", max(value, 0.0))


# Stops the current transition tween if one is running.
func _kill_transition_tween() -> void:
	if transition_tween == null:
		return

	transition_tween.kill()
	transition_tween = null
