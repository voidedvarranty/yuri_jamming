shader_type canvas_item;
render_mode unshaded;

// PHARAOH PHUNK MUSIC-REACTIVE BACKGROUND
//
// This CanvasItem shader creates the animated Egyptian background used by the
// music setup scene. It combines several visual layers:
//
// - Slow colour waves in gold, lapis, turquoise, and red
// - A large central pyramid emblem
// - Moving pyramid borders along the top and bottom
// - Stars that flash in rotating groups on each beat
// - Subtle beat and downbeat brightness pulses
// - A vignette that darkens the edges of the screen
//
// The scene script supplies the current music playback position, BPM, beat
// offset, beats per bar, and music-volume value through these uniforms:
//
// disco_amount
// Controls the overall strength of the shader. The music volume slider writes
// directly to this value. Lower volume produces a darker and less active
// background, while muting reduces the visual effect to zero.
//
// music_time
// Contains the current playback position of the preview track in seconds.
// The scene script updates this every frame using MusicPlayer.
//
// bpm
// Contains the tempo of the current track. The shader uses it to convert
// music_time from seconds into musical beats.
//
// beat_offset
// Contains the playback time where beat synchronization begins. Before this
// point, beat pulses remain inactive. For the current track, the beat begins
// after the introduction at approximately six seconds.
//
// beats_per_bar
// Determines the length of a musical bar. This is used to identify the first
// beat of each bar and create a stronger downbeat response.
//
// The MUSIC TIMING section converts playback time into these useful values:
//
// beat_position
// The continuous number of beats that have passed since beat_offset.
//
// beat_phase
// The current position within one beat, ranging from 0.0 to almost 1.0.
//
// beat_number
// The whole-number index of the current beat.
//
// beat_in_bar
// The position of the current beat inside the musical bar.
//
// beat_pulse
// A short pulse that begins strongly on every beat and quickly fades.
//
// downbeat_pulse
// A stronger pulse that only occurs on the first beat of each bar.
//
// musical_motion
// A slower continuous movement value measured across several beats. It drives
// effects that should flow with the music rather than flash on every beat.
//
// The visual sections below the timing calculation use these values in
// different ways. The colour waves use musical_motion, the pyramid outlines
// react to beat and downbeat pulses, the borders scroll according to the beat
// position, and the stars divide themselves into groups that flash on
// alternating beats.
//
// USING THIS TIMING SYSTEM FOR ANOTHER SHADER
//
// A different track can use a completely different visual design while
// retaining the same synchronization system. Keep these uniforms:
//
// uniform float disco_amount;
// uniform float music_time;
// uniform float bpm;
// uniform float beat_offset;
// uniform float beats_per_bar;
//
// Also keep the calculations in the MUSIC TIMING section that produce
// beat_position, beat_phase, beat_number, beat_in_bar, beat_pulse,
// downbeat_pulse, and musical_motion.
//
// Everything after the timing section can be redesigned. The current colour
// waves, pyramid functions, borders, stars, palette, and vignette are specific
// to this Egyptian visual theme and can be removed or replaced.
//
// For another track:
//
// - Set the new BPM in the scene script
// - Set beat_offset to the point where the musical beat begins
// - Create new visuals that use beat_pulse for individual beats
// - Use downbeat_pulse for the first beat of each bar
// - Use beat_number to alternate or sequence visual events
// - Use musical_motion for slower movement synchronized across multiple beats
// - Multiply the final effect by disco_amount so the volume slider continues
//   to control its visual intensity
//
// This shader is synchronized through track timing rather than live frequency
// analysis. Bass-responsive screenshake and sand bursts are handled separately
// by BassScreenShake, which analyzes the live audio on the Music bus.

// Controlled by the music volume slider.
uniform float disco_amount : hint_range(0.0, 1.0) = 0.5;


// Supplied by sound_setup.gd.
uniform float music_time = 0.0;
uniform float bpm : hint_range(30.0, 300.0) = 120.0;
uniform float beat_offset = 0.0;
uniform float beats_per_bar : hint_range(1.0, 16.0) = 4.0;


// GENERAL APPEARANCE


uniform float intensity : hint_range(0.0, 1.5) = 0.68;
uniform float colour_softness : hint_range(0.5, 5.0) = 2.2;

uniform vec4 background_colour : source_color = vec4(
	0.005,
	0.004,
	0.012,
	1.0
);

uniform vec4 gold_colour : source_color = vec4(
	0.85,
	0.61,
	0.20,
	1.0
);

uniform vec4 bright_gold_colour : source_color = vec4(
	1.0,
	0.83,
	0.40,
	1.0
);

uniform vec4 lapis_colour : source_color = vec4(
	0.06,
	0.17,
	0.48,
	1.0
);

uniform vec4 turquoise_colour : source_color = vec4(
	0.08,
	0.55,
	0.52,
	1.0
);

uniform vec4 red_colour : source_color = vec4(
	0.48,
	0.07,
	0.12,
	1.0
);


// MUSICAL MOVEMENT


uniform float colour_cycle_beats : hint_range(1.0, 32.0) = 8.0;
uniform float beat_pulse_strength : hint_range(0.0, 2.0) = 0.35;
uniform float downbeat_strength : hint_range(0.0, 2.0) = 0.50;
uniform float beat_decay : hint_range(1.0, 20.0) = 8.0;


// CENTRAL PYRAMID EMBLEM


uniform vec2 central_pyramid_position = vec2(0.5, 0.50);

uniform float central_pyramid_width
	: hint_range(0.10, 1.0) = 0.52;

uniform float central_pyramid_height
	: hint_range(0.10, 1.0) = 0.42;

uniform float central_pyramid_fill
	: hint_range(0.0, 1.0) = 0.16;

uniform float central_pyramid_outline
	: hint_range(0.0, 1.0) = 0.28;

uniform float central_pyramid_line_width
	: hint_range(0.002, 0.08) = 0.012;

uniform float central_pyramid_pulse
	: hint_range(0.0, 1.0) = 0.10;

uniform float stone_line_amount
	: hint_range(0.0, 1.0) = 0.12;

uniform float stone_line_density
	: hint_range(10.0, 200.0) = 95.0;


// PYRAMID BORDERS


uniform float pyramid_amount : hint_range(0.0, 1.0) = 0.55;
uniform float pyramid_columns : hint_range(2.0, 20.0) = 9.0;

uniform float pyramid_line_width
	: hint_range(0.005, 0.10) = 0.025;

uniform float pyramid_scroll_speed
	: hint_range(-1.0, 1.0) = 0.04;


// STARS


uniform float sparkle_amount : hint_range(0.0, 1.0) = 0.55;

uniform float sparkle_brightness
	: hint_range(0.0, 3.0) = 1.25;

uniform float sparkle_size
	: hint_range(0.02, 0.20) = 0.105;

uniform float background_twinkle_strength
	: hint_range(0.0, 1.0) = 0.30;


const float TAU_VALUE = 6.28318530718;


float hash(vec2 position) {
	return fract(
		sin(
			dot(
				position,
				vec2(127.1, 311.7)
			)
		)
		* 43758.5453
	);
}


float pyramid_outline(
	vec2 local_uv,
	float line_width
) {
	float centred_x = abs(
		local_uv.x * 2.0 - 1.0
	);

	float slope_height = mix(
		0.16,
		0.86,
		1.0 - centred_x
	);

	float sloped_edges = (
		1.0
		- smoothstep(
			line_width,
			line_width * 2.0,
			abs(
				local_uv.y
				- slope_height
			)
		)
	);

	float base_edge = (
		1.0
		- smoothstep(
			line_width,
			line_width * 2.0,
			abs(
				local_uv.y
				- 0.16
			)
		)
	);

	return max(
		sloped_edges,
		base_edge
	);
}


float triangle_shape(
	vec2 position,
	float width,
	float height
) {
	float safe_width = max(
		width,
		0.001
	);

	float safe_height = max(
		height,
		0.001
	);

	float vertical_position = (
		position.y
		+ safe_height * 0.5
	);

	float allowed_width = (
		vertical_position
		/ safe_height
		* safe_width
		* 0.5
	);

	float inside_vertical = (
		step(0.0, vertical_position)
		* step(
			vertical_position,
			safe_height
		)
	);

	float inside_horizontal = step(
		abs(position.x),
		allowed_width
	);

	return (
		inside_vertical
		* inside_horizontal
	);
}


float triangle_outline(
	vec2 position,
	float width,
	float height,
	float line_width
) {
	float outer_triangle = triangle_shape(
		position,
		width,
		height
	);

	float inner_width = max(
		width - line_width * 8.0,
		0.001
	);

	float inner_height = max(
		height - line_width * 6.0,
		0.001
	);

	float inner_triangle = triangle_shape(
		position,
		inner_width,
		inner_height
	);

	return max(
		outer_triangle - inner_triangle,
		0.0
	);
}


void fragment() {
	vec2 uv = UV;
	vec2 centred_uv = uv - vec2(0.5);

	float amount = clamp(
		disco_amount,
		0.0,
		1.0
	);

	float safe_bpm = max(
		bpm,
		1.0
	);

	float safe_beats_per_bar = max(
		beats_per_bar,
		1.0
	);

	float safe_cycle_beats = max(
		colour_cycle_beats,
		1.0
	);


	// MUSIC TIMING


	float beat_active = step(
		beat_offset,
		music_time
	);

	float adjusted_music_time = max(
		music_time - beat_offset,
		0.0
	);

	float beat_position = (
		adjusted_music_time
		* safe_bpm
		/ 60.0
	);

	float beat_phase = fract(
		beat_position
	);

	float beat_number = floor(
		beat_position
	);

	float beat_in_bar = mod(
		beat_number,
		safe_beats_per_bar
	);

	float beat_pulse = (
		exp(
			-beat_phase
			* beat_decay
		)
		* beat_active
	);

	float is_downbeat = (
		1.0
		- step(
			0.5,
			beat_in_bar
		)
	);

	float downbeat_pulse = (
		beat_pulse
		* is_downbeat
	);

	float musical_motion = (
		beat_position
		* TAU_VALUE
		/ safe_cycle_beats
	);


	// BASE BACKGROUND


	vec3 colour = background_colour.rgb;


	// SOFT COLOUR WAVES


	float gold_wave = sin(
		uv.x * 3.0
		+ uv.y * 1.5
		+ musical_motion
	);

	float lapis_wave = sin(
		uv.x * -2.0
		+ uv.y * 3.5
		+ musical_motion * 0.65
		+ 2.1
	);

	float turquoise_wave = sin(
		uv.x * 2.5
		- uv.y * 3.0
		+ musical_motion * 0.42
		+ 4.2
	);

	float red_wave = sin(
		uv.x * 1.5
		+ uv.y * 2.0
		- musical_motion * 0.28
		+ 1.3
	);

	gold_wave = pow(
		gold_wave * 0.5 + 0.5,
		colour_softness
	);

	lapis_wave = pow(
		lapis_wave * 0.5 + 0.5,
		colour_softness
	);

	turquoise_wave = pow(
		turquoise_wave * 0.5 + 0.5,
		colour_softness
	);

	red_wave = pow(
		red_wave * 0.5 + 0.5,
		colour_softness
	);

	colour += (
		gold_colour.rgb
		* gold_wave
		* 0.15
	);

	colour += (
		lapis_colour.rgb
		* lapis_wave
		* 0.28
	);

	colour += (
		turquoise_colour.rgb
		* turquoise_wave
		* 0.12
	);

	colour += (
		red_colour.rgb
		* red_wave
		* 0.08
	);


	// CENTRAL DARK PYRAMID EMBLEM


	vec2 pyramid_uv = (
		uv
		- central_pyramid_position
	);

	float pyramid_fill_shape = triangle_shape(
		pyramid_uv,
		central_pyramid_width,
		central_pyramid_height
	);

	float outer_pyramid_edge = triangle_outline(
		pyramid_uv,
		central_pyramid_width,
		central_pyramid_height,
		central_pyramid_line_width
	);

	float middle_pyramid_edge = triangle_outline(
		pyramid_uv,
		central_pyramid_width * 0.68,
		central_pyramid_height * 0.68,
		central_pyramid_line_width
	);

	float inner_pyramid_edge = triangle_outline(
		pyramid_uv,
		central_pyramid_width * 0.38,
		central_pyramid_height * 0.38,
		central_pyramid_line_width
	);

	float pyramid_local_y = (
		pyramid_uv.y
		+ central_pyramid_height * 0.5
	);

	float stone_lines = sin(
		pyramid_local_y
		* stone_line_density
		+ musical_motion * 0.35
	);

	stone_lines = smoothstep(
		0.91,
		1.0,
		stone_lines
	);

	stone_lines *= pyramid_fill_shape;

	float pyramid_downbeat = (
		1.0
		+ downbeat_pulse
		* central_pyramid_pulse
	);

	// Dark lapis silhouette.
	colour += (
		lapis_colour.rgb
		* pyramid_fill_shape
		* central_pyramid_fill
	);

	// Restrained gold outer geometry.
	colour += (
		gold_colour.rgb
		* outer_pyramid_edge
		* central_pyramid_outline
		* pyramid_downbeat
	);

	// Nested golden pyramid.
	colour += (
		gold_colour.rgb
		* middle_pyramid_edge
		* central_pyramid_outline
		* 0.75
		* pyramid_downbeat
	);

	// Small turquoise centre.
	colour += (
		turquoise_colour.rgb
		* inner_pyramid_edge
		* central_pyramid_outline
		* 0.60
		* pyramid_downbeat
	);

	// Subtle moving stone courses.
	colour += (
		gold_colour.rgb
		* stone_lines
		* stone_line_amount
	);


	// REPEATING PYRAMID BORDERS


	float pyramid_scroll = (
		beat_position
		* pyramid_scroll_speed
	);

	vec2 top_pyramid_uv = vec2(
		fract(
			uv.x
			* pyramid_columns
			+ pyramid_scroll
		),
		clamp(
			uv.y / 0.22,
			0.0,
			1.0
		)
	);

	vec2 bottom_pyramid_uv = vec2(
		fract(
			uv.x
			* pyramid_columns
			- pyramid_scroll
		),
		clamp(
			(1.0 - uv.y) / 0.22,
			0.0,
			1.0
		)
	);

	float top_border_mask = (
		1.0
		- smoothstep(
			0.14,
			0.24,
			uv.y
		)
	);

	float bottom_border_mask = smoothstep(
		0.76,
		0.86,
		uv.y
	);

	float top_pyramids = (
		pyramid_outline(
			top_pyramid_uv,
			pyramid_line_width
		)
		* top_border_mask
	);

	float bottom_pyramids = (
		pyramid_outline(
			bottom_pyramid_uv,
			pyramid_line_width
		)
		* bottom_border_mask
	);

	float pyramid_pattern = max(
		top_pyramids,
		bottom_pyramids
	);

	float border_pyramid_pulse = (
		1.0
		+ beat_pulse * 0.30
		+ downbeat_pulse * 0.40
	);

	colour += (
		gold_colour.rgb
		* pyramid_pattern
		* pyramid_amount
		* border_pyramid_pulse
	);


	// BEAT-REACTIVE STARS


	vec2 sparkle_grid_size = vec2(
		28.0,
		17.0
	);

	vec2 sparkle_cell = floor(
		uv * sparkle_grid_size
	);

	vec2 sparkle_position = (
		fract(
			uv
			* sparkle_grid_size
		)
		- vec2(0.5)
	);

	float sparkle_random = hash(
		sparkle_cell
	);

	float sparkle_group_random = hash(
		sparkle_cell
		+ vec2(19.4, 3.7)
	);

	float sparkle_colour_random = hash(
		sparkle_cell
		+ vec2(7.2, 29.1)
	);

	float sparkle_group = floor(
		sparkle_group_random
		* 4.0
	);

	float active_sparkle_group = mod(
		beat_number,
		4.0
	);

	float group_matches_beat = (
		1.0
		- step(
			0.1,
			abs(
				sparkle_group
				- active_sparkle_group
			)
		)
	);

	float sparkle_enabled = step(
		1.0
		- sparkle_amount
		* 0.22,
		sparkle_random
	);

	float background_twinkle = sin(
		beat_position * 1.7
		+ sparkle_random
		* TAU_VALUE
	);

	background_twinkle = pow(
		max(
			background_twinkle,
			0.0
		),
		7.0
	);

	float beat_star_flash = (
		beat_pulse
		* group_matches_beat
	);

	beat_star_flash *= (
		1.0
		+ downbeat_pulse
		* downbeat_strength
	);

	float star_flash = max(
		background_twinkle
		* background_twinkle_strength,
		beat_star_flash
	);


	// STAR SHAPE


	float star_core = (
		1.0
		- smoothstep(
			0.0,
			sparkle_size,
			length(
				sparkle_position
			)
		)
	);

	float horizontal_ray = (
		1.0
		- smoothstep(
			0.0,
			sparkle_size * 1.9,
			abs(
				sparkle_position.x
			)
		)
	);

	horizontal_ray *= (
		1.0
		- smoothstep(
			0.0,
			sparkle_size * 0.16,
			abs(
				sparkle_position.y
			)
		)
	);

	float vertical_ray = (
		1.0
		- smoothstep(
			0.0,
			sparkle_size * 1.9,
			abs(
				sparkle_position.y
			)
		)
	);

	vertical_ray *= (
		1.0
		- smoothstep(
			0.0,
			sparkle_size * 0.16,
			abs(
				sparkle_position.x
			)
		)
	);

	float star_shape = max(
		star_core,
		max(
			horizontal_ray,
			vertical_ray
		)
	);

	float sparkle = (
		sparkle_enabled
		* star_flash
		* star_shape
		* sparkle_brightness
	);

	vec3 star_colour = mix(
		bright_gold_colour.rgb,
		turquoise_colour.rgb,
		step(
			0.76,
			sparkle_colour_random
		)
	);

	colour += (
		star_colour
		* sparkle
	);


	// SUBTLE WHOLE-SCREEN PULSE


	float overall_pulse = (
		beat_pulse
		* beat_pulse_strength
		* 0.06
	);

	overall_pulse += (
		downbeat_pulse
		* downbeat_strength
		* 0.07
	);

	colour *= (
		1.0
		+ overall_pulse
	);


	// VIGNETTE


	float vignette = (
		1.0
		- smoothstep(
			0.20,
			0.80,
			length(
				centred_uv
			)
		)
	);

	colour *= mix(
		0.28,
		1.0,
		vignette
	);


	// MUSIC VOLUME CONTROLS THE TOTAL EFFECT


	colour *= (
		intensity
		* amount
	);

	COLOR = vec4(
		colour,
		1.0
	);
}