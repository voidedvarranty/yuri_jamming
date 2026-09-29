extends Node2D

@export_group("Movement")
# How fast the test character moves.
@export var move_speed: float = 120.0

# Keeps diagonal movement from being faster than straight movement.
@export var normalize_diagonal_movement: bool = true

@export_group("Sprite Direction")
# Flips the sprite when moving left or right.
@export var flip_sprite_on_horizontal_movement: bool = true

@export_group("Poop")
# Optional poop scene to spawn.
# If this is empty, the script creates a fallback poop label.
@export var poop_scene: PackedScene

# How much score each poop gives.
@export var poop_score_value: int = 1

# Where poop spawns relative to the chinchilla.
@export var poop_spawn_offset: Vector2 = Vector2(0.0, 12.0)

# Optional parent for spawned poop.
# Usually set this to a PoopContainer node to keep the scene tree clean.
@export var poop_parent_path: NodePath

@export_group("Chinchilla Text Noises")
# How long the random popup text stays visible.
@export var popup_duration: float = 0.65

# Toggles random text when moving.
@export var show_movement_noises: bool = true

# Toggles random text when pressing action buttons.
@export var show_action_noises: bool = true

# German.
@export var chinchilla_noises: PackedStringArray = [
	"Fisch",
	"Taube",
	"Genau",
	"faltbare Giraffe",
	"verbrauchen",
	"ABER WIESO?!",
	"sind lebensmüde",
]

# Counts down until the popup text hides itself.
var popup_timer: float = 0.0

# Very serious poop economy.
var poop_score: int = 0
var poop_count: int = 0

# Used to pick random chinchilla noises.
var random_number_generator: RandomNumberGenerator = RandomNumberGenerator.new()

# Main visual character and popup text.
# get_node_or_null() keeps the scene from crashing if someone renames or removes these nodes.
# The "as" part tells Godot what type the node should be.
@onready var animated_sprite: AnimatedSprite2D = (
	get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
)
@onready var popup_label: Label = get_node_or_null("%PopupLabel") as Label


func _ready() -> void:
	random_number_generator.randomize()
	_setup_popup_label()

	# Tell listeners the starting score.
	# has_signal keeps this test script from exploding if EventBus is not fully set up yet.
	if EventBus.has_signal("score_changed"):
		EventBus.score_changed.emit(poop_score)


func _process(delta: float) -> void:
	_update_movement(delta)
	_update_action_noises()
	_update_popup_timer(delta)


# Clears and hides the popup label at the start.
func _setup_popup_label() -> void:
	if popup_label == null:
		return

	popup_label.text = ""
	popup_label.visible = false


# Handles movement, sprite direction, and movement noises.
func _update_movement(delta: float) -> void:
	var move_direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)

	if normalize_diagonal_movement and move_direction.length() > 1.0:
		move_direction = move_direction.normalized()

	position += move_direction * move_speed * delta

	_update_sprite_direction(move_direction)

	if show_movement_noises:
		_update_movement_noises()


# Flips the sprite based on horizontal movement.
func _update_sprite_direction(move_direction: Vector2) -> void:
	if animated_sprite == null:
		return

	if not flip_sprite_on_horizontal_movement:
		return

	if move_direction.x < 0.0:
		animated_sprite.flip_h = true

	if move_direction.x > 0.0:
		animated_sprite.flip_h = false


# Shows random noises when movement actions are pressed.
func _update_movement_noises() -> void:
	if Input.is_action_just_pressed("move_left"):
		show_random_chinchilla_noise()

	if Input.is_action_just_pressed("move_right"):
		show_random_chinchilla_noise()

	if Input.is_action_just_pressed("move_up"):
		show_random_chinchilla_noise()

	if Input.is_action_just_pressed("move_down"):
		show_random_chinchilla_noise()


# Handles primary, secondary, and pause test inputs.
func _update_action_noises() -> void:
	if not show_action_noises:
		return

	if Input.is_action_just_pressed("action_primary"):
		show_random_chinchilla_noise()

	# By default, action_secondary is Shift.
	# This spawns poop, updates the score, and tells EventBus about the incident.
	if Input.is_action_just_pressed("action_secondary"):
		spawn_poop()
		show_random_chinchilla_noise()

	if Input.is_action_just_pressed("pause"):
		show_random_chinchilla_noise()


# Spawns poop, updates poop stats, and emits EventBus signals.
func spawn_poop() -> void:
	var poop_instance: Node2D = _create_poop_instance()

	if poop_instance == null:
		return

	var poop_parent: Node = _get_poop_parent()
	poop_parent.add_child(poop_instance)

	poop_instance.global_position = global_position + poop_spawn_offset
	poop_instance.name = "Poop"

	poop_count += 1
	poop_score += poop_score_value

	# Tell any listeners that poop happened.
	if EventBus.has_signal("chinchilla_pooped"):
		EventBus.chinchilla_pooped.emit(poop_count, poop_instance.global_position)

	# Tell any score UI to update itself.
	if EventBus.has_signal("score_changed"):
		EventBus.score_changed.emit(poop_score)


# Creates the assigned poop scene, or falls back to emergency text poop.
func _create_poop_instance() -> Node2D:
	if poop_scene == null:
		return _create_fallback_poop()

	var instance: Node = poop_scene.instantiate()

	if instance is Node2D:
		return instance as Node2D

	instance.queue_free()
	push_warning("Poop scene root must be Node2D.")
	return null


# Creates fallback poop if no poop scene is assigned.
# Not beautiful.
func _create_fallback_poop() -> Node2D:
	var fallback_poop: Node2D = Node2D.new()
	fallback_poop.name = "Poop"

	var label: Label = Label.new()
	label.text = "poop"
	label.position = Vector2(-12.0, -8.0)
	fallback_poop.add_child(label)

	return fallback_poop


# Finds where poop should be spawned in the scene tree.
func _get_poop_parent() -> Node:
	if poop_parent_path != NodePath():
		var selected_parent: Node = get_node_or_null(poop_parent_path)

		if selected_parent != null:
			return selected_parent

	var parent_node: Node = get_parent()

	if parent_node != null:
		return parent_node

	return get_tree().current_scene


# Picks a random chinchilla noise and shows it.
func show_random_chinchilla_noise() -> void:
	if chinchilla_noises.is_empty():
		show_popup("Genau")
		return

	var random_index: int = random_number_generator.randi_range(
		0,
		chinchilla_noises.size() - 1
	)
	show_popup(chinchilla_noises[random_index])


# Shows popup text and resets the popup timer.
func show_popup(text: String) -> void:
	if popup_label == null:
		return

	popup_label.text = text
	popup_label.visible = true
	popup_timer = popup_duration


# Hides the popup text after the timer runs out.
func _update_popup_timer(delta: float) -> void:
	if popup_label == null:
		return

	if popup_timer <= 0.0:
		return

	popup_timer -= delta

	if popup_timer <= 0.0:
		popup_label.visible = false
