shader_type canvas_item;

uniform vec4 base_colour : source_color = vec4(0.001, 0.001, 0.003, 1.0);

uniform vec4 colour_red : source_color = vec4(0.85, 0.16, 0.18, 1.0);
uniform vec4 colour_orange : source_color = vec4(0.90, 0.45, 0.12, 1.0);
uniform vec4 colour_yellow : source_color = vec4(0.95, 0.82, 0.18, 1.0);
uniform vec4 colour_green : source_color = vec4(0.20, 0.72, 0.28, 1.0);
uniform vec4 colour_blue : source_color = vec4(0.16, 0.42, 0.90, 1.0);
uniform vec4 colour_indigo : source_color = vec4(0.34, 0.22, 0.72, 1.0);
uniform vec4 colour_violet : source_color = vec4(0.62, 0.20, 0.78, 1.0);

uniform float base_colour_strength : hint_range(0.0, 1.0) = 0.035;
uniform float swirl_colour_strength : hint_range(0.0, 2.0) = 0.24;

uniform float movement_speed : hint_range(0.0, 3.0) = 0.35;
uniform float colour_cycle_speed : hint_range(0.0, 2.0) = 0.10;

uniform float scale : hint_range(1.0, 30.0) = 7.0;
uniform float softness : hint_range(0.0, 1.0) = 0.72;

uniform float curve_strength : hint_range(0.0, 1.0) = 0.18;
uniform float curve_scale : hint_range(0.5, 20.0) = 4.5;

uniform float swirl_density : hint_range(1.0, 30.0) = 16.0;
uniform float swirl_thickness : hint_range(0.001, 0.2) = 0.022;
uniform float swirl_spin_speed : hint_range(0.0, 3.0) = 0.45;

uniform float black_cutoff : hint_range(0.0, 0.2) = 0.035;


vec3 rainbow_palette(float t) {
	t = fract(t);

	if (t < 1.0 / 6.0) {
		return mix(colour_red.rgb, colour_orange.rgb, t * 6.0);
	} else if (t < 2.0 / 6.0) {
		return mix(colour_orange.rgb, colour_yellow.rgb, (t - 1.0 / 6.0) * 6.0);
	} else if (t < 3.0 / 6.0) {
		return mix(colour_yellow.rgb, colour_green.rgb, (t - 2.0 / 6.0) * 6.0);
	} else if (t < 4.0 / 6.0) {
		return mix(colour_green.rgb, colour_blue.rgb, (t - 3.0 / 6.0) * 6.0);
	} else if (t < 5.0 / 6.0) {
		return mix(colour_blue.rgb, colour_indigo.rgb, (t - 4.0 / 6.0) * 6.0);
	}

	return mix(colour_indigo.rgb, colour_violet.rgb, (t - 5.0 / 6.0) * 6.0);
}


float wave(vec2 uv, float offset, float speed_multiplier) {
	return sin(
		uv.x * scale
		+ uv.y * scale * 0.7
		+ TIME * movement_speed * speed_multiplier
		+ offset
	) * 0.5 + 0.5;
}


vec2 curve_uv(vec2 uv) {
	float curve_x = sin((uv.y * curve_scale) + TIME * movement_speed) * curve_strength;
	float curve_y = cos((uv.x * curve_scale) - TIME * movement_speed * 0.8) * curve_strength;

	return uv + vec2(curve_x, curve_y) * 0.12;
}


float swirl_mask(vec2 uv, float offset) {
	vec2 centred_uv = uv - vec2(0.5);
	float radius = length(centred_uv);
	float angle = atan(centred_uv.y, centred_uv.x);

	float swirl = sin(
		angle * 3.0
		+ radius * swirl_density
		- TIME * swirl_spin_speed
		+ offset
	);

	float line = 1.0 - smoothstep(0.0, swirl_thickness, abs(swirl));
	line *= smoothstep(0.92, 0.10, radius);

	return line;
}


void fragment() {
	vec2 uv = curve_uv(UV);

	float w1 = wave(uv, 0.0, 1.0);
	float w2 = wave(uv + vec2(0.31, 0.17), 2.4, -0.7);
	float w3 = wave(uv + vec2(-0.18, 0.28), 5.1, 0.45);

	w1 = smoothstep(softness, 1.0, w1);
	w2 = smoothstep(softness, 1.0, w2);
	w3 = smoothstep(softness, 1.0, w3);

	vec3 flowing_colour = rainbow_palette(w1 * 0.30 + w2 * 0.20 + TIME * 0.015) * w1;
	flowing_colour += rainbow_palette(w2 * 0.35 + w3 * 0.25 + 0.18 + TIME * 0.012) * w2;
	flowing_colour += rainbow_palette(w3 * 0.40 + w1 * 0.15 + 0.36 + TIME * 0.010) * w3;

	float line_a = swirl_mask(uv + vec2(0.00, 0.00), 0.0);
	float line_b = swirl_mask(uv + vec2(0.06, -0.04), 1.7);
	float line_c = swirl_mask(uv + vec2(-0.05, 0.05), 3.4);
	float line_d = swirl_mask(uv + vec2(0.03, 0.08), 5.1);

	float cycle = TIME * colour_cycle_speed;

	vec3 swirl_colour = rainbow_palette(cycle + 0.00) * line_a;
	swirl_colour += rainbow_palette(cycle + 0.25) * line_b;
	swirl_colour += rainbow_palette(cycle + 0.50) * line_c;
	swirl_colour += rainbow_palette(cycle + 0.75) * line_d;

	vec3 final_colour = base_colour.rgb;
	final_colour += flowing_colour * base_colour_strength;
	final_colour += swirl_colour * swirl_colour_strength;

	final_colour = max(final_colour - vec3(black_cutoff), vec3(0.0));

	COLOR = vec4(final_colour, base_colour.a);
}