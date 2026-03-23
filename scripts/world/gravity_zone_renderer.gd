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

		# Pulsing concentric rings — pixel dots, not smooth arcs
		for i in range(4):
			var phase: float = fmod(time * 0.4 + float(i) * 0.25, 1.0)
			var ring_r: float = radius * (1.0 - phase)
			var ring_alpha: float = phase * (1.0 - phase) * 2.5
			if GameState.is_edit_mode:
				ring_alpha *= 0.8
			else:
				ring_alpha *= 0.25
			var ring_pts: int = int(ring_r * 1.5) + 8
			for ri in range(ring_pts):
				var r_angle: float = TAU * float(ri) / float(ring_pts)
				var r_pos: Vector2 = center + Vector2(cos(r_angle), sin(r_angle)) * ring_r
				draw_rect(Rect2(floor(r_pos.x), floor(r_pos.y), 1, 1), Color(0.6, 0.3, 1.0, ring_alpha))

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
			draw_rect(Rect2(floor(pos.x), floor(pos.y), 1, 1), Color(0.5, 0.4, 1.0, p_alpha))

		# BLACK HOLE CENTER — deadly singularity
		var glow_pulse: float = 0.5 + 0.3 * sin(time * 2.0)
		var edit_mult: float = 1.0 if GameState.is_edit_mode else 0.7

		# Event horizon — pixel circle using centered coordinates
		var cx: int = int(round(center.x))
		var cy: int = int(round(center.y))
		var core_r: int = 6
		for px in range(-core_r, core_r + 1):
			for py in range(-core_r, core_r + 1):
				if px * px + py * py <= core_r * core_r:
					var dist: float = sqrt(float(px * px + py * py))
					var alpha: float = 1.0 if dist < 4.0 else lerpf(1.0, 0.4, (dist - 4.0) / 3.0)
					draw_rect(Rect2(cx + px, cy + py, 1, 1), Color(0.0, 0.0, 0.0, alpha * edit_mult))

		# Event horizon glow ring — individual pixels around the edge
		var eh_r: float = 8.0
		for ei in range(40):
			var e_angle: float = TAU * float(ei) / 40.0
			var e_dist: float = eh_r + sin(e_angle * 3.0 + time * 2.0) * 1.0
			var e_pos: Vector2 = center + Vector2(cos(e_angle), sin(e_angle)) * e_dist
			var e_bright: float = 0.5 + 0.5 * sin(e_angle * 2.0 + time * 3.0)
			draw_rect(Rect2(floor(e_pos.x), floor(e_pos.y), 1, 1), Color(1.0, 0.4 * e_bright, 0.0, 0.8 * glow_pulse * edit_mult))

		# Accretion disk — 1px rects, draw BEHIND the void (only visible outside core)
		for ai in range(30):
			var a_angle: float = TAU * float(ai) / 30.0 + time * 2.0
			var a_r: float = 12.0 + sin(a_angle * 2.0 + time * 3.0) * 2.5
			var a_pos: Vector2 = center + Vector2(cos(a_angle) * a_r, sin(a_angle) * a_r * 0.55)
			# Skip pixels that would be inside the void
			if a_pos.distance_to(center) < 7.0:
				continue
			var a_bright: float = 0.4 + 0.6 * maxf(0, sin(a_angle + time * 3.0))
			var col: Color = Color(1.0, 0.6 * a_bright, 0.1 * a_bright, 0.9 * a_bright * edit_mult)
			draw_rect(Rect2(floor(a_pos.x), floor(a_pos.y), 1, 1), col)

		# Redraw void core ON TOP of accretion disk (pixel circle)
		for px in range(-5, 6):
			for py in range(-5, 6):
				if px * px + py * py <= 25:
					draw_rect(Rect2(cx + px, cy + py, 1, 1), Color(0.0, 0.0, 0.0, 1.0))

		# Sucking-in spiral streams — 1px rects like fire trail
		for si in range(16):
			var s_angle: float = TAU * float(si) / 16.0 + time * 1.2
			var s_phase: float = fmod(time * 0.6 + float(si) * 0.0625, 1.0)
			var s_r: float = 25.0 * (1.0 - s_phase * s_phase)
			var spiral_twist: float = s_phase * 3.0
			var s_pos: Vector2 = center + Vector2(cos(s_angle + spiral_twist), sin(s_angle + spiral_twist)) * s_r
			# Skip inside void
			if s_pos.distance_to(center) < 7.0:
				continue
			var s_alpha: float = s_phase * (1.0 - s_phase) * 3.0 * edit_mult
			var r_col: float = lerpf(0.5, 1.0, s_phase)
			var g_col: float = lerpf(0.7, 0.2, s_phase)
			var b_col: float = lerpf(1.0, 0.0, s_phase)
			draw_rect(Rect2(floor(s_pos.x), floor(s_pos.y), 1, 1), Color(r_col, g_col, b_col, s_alpha))

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
