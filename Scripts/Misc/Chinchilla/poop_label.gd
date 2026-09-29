extends Label

# Text shown before the number.
# Example: "Poop score: 3"
@export var score_prefix: String = "Poop score: "


func _ready() -> void:
	# Listen for score updates from EventBus.
	# This means the label does not need to know who changed the score.
	EventBus.score_changed.connect(_on_score_changed)

	# Start at 0 so the label is not empty before the first poop incident.
	_on_score_changed(0)


# Updates the label when the score changes.
func _on_score_changed(new_score: int) -> void:
	text = score_prefix + str(new_score)
