shader_type canvas_item;

uniform bool outline_enabled = false;
uniform vec4 outline_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_size = 2.0;

void fragment() {
	vec4 base_colour = texture(TEXTURE, UV) * COLOR;

	if (!outline_enabled) {
		COLOR = base_colour;
	} else {
		float alpha = base_colour.a;
		float outline_alpha = 0.0;

		vec2 pixel_size = TEXTURE_PIXEL_SIZE * outline_size;

		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, 0.0)).a);
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(-pixel_size.x, 0.0)).a);
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(0.0, pixel_size.y)).a);
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(0.0, -pixel_size.y)).a);

		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, pixel_size.y)).a);
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(-pixel_size.x, pixel_size.y)).a);
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(pixel_size.x, -pixel_size.y)).a);
		outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(-pixel_size.x, -pixel_size.y)).a);

		if (alpha <= 0.01 && outline_alpha > 0.01) {
			COLOR = outline_colour;
			COLOR.a *= outline_alpha;
		} else {
			COLOR = base_colour;
		}
	}
}
