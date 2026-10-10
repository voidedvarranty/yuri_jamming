# Crosshair - centre-screen reticle drawn with _draw (no textures).
# The control is zero-sized and anchored to the screen centre, so local (0, 0) is the centre.
# ItemInteractor toggles `highlighted` when a pickup target is under (or near) the reticle.

class_name Crosshair
extends Control

@export var color := Color(1.0, 1.0, 1.0, 0.85)
@export var highlight_color := Color(1.0, 0.85, 0.3, 1.0)
@export var dot_radius: float = 1.5
@export var ring_radius: float = 5.0

# Setter only redraws on actual change.
var highlighted := false:
	set(value):
		if value != highlighted:
			highlighted = value
			queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var tint := highlight_color if highlighted else color
	# Dark backing circle keeps the dot readable on bright backgrounds.
	draw_circle(Vector2.ZERO, dot_radius + 1.0, Color(0, 0, 0, 0.6))
	draw_circle(Vector2.ZERO, dot_radius, tint)
	# Ring = 'can pick up', with the same dark outline trick.
	if highlighted:
		draw_arc(Vector2.ZERO, ring_radius + 1.0, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 1.0)
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 24, tint, 1.0)
