shader_type canvas_item;

uniform float scrollSpeed : hint_range(0, 2) = 0.05;
uniform float angleDegrees : hint_range(0, 360, 1) = 45.0;
uniform float repeatX : hint_range(1,20, 1) = 5;
uniform float repeatY : hint_range(1,20, 1) = 5;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	float angleRad = radians(angleDegrees);
	
	vec2 direction = vec2(cos(angleRad), sin(angleRad));
	
	vec2 scroll = fract(TIME * scrollSpeed * direction);
	vec2 offsetUV = UV - scroll;
	
	//tile
	vec2 scaledUV = vec2(fract(offsetUV.x * repeatX), fract(offsetUV.y * repeatY));
	vec2 texelSize = vec2(1.0)/vec2(textureSize(TEXTURE, 0));
	vec2 snappedUV = round(scaledUV / texelSize) * texelSize;
	
	COLOR = texture(TEXTURE,snappedUV) * tint;
}
