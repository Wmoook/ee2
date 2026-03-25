shader_type canvas_item;

// Interstellar-style black hole with accretion disk and gravitational lensing

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float star_field(vec2 uv, float density) {
	vec2 grid = floor(uv * density);
	float h = hash(grid);
	vec2 center = (grid + vec2(h, fract(h * 17.3))) / density;
	float d = length(uv - center);
	float brightness = step(d, 0.3 / density) * (0.5 + 0.5 * h);
	// Twinkle
	brightness *= 0.6 + 0.4 * sin(TIME * (1.0 + h * 3.0) + h * 100.0);
	return brightness;
}

void fragment() {
	vec2 uv = (UV - 0.5) * 2.0; // -1 to 1
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	uv.x *= 1.0 / aspect; // correct aspect ratio

	float dist = length(uv);
	float angle = atan(uv.y, uv.x);

	// === BLACK HOLE (dark sphere) ===
	float bh_radius = 0.22;
	float bh_edge = smoothstep(bh_radius, bh_radius - 0.02, dist);

	// === ACCRETION DISK ===
	// Disk is a flattened ellipse — squash Y to make it thin
	vec2 disk_uv = uv;
	disk_uv.y *= 2.8; // Flatten — disk seen at angle
	float disk_dist = length(disk_uv);
	float disk_angle = atan(disk_uv.y, disk_uv.x);

	// Disk ring band (inner/outer radius)
	float disk_inner = 0.28;
	float disk_outer = 0.7;
	float disk_band = smoothstep(disk_inner, disk_inner + 0.05, disk_dist) *
					  smoothstep(disk_outer, disk_outer - 0.1, disk_dist);

	// Only show disk where Y is thin (horizontal band)
	float disk_thin = exp(-uv.y * uv.y * 18.0);

	// Disk rotation + ring detail
	float ring_angle = disk_angle + TIME * 0.3;
	float rings = 0.0;
	rings += sin(disk_dist * 40.0 - TIME * 2.0) * 0.15 + 0.85;
	rings *= sin(disk_dist * 25.0 - TIME * 1.5 + 1.0) * 0.1 + 0.9;
	rings *= sin(disk_dist * 60.0 - TIME * 3.0 + 2.0) * 0.08 + 0.92;

	// Disk color: hot orange/yellow center, dark red edges
	float heat = 1.0 - smoothstep(disk_inner, disk_outer, disk_dist);
	vec3 disk_col_hot = vec3(1.0, 0.85, 0.4);   // Bright yellow-white
	vec3 disk_col_mid = vec3(1.0, 0.45, 0.1);    // Orange
	vec3 disk_col_cool = vec3(0.5, 0.1, 0.05);   // Dark red
	vec3 disk_color = mix(disk_col_cool, disk_col_mid, heat);
	disk_color = mix(disk_color, disk_col_hot, heat * heat);
	disk_color *= rings;

	float disk_mask = disk_band * disk_thin;

	// === GRAVITATIONAL LENSING (disk visible above/below black hole) ===
	// Lensed arc above black hole
	float lens_y_top = -0.08;
	float lens_curve_top = abs(uv.y - lens_y_top) - 0.02;
	float lens_dist_top = length(vec2(uv.x, lens_curve_top));
	float lens_ring_top = smoothstep(bh_radius + 0.01, bh_radius + 0.04, dist) *
						  exp(-lens_curve_top * lens_curve_top * 800.0) *
						  smoothstep(0.0, 0.1, abs(uv.x)) *
						  step(uv.y, -0.02);

	// Lensed arc below
	float lens_y_bot = 0.08;
	float lens_curve_bot = abs(uv.y - lens_y_bot) - 0.02;
	float lens_ring_bot = smoothstep(bh_radius + 0.01, bh_radius + 0.04, dist) *
						  exp(-lens_curve_bot * lens_curve_bot * 800.0) *
						  smoothstep(0.0, 0.1, abs(uv.x)) *
						  step(0.02, uv.y);

	float lens_total = (lens_ring_top + lens_ring_bot) * 0.8;
	vec3 lens_color = mix(disk_col_mid, disk_col_hot, 0.6) * lens_total;

	// === PHOTON RING (bright thin ring at event horizon edge) ===
	float photon = exp(-pow((dist - bh_radius - 0.01) * 80.0, 2.0)) * 0.6;
	vec3 photon_color = vec3(1.0, 0.7, 0.3) * photon;

	// === GLOW around black hole ===
	float glow = exp(-pow((dist - bh_radius) * 5.0, 2.0)) * 0.15;
	vec3 glow_color = vec3(0.8, 0.3, 0.1) * glow;

	// === STARS ===
	vec2 star_uv = UV;
	float stars = 0.0;
	stars += star_field(star_uv, 80.0) * 0.6;
	stars += star_field(star_uv + vec2(50.0), 150.0) * 0.3;
	stars += star_field(star_uv + vec2(100.0), 300.0) * 0.15;
	// Brighter blue-ish stars
	vec3 star_color = vec3(0.7, 0.8, 1.0) * stars;
	// Some warm stars
	float warm = hash(floor(star_uv * 80.0) + vec2(7.0));
	star_color = mix(star_color, vec3(1.0, 0.8, 0.5) * stars, step(0.7, warm));

	// === PURPLE BORDER CIRCLE ===
	float border_dist = abs(dist - 0.92);
	float border = smoothstep(0.015, 0.005, border_dist) * 0.3;
	vec3 border_color = vec3(0.3, 0.15, 0.5) * border;

	// === COMPOSE ===
	vec3 color = vec3(0.01, 0.01, 0.02); // Near-black background
	color += star_color;
	color += border_color;
	color += disk_color * disk_mask;
	color += lens_color;
	color += photon_color;
	color += glow_color;

	// Black hole blocks everything behind it
	color = mix(color, vec3(0.0), bh_edge);

	// Dim stars near the disk (disk is bright, stars shouldn't compete)
	color = mix(color, disk_color * disk_mask + lens_color + photon_color + glow_color,
				smoothstep(0.0, 0.3, disk_mask + lens_total));

	// Pixelate for pixel art feel
	vec2 px = floor(UV * 400.0) / 400.0;
	float px_blend = 0.3; // Subtle pixelation
	vec3 px_color = color; // Could re-evaluate at px coords but too expensive, just quantize colors
	color = floor(color * 20.0) / 20.0 * px_blend + color * (1.0 - px_blend);

	COLOR = vec4(color, 1.0);
}
