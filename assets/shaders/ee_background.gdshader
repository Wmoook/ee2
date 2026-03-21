shader_type canvas_item;

// EE-style dark background with subtle grid pattern
uniform vec4 bg_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 grid_color : source_color = vec4(0.08, 0.08, 0.12, 1.0);
uniform float grid_size = 16.0;
uniform float grid_width = 0.5;

void fragment() {
	vec2 world_pos = (UV * vec2(textureSize(TEXTURE, 0)));
	vec2 grid_pos = mod(world_pos, grid_size);

	float grid_line = 0.0;
	if (grid_pos.x < grid_width || grid_pos.y < grid_width) {
		grid_line = 1.0;
	}

	COLOR = mix(bg_color, grid_color, grid_line);
}
