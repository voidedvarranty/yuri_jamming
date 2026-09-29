shader_type canvas_item;

uniform sampler3D noise_texture : repeat_enable;

// Replaced the color ramp with 2 distinct color inputs
uniform vec4 color_one : source_color = vec4(1.0, 1.0, 1.0, 1.0); // "White" parts
uniform vec4 color_two : source_color = vec4(0.0, 0.0, 0.0, 1.0); // "Black" parts

uniform float noise_scale : hint_range(0.1, 10.0) = 2.0;
uniform float seethe_speed : hint_range(0, 5.0) = 0.5;
uniform float target_height = 180.0;

void fragment() {
    // 1. Calculate dynamic resolution to keep pixels perfectly square
    float actual_aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
    vec2 dynamic_resolution = vec2(target_height * actual_aspect, target_height);
    
    // 2. Snap to the pixel grid
    vec2 pixel_grid = floor(SCREEN_UV * dynamic_resolution);
    vec2 pixelated_uv = pixel_grid / dynamic_resolution;
    
    // 3. Sample the seething 3D noise
    vec3 uv3d;
    uv3d.xy = pixelated_uv * vec2(actual_aspect, 1.0) * noise_scale;
    uv3d.z = TIME * seethe_speed;
    float noise_value = texture(noise_texture, uv3d).r;
    
    // 4. Create a 2x2 checkerboard pattern based on the pixel grid coordinates.
    // tracking if the sum of X and Y pixel coordinates is even or odd.
    float checkerboard = mod(pixel_grid.x + pixel_grid.y, 2.0);
    
    // 5. Dither logic:
    // Pure noise_value -> 0.0 is full color_two, 1.0 is full color_one.
    // By factoring in the checkerboard step, mid-tones (0.25 to 0.75) 
    // break apart into alternating pixel clusters.
    float dither_threshold = mix(0.25, 0.75, checkerboard);
    
    // If noise is brighter than the threshold, use color_one, else color_two
    vec4 final_color = (noise_value > dither_threshold) ? color_one : color_two;
    
    COLOR = final_color;
}