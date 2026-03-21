shader_type canvas_item;
// EE-style world background with animated subtle pattern

void fragment() {
	vec2 uv = UV;
	vec2 world_uv = uv * vec2(textureSize(TEXTURE, 0));

	// Dark base with subtle grid
	float tile = 16.0;
	vec2 grid = abs(fract(world_uv / tile) - 0.5) * 2.0;
	float gridline = 1.0 - smoothstep(0.92, 0.98, max(grid.x, grid.y));

	// Subtle animated gradient
	float t = TIME * 0.15;
	float wave = sin(uv.x * 3.0 + t) * 0.5 + 0.5;
	float wave2 = cos(uv.y * 2.5 - t * 0.7) * 0.5 + 0.5;

	vec3 bg_dark = vec3(0.02, 0.025, 0.06);
	vec3 bg_accent = vec3(0.04, 0.05, 0.12);
	vec3 grid_col = vec3(0.06, 0.07, 0.14);

	vec3 base = mix(bg_dark, bg_accent, wave * wave2 * 0.5);
	vec3 final_col = mix(base, grid_col, gridline * 0.3);

	COLOR = vec4(final_col, 1.0);
}
