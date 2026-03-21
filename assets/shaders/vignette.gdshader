shader_type canvas_item;
// Cinematic vignette + subtle chromatic aberration + scanline hint

void fragment() {
	vec2 uv = UV;
	vec2 center = vec2(0.5);
	float dist = distance(uv, center);

	// Vignette
	float vig = 1.0 - smoothstep(0.3, 0.85, dist);
	vig = mix(0.7, 1.0, vig);

	// Subtle scanlines
	float scan = sin(uv.y * 800.0) * 0.015 + 1.0;

	// Very subtle chromatic aberration at edges
	float aber = dist * 0.002;

	COLOR = vec4(vec3(0.0), (1.0 - vig * scan) * 0.4);
}
