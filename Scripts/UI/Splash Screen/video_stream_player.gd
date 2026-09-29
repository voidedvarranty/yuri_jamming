extends VideoStreamPlayer

@export var logo_player: VideoStreamPlayer

var regular_logo: VideoStream = preload("uid://bgkcrj18hmoxy")


func _ready() -> void:
	# Plays the logo video and opens the groove setup when it ends.
	if not finished.is_connected(_on_finished):
		finished.connect(_on_finished)

	logo_player.stream = regular_logo
	logo_player.play()


func _on_finished() -> void:
	SceneManager.go("groove")
