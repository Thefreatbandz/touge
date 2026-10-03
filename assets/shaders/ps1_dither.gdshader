shader_type canvas_item;
// PS1-style post: RGB565 (5-bit) quantization + ordered dither.
// Kills color banding on the sunset sky.

void fragment() {
	vec3 c = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	// 4x4 Bayer ordered dither, scaled to +/-4/255 like the PS1
	vec2 px = floor(FRAGCOORD.xy);
	float bayer = fract(px.x * 0.25) * 0.25 + fract(px.y * 0.25);
	float dither = (bayer - 0.5) * (8.0 / 255.0);
	c = clamp(c + dither, vec3(0.0), vec3(1.0));
	// 5 bits per channel via round()
	c = round(c * 31.0) / 31.0;
	COLOR = vec4(c, 1.0);
}
