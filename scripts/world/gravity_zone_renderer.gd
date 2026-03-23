extends Node2D
## Renders gravity zone visual effects — all pixel art style

func _ready() -> void:
	z_index = -1
	WorldManager.gravity_zones.zones_changed.connect(func(): queue_redraw())

func _process(_delta: float) -> void:
	if WorldManager.gravity_zones.zones.size() > 0:
		queue_redraw()

func _draw() -> void:
	var time: float = Time.get_ticks_msec() * 0.001
	for gz in WorldManager.gravity_zones.zones:
		var center: Vector2 = gz.center
		var radius: float = gz.radius
		var cx: int = int(round(center.x))
		var cy: int = int(round(center.y))
		var edit: bool = GameState.is_edit_mode
		var bright: float = 1.0 if edit else 0.7

		# Zone boundary — animated swirling pixel ring (always visible)
		var border_pts: int = int(radius * 2.5) + 20
		for bi in range(border_pts):
			var b_angle: float = TAU * float(bi) / float(border_pts) + time * 0.3
			var b_wobble: float = sin(b_angle * 6.0 + time * 2.0) * 1.5
			var b_pos: Vector2 = center + Vector2(cos(b_angle), sin(b_angle)) * (radius + b_wobble)
			# Swirling brightness pattern
			var b_bright: float = 0.3 + 0.7 * maxf(0, sin(b_angle * 3.0 - time * 1.5))
			var b_alpha: float = b_bright * (0.5 if edit else 0.2)
			draw_rect(Rect2(floor(b_pos.x), floor(b_pos.y), 1, 1), Color(0.5, 0.2, 0.9, b_alpha))

		# Pulsing inward rings (pixel dots)
		for i in range(4):
			var phase: float = fmod(time * 0.4 + float(i) * 0.25, 1.0)
			var ring_r: float = radius * (1.0 - phase)
			var ring_alpha: float = phase * (1.0 - phase) * 2.0 * (0.7 if edit else 0.2)
			var ring_pts: int = int(ring_r * 2.0) + 12
			for ri in range(ring_pts):
				var r_angle: float = TAU * float(ri) / float(ring_pts)
				var r_pos: Vector2 = center + Vector2(cos(r_angle), sin(r_angle)) * ring_r
				draw_rect(Rect2(floor(r_pos.x), floor(r_pos.y), 1, 1), Color(0.6, 0.3, 1.0, ring_alpha))

		# --- BLACK HOLE CENTER ---

		var void_r: int = 8

		# --- DRAW ORDER: back ring → void → front ring (Saturn's rings illusion) ---

		# Helper: draw accretion ring pixels for a given angle range
		# back_half = true means top half (behind hole), false = bottom (in front)
		for pass_idx in range(3):  # 0=back ring, 1=void+glow, 2=front ring
			if pass_idx == 0 or pass_idx == 2:
				# Accretion disk — 6 tightly-packed layers that blend together
				for layer in range(6):
					var layer_t: float = float(layer) / 5.0  # 0=inner, 1=outer
					var layer_r: float = 10.0 + layer_t * 8.0
					var layer_count: int = 70
					var speed: float = 2.5 - layer_t * 1.0  # Inner spins faster
					for ai in range(layer_count):
						var a_angle: float = TAU * float(ai) / float(layer_count) + time * speed + float(layer) * 0.5
						var wobble: float = sin(a_angle * 3.0 + time * 2.5 + float(layer)) * (1.0 + layer_t)
						var a_r: float = layer_r + wobble
						var a_pos: Vector2 = center + Vector2(cos(a_angle) * a_r, sin(a_angle) * a_r * 0.4)
						if pass_idx == 0 and a_pos.y > center.y:
							continue
						if pass_idx == 2 and a_pos.y <= center.y:
							continue
						if pass_idx == 0 and a_pos.distance_to(center) < float(void_r):
							continue
						var a_bright: float = 0.5 + 0.5 * maxf(0, sin(a_angle * 1.5 + time * 3.0 + float(layer) * 0.7))
						var front_boost: float = 1.4 if pass_idx == 2 else 1.0
						# Color gradient: inner = bright white-yellow, outer = orange
						var r_c: float = 1.0
						var g_c: float = lerpf(0.95, 0.4, layer_t) * a_bright
						var b_c: float = lerpf(0.7, 0.1, layer_t) * a_bright * a_bright
						var a_alpha: float = lerpf(1.0, 0.7, layer_t) * a_bright * bright * front_boost
						draw_rect(Rect2(floor(a_pos.x), floor(a_pos.y), 1, 1), Color(r_c, g_c, b_c, minf(a_alpha, 1.0)))
						# Second pixel offset for blending/thickness
						if a_bright > 0.5:
							var off: Vector2 = Vector2(cos(a_angle), sin(a_angle) * 0.4).normalized()
							draw_rect(Rect2(floor(a_pos.x + off.x), floor(a_pos.y + off.y), 1, 1), Color(r_c, g_c, b_c, minf(a_alpha * 0.5, 1.0)))

			elif pass_idx == 1:
				# Void core — solid black pixel circle
				for px in range(-void_r, void_r + 1):
					for py in range(-void_r, void_r + 1):
						if px * px + py * py <= void_r * void_r:
							draw_rect(Rect2(cx + px, cy + py, 1, 1), Color(0.0, 0.0, 0.0, 1.0))

				# Event horizon glow ring
				var eh_count: int = 60
				for ei in range(eh_count):
					var e_angle: float = TAU * float(ei) / float(eh_count)
					var e_r: float = float(void_r) + 1.0 + sin(e_angle * 4.0 + time * 2.5) * 0.5
					var e_pos: Vector2 = center + Vector2(cos(e_angle), sin(e_angle)) * e_r
					var e_pulse: float = 0.6 + 0.4 * sin(e_angle * 2.0 + time * 3.0)
					draw_rect(Rect2(floor(e_pos.x), floor(e_pos.y), 1, 1), Color(1.0, 0.6 * e_pulse, 0.2 * e_pulse, e_pulse * bright))

		# 4. Spiral streams being sucked in — dense, many particles
		for si in range(24):
			var s_angle: float = TAU * float(si) / 24.0 + time * 1.0
			var s_phase: float = fmod(time * 0.5 + float(si) * 0.042, 1.0)
			var s_r: float = 30.0 * (1.0 - s_phase * s_phase)
			var spiral_twist: float = s_phase * 4.0
			var s_pos: Vector2 = center + Vector2(cos(s_angle + spiral_twist), sin(s_angle + spiral_twist)) * s_r
			if s_pos.distance_to(center) < float(void_r) + 1.0:
				continue
			var s_alpha: float = s_phase * (1.0 - s_phase) * 3.5 * bright
			var rc: float = lerpf(0.4, 1.0, s_phase)
			var gc: float = lerpf(0.6, 0.15, s_phase)
			var bc: float = lerpf(1.0, 0.0, s_phase)
			draw_rect(Rect2(floor(s_pos.x), floor(s_pos.y), 1, 1), Color(rc, gc, bc, s_alpha))

		# 5. Inward flow lines (pixel-based)
		for i in range(8):
			var line_angle: float = TAU * float(i) / 8.0 + time * 0.1
			var flow_phase: float = fmod(time * 0.4 + float(i) * 0.125, 1.0)
			var start_r: float = radius * (0.3 + 0.6 * flow_phase)
			var line_len: int = int(radius * 0.12) + 2
			var line_alpha: float = (1.0 - flow_phase) * 0.5 * bright
			var dir: Vector2 = Vector2(cos(line_angle), sin(line_angle))
			for li in range(line_len):
				var lr: float = start_r - float(li)
				var l_pos: Vector2 = center + dir * lr
				draw_rect(Rect2(floor(l_pos.x), floor(l_pos.y), 1, 1), Color(0.7, 0.4, 1.0, line_alpha * (1.0 - float(li) / float(line_len))))
