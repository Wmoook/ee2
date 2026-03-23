extends Node2D
## Renders gravity zone visual effects: pulsing rings, orbiting particles, inward flow lines

func _ready() -> void:
	z_index = -1  # Behind player, above background
	WorldManager.gravity_zones.zones_changed.connect(func(): queue_redraw())

func _process(_delta: float) -> void:
	if WorldManager.gravity_zones.zones.size() > 0:
		queue_redraw()

func _draw() -> void:
	var time: float = Time.get_ticks_msec() * 0.001
	for gz in WorldManager.gravity_zones.zones:
		var center: Vector2 = gz.center
		var radius: float = gz.radius

		if GameState.is_edit_mode:
			# Edit mode: bright outline + center dot
			draw_arc(center, radius, 0, TAU, 64, Color(0.7, 0.2, 1.0, 0.5), 2.0)
			draw_circle(center, 4.0, Color(0.7, 0.2, 1.0, 0.8))

		# Pulsing concentric rings that flow INWARD (show pull direction)
		for i in range(4):
			var phase: float = fmod(time * 0.4 + float(i) * 0.25, 1.0)
			var ring_r: float = radius * (1.0 - phase)  # Shrinks inward
			var ring_alpha: float = phase * (1.0 - phase) * 2.5  # Fade in then out
			if GameState.is_edit_mode:
				ring_alpha *= 0.8
			else:
				ring_alpha *= 0.25  # Subtle in play mode
			draw_arc(center, ring_r, 0, TAU, 48, Color(0.6, 0.3, 1.0, ring_alpha), 1.0)

		# Orbiting particles around the edge
		var num_particles: int = int(radius / 15.0) + 4
		for i in range(num_particles):
			var base_angle: float = TAU * float(i) / float(num_particles)
			var orbit_speed: float = 0.3 + float(i % 3) * 0.15
			var angle: float = base_angle + time * orbit_speed
			# Particles spiral inward slightly
			var spiral: float = fmod(time * 0.2 + float(i) * 0.3, 1.0)
			var r: float = radius * (0.3 + 0.7 * (1.0 - spiral * 0.3))
			var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * r
			var p_alpha: float = 0.5 if GameState.is_edit_mode else 0.15
			var p_size: float = 1.5 + sin(time * 2.0 + float(i)) * 0.5
			draw_circle(pos, p_size, Color(0.5, 0.4, 1.0, p_alpha))

		# Center glow — subtle pulsing dot
		var glow_pulse: float = 0.5 + 0.3 * sin(time * 1.5)
		var glow_alpha: float = glow_pulse * (0.6 if GameState.is_edit_mode else 0.2)
		draw_circle(center, 5.0 + sin(time) * 1.5, Color(0.8, 0.5, 1.0, glow_alpha * 0.4))
		draw_circle(center, 3.0, Color(0.9, 0.7, 1.0, glow_alpha))

		# Inward flow lines (6 lines pointing toward center)
		var num_lines: int = 6
		for i in range(num_lines):
			var line_angle: float = TAU * float(i) / float(num_lines) + time * 0.1
			var flow_phase: float = fmod(time * 0.5 + float(i) * 0.17, 1.0)
			var start_r: float = radius * (0.4 + 0.5 * flow_phase)
			var end_r: float = start_r - radius * 0.15
			var line_alpha: float = (1.0 - flow_phase) * (0.4 if GameState.is_edit_mode else 0.12)
			var start_pt: Vector2 = center + Vector2(cos(line_angle), sin(line_angle)) * start_r
			var end_pt: Vector2 = center + Vector2(cos(line_angle), sin(line_angle)) * end_r
			draw_line(start_pt, end_pt, Color(0.7, 0.4, 1.0, line_alpha), 1.0)
