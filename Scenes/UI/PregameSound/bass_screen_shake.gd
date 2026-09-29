extends Node

class_name BassScreenShake

# BASS-REACTIVE SCREEN SHAKE
#
# This node listens to the low-frequency energy passing through the Music
# audio bus and triggers screenshake when it detects a sudden bass hit.
#
# The Music bus contains an AudioEffectSpectrumAnalyzer. The script uses
# analyzer_effect_index to retrieve its runtime instance through
# AudioServer.get_bus_effect_instance().
#
# The analyzer provides live frequency data from the audio passing through
# the bus. This script reads the range between minimum_frequency_hz and
# maximum_frequency_hz, set to 30–95 Hz by default to focus on kicks,
# sub-bass, and 808s.
#
# Because detection uses the live audio from the Music bus rather than
# track-specific timestamps, this node works with any music track routed
# through that bus. To reuse it, copy the node into another scene and assign
# the Control node that should move to shake_target.
#
# Each frame, the script:
# - Reads the current strength of the selected bass frequencies
# - Converts that strength to decibels
# - Compares it with the recent bass baseline
# - Checks whether it is loud enough and rose quickly enough
# - Triggers a bass hit when all detection conditions are met
#
# trigger_threshold_db sets the minimum bass volume required for a hit.
# required_rise_db prevents sustained bass from repeatedly triggering the
# effect by requiring a sudden increase above the recent baseline.
# trigger_cooldown limits how often new hits can be detected.
#
# baseline_follow_speed controls how quickly the recent bass baseline follows
# changes in the music. A slower baseline responds more to gradual rises,
# while a faster baseline focuses more strongly on sudden transients.
#
# When a bass hit is detected, its decibel level is converted into a shake
# strength between minimum_shake_strength and maximum_shake_strength.
# Louder bass hits therefore produce stronger screenshake.
#
# The resulting shake strength is also multiplied by the current Music bus
# volume. Full volume gives the full calculated shake, lower volume weakens
# it proportionally, and muting the bus removes the shake entirely.
#
# The bass_hit signal emits the final volume-scaled strength. Other nodes
# connect to this signal to trigger synchronized effects, such as sand
# particle bursts.
#
# The screenshake offsets shake_target from its original position every frame.
# shake_decay returns the target toward rest, while horizontal_shake_ratio
# controls the amount of horizontal movement compared with vertical movement.


signal bass_hit(strength: float)


@export var shake_target: Control

@export var music_bus_name: StringName = &"Music"
@export var analyzer_effect_index: int = 0

@export var minimum_frequency_hz: float = 30.0
@export var maximum_frequency_hz: float = 95.0

@export var trigger_threshold_db: float = -24.0
@export var required_rise_db: float = 6.0
@export var trigger_cooldown: float = 0.14
@export var baseline_follow_speed: float = 3.0

@export var minimum_shake_strength: float = 3.0
@export var maximum_shake_strength: float = 8.0
@export var maximum_detection_db: float = -8.0

@export var shake_decay: float = 30.0
@export var horizontal_shake_ratio: float = 0.35


var analyzer: AudioEffectSpectrumAnalyzerInstance
var music_bus_index: int

var original_position: Vector2
var shake_strength: float = 0.0
var cooldown: float = 0.0
var bass_baseline_db: float = -80.0


func _ready() -> void:
	original_position = shake_target.position

	music_bus_index = AudioServer.get_bus_index(
		music_bus_name
	)

	analyzer = AudioServer.get_bus_effect_instance(
		music_bus_index,
		analyzer_effect_index
	) as AudioEffectSpectrumAnalyzerInstance


func _process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)

	_detect_bass(delta)
	_update_screenshake(delta)


func _detect_bass(delta: float) -> void:
	var magnitude := analyzer.get_magnitude_for_frequency_range(
		minimum_frequency_hz,
		maximum_frequency_hz,
		AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX
	)

	var bass_linear := maxf(
		magnitude.x,
		magnitude.y
	)

	var bass_db := linear_to_db(
		maxf(bass_linear, 0.00001)
	)

	var bass_rise := bass_db - bass_baseline_db

	if (
		cooldown <= 0.0
		and bass_db >= trigger_threshold_db
		and bass_rise >= required_rise_db
	):
		_trigger_bass_hit(bass_db)

	bass_baseline_db = lerpf(
		bass_baseline_db,
		bass_db,
		baseline_follow_speed * delta
	)


func _trigger_bass_hit(bass_db: float) -> void:
	var loudness := clampf(
		inverse_lerp(
			trigger_threshold_db,
			maximum_detection_db,
			bass_db
		),
		0.0,
		1.0
	)

	var new_strength := lerpf(
		minimum_shake_strength,
		maximum_shake_strength,
		loudness
	)

	var volume_multiplier := (
		0.0
		if AudioServer.is_bus_mute(music_bus_index)
		else db_to_linear(
			AudioServer.get_bus_volume_db(music_bus_index)
		)
	)

	new_strength *= volume_multiplier

	shake_strength = maxf(
		shake_strength,
		new_strength
	)

	cooldown = trigger_cooldown

	bass_hit.emit(new_strength)


func _update_screenshake(delta: float) -> void:
	shake_strength = move_toward(
		shake_strength,
		0.0,
		shake_decay * delta
	)

	var shake_offset := Vector2(
		randf_range(-1.0, 1.0) * horizontal_shake_ratio,
		randf_range(-1.0, 1.0)
	)

	shake_target.position = (
		original_position
		+ shake_offset * shake_strength
	)
