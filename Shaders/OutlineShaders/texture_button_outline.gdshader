shader_type canvas_item;

uniform vec4 outline_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_size = 3.0;
uniform bool show_outline = false;

void fragment() {
	vec4 base_colour = texture(TEXTURE, UV);

	if (!show_outline) {
		COLOR = base_colour;
	} else {
		vec2 pixel_size = TEXTURE_PIXEL_SIZE * outline_size;

		float outline_alpha = 0.0;

		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, 0.0)).a);
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(-pixel_size.x, 0.0)).a);
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(0.0, pixel_size.y)).a);
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(0.0, -pixel_size.y)).a);

		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, pixel_size.y)).a);
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(-pixel_size.x, pixel_size.y)).a);
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, -pixel_size.y)).a);
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(-pixel_size.x, -pixel_size.y)).a);

		float final_outline_alpha = outline_alpha * (1.0 - base_colour.a);

		vec4 final_colour = mix(outline_colour, base_colour, base_colour.a);
		COLOR = vec4(final_colour.rgb, max(base_colour.a, final_outline_alpha));
	}
}