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

		# BLACK HOLE CENTER — deadly, menacing
		var glow_pulse: float = 0.5 + 0.3 * sin(time * 2.0)
		var edit_mult: float = 1.0 if GameState.is_edit_mode else 0.6

		# Dark void core
		draw_circle(center, 8.0, Color(0.0, 0.0, 0.0, 0.95 * edit_mult))
		draw_circle(center, 6.0, Color(0.02, 0.0, 0.05, 1.0 * edit_mult))

		# Danger ring — red/orange pulsing
		var danger_r: float = 10.0 + sin(time * 3.0) * 1.5
		draw_arc(center, danger_r, 0, TAU, 32, Color(1.0, 0.2, 0.0, 0.7 * glow_pulse * edit_mult), 1.5)
		draw_arc(center, danger_r + 2.0, 0, TAU, 32, Color(1.0, 0.5, 0.0, 0.4 * glow_pulse * edit_mult), 1.0)

		# Sucking-in spiral particles near center
		for si in range(8):
			var s_angle: float = TAU * float(si) / 8.0 + time * 1.5
			var s_phase: float = fmod(time * 0.8 + float(si) * 0.125, 1.0)
			var s_r: float = 20.0 * (1.0 - s_phase)  # Spirals inward
			var s_pos: Vector2 = center + Vector2(cos(s_angle + s_phase * 2.0), sin(s_angle + s_phase * 2.0)) * s_r
			var s_alpha: float = s_phase * (1.0 - s_phase) * 3.0 * edit_mult
			var s_col: Color = Color(1.0, lerpf(0.1, 0.6, s_phase), 0.0, s_alpha * 0.8)
			draw_circle(s_pos, 1.5 * (1.0 - s_phase), s_col)

		# Accretion ring — fast-spinning bright ring just outside the kill zone
		for ai in range(12):
			var a_angle: float = TAU * float(ai) / 12.0 + time * 2.5
			var a_r: float = 12.0 + sin(a_angle * 3.0 + time) * 1.5
			var a_pos: Vector2 = center + Vector2(cos(a_angle), sin(a_angle)) * a_r
			var a_bright: float = 0.5 + 0.5 * sin(a_angle * 2.0 + time * 4.0)
			draw_circle(a_pos, 1.0, Color(1.0, 0.8 * a_bright, 0.3 * a_bright, 0.6 * a_bright * edit_mult))

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
