class_name CraftingCog
extends Control

enum CogState { HIDDEN, PARTIAL, READY, BLOCKED }

@export var teeth: int = 8
@export var idle_color := Color(0.1, 0.1, 0.1, 0.55)
@export var outline_color := Color(0.9, 0.9, 0.85, 0.9)
@export var progress_color := Color(0.95, 0.85, 0.45, 1.0)
@export var ready_color := Color(1.0, 0.8, 0.25, 1.0)
@export var blocked_color := Color(0.85, 0.25, 0.2, 1.0)

var state: CogState = CogState.HIDDEN:
	set(value):
		state = value
		visible = state != CogState.HIDDEN
		queue_redraw()
var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()
var hovered := false:
	set(value):
		hovered = value
		queue_redraw()

var _angle := 0.0
var _pop := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(26, 26)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	if state == CogState.READY:
		_angle += delta * (3.0 if hovered else 1.2)
		queue_redraw()
	if _pop > 0.0:
		_pop = maxf(_pop - delta * 3.0, 0.0)
		_angle += delta * 12.0
		queue_redraw()


func play_craft_effect() -> void:
	_pop = 1.0
	queue_redraw()


func is_mouse_over() -> bool:
	return visible and get_global_rect().grow(3).has_point(get_global_mouse_position())


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	radius *= 1.0 + (0.15 if hovered else 0.0) + _pop * 0.25

	var fill := idle_color
	match state:
		CogState.READY:
			fill = ready_color
		CogState.BLOCKED:
			fill = blocked_color

	var points := _gear_points(center, radius, _angle)
	draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, outline_color, 1.0)
	draw_circle(center, radius * 0.28, Color(0, 0, 0, 0.6))

	if state == CogState.PARTIAL:
		draw_arc(center, radius + 2.0, -PI * 0.5, -PI * 0.5 + TAU * progress, 32, progress_color, 2.0)
	elif state == CogState.BLOCKED:
		var r := radius * 0.35
		draw_line(center + Vector2(-r, -r), center + Vector2(r, r), Color.WHITE, 2.0)
		draw_line(center + Vector2(r, -r), center + Vector2(-r, r), Color.WHITE, 2.0)


func _gear_points(center: Vector2, radius: float, angle: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var inner := radius * 0.72
	var steps := teeth * 4
	for i in steps:
		var a := angle + TAU * float(i) / float(steps)
		var r := radius if (i % 4) < 2 else inner
		points.append(center + Vector2(cos(a), sin(a)) * r)
	return points
