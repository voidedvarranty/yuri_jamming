extends Control

# PHARAOH PHUNK MUSIC SETUP
#
# This scene lets the player preview and configure the music volume before
# entering the main menu.
#
# The volume slider updates GameData.music_volume. That same value controls:
# - The actual music volume through GameData
# - The background shader's visual intensity
# - The brightness and opacity of the falling sand particles
#
# MusicPlayer plays the preview track and provides its current playback
# position. The script sends this position to the background shader so its
# animations remain synchronized with the track's BPM and beat offset.
#
# When playback reaches beat_offset_seconds:
# - The Continue button fades into view
# - An initial sand burst is emitted
#
# BassScreenShake analyzes the Music audio bus and emits bass_hit whenever
# it detects a strong low-frequency hit. Each bass hit triggers another sand
# burst at several random horizontal positions.
#
# Sand particles are emitted manually through GPUParticles2D.emit_particle().
# The script determines their starting positions and velocities, while the
# GPUParticles2D node and its ParticleProcessMaterial control their texture,
# colour, gravity, scale, lifetime, and other visual properties.
#
# At full music volume, the sand reaches maximum_sand_modulate brightness
# and opacity. By default this is 0.75. Lowering the volume scales the sand
# down proportionally, while muting makes it invisible.
#
# USING A DIFFERENT TRACK
#
# To use this setup with another track, assign the new AudioStream to
# music_preview and update preview_bpm and beat_offset_seconds.
#
# preview_bpm is the BPM used by the shader animations.
# beat_offset_seconds is the playback position where the synchronized visual
# beat begins and where the Continue button and initial sand burst appear.
#
# The main track-specific component is the background shader on %Background . A different
# track can use a completely different visual design while keeping the same
# timing interface used by this script.
#
# A replacement shader should keep these uniforms:
#
# uniform float disco_amount;
# uniform float music_time;
# uniform float bpm;
# uniform float beat_offset;
# uniform float beats_per_bar;
#
# disco_amount receives the current music volume and controls the overall
# visual intensity.
#
# music_time receives the current playback position in seconds.
#
# bpm, beat_offset, and beats_per_bar provide the information needed to convert
# playback time into synchronized beat and bar timing.
#
# The replacement shader should also keep, or recreate, the timing calculation
# that converts music_time into beat_position:
#
# float adjusted_music_time = max(music_time - beat_offset, 0.0);
# float beat_position = adjusted_music_time * bpm / 60.0;
# float beat_phase = fract(beat_position);
# float beat_number = floor(beat_position);
#
# From there, the shader can use beat_phase, beat_number, and the bar position
# to drive any new visual effects. The Egyptian colours, pyramids, stars, waves,
# and other current visuals can all be removed or replaced.
#
# BassScreenShake does not use the shader timing. It reads the live audio from
# the Music bus, so it continues to react to bass hits in the new track. Its
# frequency range and detection values can be adjusted separately when a track
# has significantly different bass characteristics.
#
# Used global systems:
# MusicPlayer, GameData, and SceneManager.

@export_group("Music")

@export var music_preview: AudioStream
@export var preview_bpm: float = 120.0
@export var beat_offset_seconds: float = 6.0


@export_group("Scene")

@export var continue_fade_duration: float = 0.35
@export var scene_transition_duration: float = 0.5


@export_group("Sand Burst")

# Horizontal area where the random sand patches can appear.
@export var sand_emission_width: float = 1100.0

# Three random patches per bass hit.
@export var sand_spots_per_burst: int = 3

# Amount of sand emitted from each patch.
@export var sand_particles_per_spot: int = 30

# How widely particles spread around each random patch.
@export var sand_spot_spread_x: float = 20.0
@export var sand_spot_spread_y: float = 6.0

# Initial downward velocity.
@export var sand_velocity_min: float = 40.0
@export var sand_velocity_max: float = 100.0

# Small amount of sideways movement.
@export var sand_sideways_velocity: float = 20.0

# Maximum sand brightness and opacity at full volume.
@export_range(0.0, 1.0, 0.01)
var maximum_sand_modulate: float = 0.75


@onready var background: ColorRect = %Background
@onready var music_slider: HSlider = %MusicSlider
@onready var mute_button: Button = %MuteButton
@onready var continue_button: Button = %ContinueButton

@onready var sand_particles: GPUParticles2D = %SandParticles
@onready var bass_screen_shake: BassScreenShake = %BassScreenShake


var disco_material: ShaderMaterial
var volume_before_mute: float = 0.5
var drop_triggered: bool = false


func _ready() -> void:
	_setup_text()
	_setup_shader()
	_setup_slider()
	_setup_buttons()
	_setup_sand()
	_hide_continue_button()
	_play_music()

	music_slider.grab_focus()


func _process(_delta: float) -> void:
	var music_time := MusicPlayer.get_current_playback_position()

	disco_material.set_shader_parameter(
		"music_time",
		music_time
	)

	if not drop_triggered and music_time >= beat_offset_seconds:
		_trigger_beat_drop()


# SETUP


func _setup_text() -> void:
	%TitleLabel.text = "HEY! BEFORE WE ENTER THE TOMB..."
	%DescriptionLabel.text = "How much pharaoh phunk can you handle?"
	%MusicLabel.text = "Dusty Sarcophagus"
	%MusicLabel2.text = "Full Ankha"


func _setup_shader() -> void:
	disco_material = background.material.duplicate()
	background.material = disco_material

	disco_material.set_shader_parameter(
		"bpm",
		preview_bpm
	)

	disco_material.set_shader_parameter(
		"beat_offset",
		beat_offset_seconds
	)

	disco_material.set_shader_parameter(
		"beats_per_bar",
		4.0
	)

	disco_material.set_shader_parameter(
		"music_time",
		0.0
	)


func _setup_slider() -> void:
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.01

	music_slider.set_value_no_signal(
		GameData.music_volume
	)

	if GameData.music_volume > 0.0:
		volume_before_mute = GameData.music_volume

	_update_visual_amount(GameData.music_volume)
	_update_mute_text()

	music_slider.value_changed.connect(
		_on_music_slider_changed
	)


func _setup_buttons() -> void:
	mute_button.pressed.connect(
		_toggle_music_mute
	)

	continue_button.pressed.connect(
		_continue_to_main_menu
	)


func _setup_sand() -> void:
	sand_particles.emitting = false
	sand_particles.local_coords = true
	sand_particles.amount = 600

	_update_sand_brightness(GameData.music_volume)

	bass_screen_shake.bass_hit.connect(
		_on_bass_hit
	)


func _play_music() -> void:
	MusicPlayer.play(
		music_preview,
		true,
		false,
		0.5,
		false,
		0.0,
		0.0,
		false,
		true
	)


# BEAT EFFECTS


func _trigger_beat_drop() -> void:
	drop_triggered = true

	_reveal_continue_button()
	_burst_sand()


func _on_bass_hit(_strength: float) -> void:
	_burst_sand()


func _burst_sand() -> void:
	var emission_flags := (
		GPUParticles2D.EMIT_FLAG_POSITION
		| GPUParticles2D.EMIT_FLAG_VELOCITY
	)

	for _spot: int in range(sand_spots_per_burst):
		var spot_position := Vector2(
			randf_range(
				-sand_emission_width / 2.0,
				sand_emission_width / 2.0
			),
			0.0
		)

		for _particle: int in range(sand_particles_per_spot):
			var particle_position := spot_position + Vector2(
				randf_range(
					-sand_spot_spread_x,
					sand_spot_spread_x
				),
				randf_range(
					-sand_spot_spread_y,
					sand_spot_spread_y
				)
			)

			var particle_velocity := Vector2(
				randf_range(
					-sand_sideways_velocity,
					sand_sideways_velocity
				),
				randf_range(
					sand_velocity_min,
					sand_velocity_max
				)
			)

			sand_particles.emit_particle(
				Transform2D(
					0.0,
					particle_position
				),
				particle_velocity,
				Color.WHITE,
				Color.WHITE,
				emission_flags
			)


# MUSIC VOLUME


func _on_music_slider_changed(value: float) -> void:
	GameData.set_music_volume(value)
	_update_visual_amount(value)

	if value > 0.0:
		volume_before_mute = value

	_update_mute_text()


func _toggle_music_mute() -> void:
	if GameData.music_volume > 0.0:
		volume_before_mute = GameData.music_volume
		_set_music_volume(0.0)
	else:
		_set_music_volume(volume_before_mute)


func _set_music_volume(value: float) -> void:
	GameData.set_music_volume(value)
	music_slider.set_value_no_signal(value)

	_update_visual_amount(value)
	_update_mute_text()


func _update_visual_amount(value: float) -> void:
	_update_disco_amount(value)
	_update_sand_brightness(value)


func _update_disco_amount(value: float) -> void:
	disco_material.set_shader_parameter(
		"disco_amount",
		value
	)


func _update_sand_brightness(value: float) -> void:
	var sand_amount := value * maximum_sand_modulate

	sand_particles.modulate = Color(
		sand_amount,
		sand_amount,
		sand_amount,
		sand_amount
	)


func _update_mute_text() -> void:
	mute_button.text = (
		"BRING BACK THE PHUNK"
		if GameData.music_volume <= 0.0
		else "SHHH, I'M GAMING"
	)


# CONTINUE BUTTON


func _hide_continue_button() -> void:
	continue_button.modulate.a = 0.0
	continue_button.disabled = true
	continue_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	continue_button.focus_mode = Control.FOCUS_NONE


func _reveal_continue_button() -> void:
	continue_button.disabled = false
	continue_button.mouse_filter = Control.MOUSE_FILTER_STOP
	continue_button.focus_mode = Control.FOCUS_ALL

	create_tween().tween_property(
		continue_button,
		"modulate:a",
		1.0,
		continue_fade_duration
	)


func _continue_to_main_menu() -> void:
	mute_button.disabled = true
	continue_button.disabled = true

	MusicPlayer.stop_audio(
		music_preview,
		true,
		scene_transition_duration
	)

	SceneManager.go(
		"main_menu",
		scene_transition_duration
	)
