shader_type canvas_item;

uniform sampler2D mask_texture : source_color, repeat_disable, filter_linear;

uniform vec4 black_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float fade_alpha = 0.0;
uniform bool reveal_enabled = false;
uniform float reveal_scale = 0.0;
uniform vec2 reveal_center = vec2(0.5, 0.5);
uniform float screen_aspect = 1.777777;
uniform float mask_aspect = 1.0;
uniform float alpha_threshold = 0.5;
uniform float edge_softness = 0.03;

void fragment() {
	float reveal_alpha = 0.0;

	if (reveal_enabled) {
		float safe_scale = max(reveal_scale, 0.0001);

		vec2 local_position = UV - reveal_center;
		local_position.x *= screen_aspect;
		local_position /= safe_scale;
		local_position.x /= max(mask_aspect, 0.0001);

		vec2 mask_uv = local_position + vec2(0.5, 0.5);

		float in_bounds = step(0.0, mask_uv.x)
			* step(mask_uv.x, 1.0)
			* step(0.0, mask_uv.y)
			* step(mask_uv.y, 1.0);

		float mask_alpha = texture(mask_texture, mask_uv).a * in_bounds;

		reveal_alpha = smoothstep(
			alpha_threshold - edge_softness,
			alpha_threshold + edge_softness,
			mask_alpha
		);
	}

	float final_alpha = fade_alpha * (1.0 - reveal_alpha);

	COLOR = vec4(black_color.rgb, black_color.a * final_alpha);
}