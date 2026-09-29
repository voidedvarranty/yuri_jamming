@tool  #https://docs.godotengine.org/en/stable/tutorials/plugins/running_code_in_the_editor.html
extends Control

# This script is used for a specific card scene that is usually part of another scene.
# Because of that, it assumes the required child nodes exist:
# Spin, Spin/Name, Spin/Desc, Spin/Pic, and mousedetect.
# If those nodes are renamed or removed, this script should be updated too.
# This keeps the code simpler than using get_node_or_null() everywhere.

@export_multiline var card_title: String = "insert name":
	set(value):
		card_title = value
		_update_visuals_when_ready()

@export_multiline var card_description: String = "insert description":
	set(value):
		card_description = value
		_update_visuals_when_ready()

@export var title_font_size: int = 24:
	set(value):
		title_font_size = value
		_update_visuals_when_ready()

@export var description_font_size: int = 8:
	set(value):
		description_font_size = value
		_update_visuals_when_ready()

@export var picture_texture: Texture2D:
	set(value):
		picture_texture = value
		_update_visuals_when_ready()

@export var picture_y_offset: float = 27.0:
	set(value):
		picture_y_offset = value
		_update_visuals_when_ready()

@export var show_picture: bool = true:
	set(value):
		show_picture = value
		_update_visuals_when_ready()

# Card nodes.
@onready var spinning_content: Node2D = $Spin
@onready var title_label: Label = $Spin/Name
@onready var description_label: Label = $Spin/Desc
@onready var picture_sprite: Sprite2D = $Spin/Pic
@onready var mouse_area: Area2D = $mousedetect

# Spin state.
var spin_angle: float = PI / 2.0
var spin_velocity: float = 0.0

# Mouse state.
var is_mouse_inside: bool = false
var previous_mouse_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_update_visuals()
	previous_mouse_position = get_global_mouse_position()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var current_mouse_position: Vector2 = get_global_mouse_position()
	var safe_delta: float = max(delta, 0.0001)

	# Dragging the mouse horizontally over the card gives it spin velocity.
	if is_mouse_inside:
		var mouse_movement_x: float = previous_mouse_position.x - current_mouse_position.x
		spin_velocity = mouse_movement_x * 0.0001 / safe_delta

	previous_mouse_position = current_mouse_position

	# Apply spin, slow it down, and softly pull it back to the front.
	spin_angle += spin_velocity
	spin_velocity *= max(0.0, 1.0 - (2.0 * delta))

	var target_spin_angle: float = round((spin_angle - PI / 2.0) / TAU) * TAU + PI / 2.0
	spin_angle = lerpf(spin_angle, target_spin_angle, delta * 0.5)

	# Fake a 3D card spin by squashing the X scale.
	var horizontal_scale: float = sin(spin_angle)
	var vertical_scale: float = 1.0 + 0.1 * (1.0 - pow(horizontal_scale, 2.0))

	spinning_content.scale = Vector2(horizontal_scale, vertical_scale)


# Updates visuals after exported values change in the editor.
func _update_visuals_when_ready() -> void:
	if is_inside_tree():
		call_deferred("_update_visuals")


# Applies text, font sizes, image, and mouse area size.
func _update_visuals() -> void:
	title_label.text = card_title
	description_label.text = card_description

	title_label.add_theme_font_size_override("font_size", title_font_size)
	description_label.add_theme_font_size_override("font_size", description_font_size)

	if show_picture:
		mouse_area.scale.y = 1.0
		picture_sprite.show()
		picture_sprite.texture = picture_texture
		picture_sprite.position.y = picture_y_offset
	else:
		mouse_area.scale.y = 0.4
		picture_sprite.hide()


func _on_mousedetect_mouse_entered() -> void:
	is_mouse_inside = true


func _on_mousedetect_mouse_exited() -> void:
	is_mouse_inside = false
