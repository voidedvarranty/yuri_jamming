class_name Crosshair
extends Control

@export var color := Color(1.0, 1.0, 1.0, 0.85)
@export var highlight_color := Color(1.0, 0.85, 0.3, 1.0)
@export var dot_radius: float = 1.5
@export var ring_radius: float = 5.0

var highlighted := false:
	set(value):
		if value != highlighted:
			highlighted = value
			queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var tint := highlight_color if highlighted else color
	draw_circle(Vector2.ZERO, dot_radius + 1.0, Color(0, 0, 0, 0.6))
	draw_circle(Vector2.ZERO, dot_radius, tint)
	if highlighted:
		draw_arc(Vector2.ZERO, ring_radius + 1.0, 0.0, TAU, 24, Color(0, 0, 0, 0.5), 1.0)
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 24, tint, 1.0)
