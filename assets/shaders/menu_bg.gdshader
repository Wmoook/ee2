shader_type canvas_item;

// DREAMERS DESIGN — menu background.
// Deep-night gradient with slow aurora ribbons (cyan -> violet -> magenta),
// soft twinkling stars and a gentle vignette. No banding, no gimmicks.

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float star_field(vec2 uv, float density, float t) {
	vec2 grid = floor(uv * density);
	float h = hash(grid);
	// only ~1 cell in 8 holds a star — a sky, not static
	if (h > 0.13) {
		return 0.0;
	}
	float h2 = fract(h * 43.7);
	vec2 center = (grid + vec2(fract(h * 91.3), fract(h * 17.3))) / density;
	float d = length(uv - center);
	float brightness = step(d, 0.30 / density) * (0.35 + 0.65 * h2);
	// slow, soft twinkle
	brightness *= 0.7 + 0.3 * sin(t * (0.6 + h2 * 1.6) + h * 100.0);
	return brightness;
}

float aurora_band(vec2 uv, float y0, float freq, float speed, float thick, float t) {
	float wave = sin(uv.x * freq + t * speed) * 0.055
	           + sin(uv.x * freq * 2.17 - t * speed * 0.63 + 1.7) * 0.03
	           + sin(uv.x * freq * 0.53 + t * speed * 0.31 + 4.2) * 0.045;
	float d = uv.y - (y0 + wave);
	float band = exp(-d * d / (thick * thick));
	// horizontal shimmer so the ribbon breathes
	band *= 0.72 + 0.28 * sin(uv.x * 9.0 + t * 0.8 + y0 * 20.0);
	return band;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.55;

	// === Deep night vertical gradient ===
	vec3 top = vec3(0.024, 0.031, 0.075);
	vec3 mid = vec3(0.055, 0.065, 0.14);
	vec3 bot = vec3(0.10, 0.085, 0.19);
	vec3 color = mix(top, mid, smoothstep(0.0, 0.62, uv.y));
	color = mix(color, bot, smoothstep(0.55, 1.0, uv.y));

	// === Aurora ribbons ===
	vec3 aur = vec3(0.0);
	aur += vec3(0.10, 0.55, 0.65) * aurora_band(uv, 0.30, 5.0, 0.50, 0.085, t) * 0.55;
	aur += vec3(0.38, 0.22, 0.72) * aurora_band(uv, 0.44, 3.6, 0.36, 0.110, t) * 0.50;
	aur += vec3(0.65, 0.18, 0.55) * aurora_band(uv, 0.60, 4.4, 0.28, 0.075, t) * 0.38;
	aur += vec3(0.12, 0.40, 0.80) * aurora_band(uv, 0.16, 2.8, 0.22, 0.070, t) * 0.35;
	// auroras live mostly in the upper 3/4 of the sky
	aur *= 1.0 - smoothstep(0.62, 1.05, uv.y);
	color += aur;

	// === Stars (aspect-corrected square cells; fade near the ribbons) ===
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 suv = vec2(uv.x * aspect, uv.y);
	float stars = 0.0;
	stars += star_field(suv, 26.0, t) * 0.65;
	stars += star_field(suv + vec2(31.0), 52.0, t) * 0.35;
	stars += star_field(suv + vec2(77.0), 96.0, t) * 0.18;
	vec3 star_col = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.65),
	                    step(0.75, hash(floor(suv * 26.0) + vec2(5.0))));
	color += star_col * stars * (1.0 - clamp(length(aur) * 1.6, 0.0, 0.8));

	// === Soft ground haze at the very bottom ===
	color += vec3(0.10, 0.07, 0.18) * smoothstep(0.82, 1.0, uv.y) * 0.5;

	// === Vignette ===
	vec2 c = uv - 0.5;
	float vig = 1.0 - 0.42 * smoothstep(0.35, 0.95, length(c) * 1.35);
	color *= vig;

	COLOR = vec4(color, 1.0);
}
