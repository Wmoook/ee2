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
		var px_size: int = 1  # Always 1px — scale by adding MORE particles instead

		# Zone boundary — animated swirling pixel ring (always visible)
		var border_pts: int = int(radius * 2.5) + 20
		for bi in range(border_pts):
			var b_angle: float = TAU * float(bi) / float(border_pts) + time * 0.3
			var b_wobble: float = sin(b_angle * 6.0 + time * 2.0) * 1.5
			var b_pos: Vector2 = center + Vector2(cos(b_angle), sin(b_angle)) * (radius + b_wobble)
			# Swirling brightness pattern
			var b_bright: float = 0.3 + 0.7 * maxf(0, sin(b_angle * 3.0 - time * 1.5))
			var b_alpha: float = b_bright * (0.5 if edit else 0.2)
			draw_rect(Rect2(floor(b_pos.x), floor(b_pos.y), px_size, px_size), Color(0.5, 0.2, 0.9, b_alpha))

		# Pulsing inward rings (pixel dots)
		for i in range(4):
			var phase: float = fmod(time * 0.4 + float(i) * 0.25, 1.0)
			var ring_r: float = radius * (1.0 - phase)
			var ring_alpha: float = phase * (1.0 - phase) * 2.0 * (0.7 if edit else 0.2)
			var ring_pts: int = int(ring_r * 2.0) + 12
			for ri in range(ring_pts):
				var r_angle: float = TAU * float(ri) / float(ring_pts)
				var r_pos: Vector2 = center + Vector2(cos(r_angle), sin(r_angle)) * ring_r
				draw_rect(Rect2(floor(r_pos.x), floor(r_pos.y), px_size, px_size), Color(0.6, 0.3, 1.0, ring_alpha))

		# --- BLACK HOLE CENTER ---

		var void_r: int = int(round(gz.get("center_radius", 8.0)))

		# --- DRAW ORDER: back ring → void → front ring (Saturn's rings illusion) ---

		# Helper: draw accretion ring pixels for a given angle range
		# back_half = true means top half (behind hole), false = bottom (in front)
		# Accretion disk as SOLID FILLED ELLIPTICAL RING — zero gaps
		var ring_thick: int = maxi(6, void_r / 2)
		var outer_r: int = void_r + ring_thick + 2
		var squash: float = 0.4  # Vertical squash for 3D perspective
		for pass_idx in range(3):  # 0=back ring, 1=void+glow, 2=front ring
			if pass_idx == 0 or pass_idx == 2:
				var front_boost: float = 1.3 if pass_idx == 2 else 1.0
				for py in range(-outer_r, outer_r + 1):
					# Back = above center, Front = below center
					if pass_idx == 0 and py > 0:
						continue
					if pass_idx == 2 and py <= 0:
						continue
					# Elliptical: actual y in ellipse space
					var ey: float = float(py) / squash
					for layer in range(3):
						var lr: int = void_r + 1 + layer * maxi(2, ring_thick / 3)
						var lr_outer: int = lr + maxi(2, ring_thick / 3)
						# Row width at this y for inner and outer circle
						if ey * ey > float(lr_outer * lr_outer):
							continue
						var w_outer: int = int(sqrt(maxf(0, float(lr_outer * lr_outer) - ey * ey)))
						var w_inner: int = 0
						if ey * ey < float(lr * lr):
							w_inner = int(sqrt(maxf(0, float(lr * lr) - ey * ey)))
						if w_outer <= w_inner:
							continue
						# Animated color: varies with angle approximation
						var angle_approx: float = atan2(float(py), float(w_outer)) + time * (2.0 - float(layer) * 0.3)
						var a_bright: float = 0.5 + 0.5 * sin(angle_approx * 2.0 + time * 3.0)
						var layer_t: float = float(layer) / 2.0
						var r_c: float = 1.0
						var g_c: float = lerpf(0.95, 0.4, layer_t) * a_bright
						var b_c: float = lerpf(0.7, 0.1, layer_t) * a_bright * a_bright
						var a_alpha: float = lerpf(0.9, 0.6, layer_t) * a_bright * bright * front_boost
						var col: Color = Color(r_c, g_c, b_c, minf(a_alpha, 1.0))
						# Draw left and right arcs
						if w_inner > 0:
							draw_rect(Rect2(cx - w_outer, cy + py, w_outer - w_inner, 1), col)
							draw_rect(Rect2(cx + w_inner + 1, cy + py, w_outer - w_inner, 1), col)
						else:
							draw_rect(Rect2(cx - w_outer, cy + py, w_outer * 2 + 1, 1), col)

			elif pass_idx == 1:
				# Void core — solid black circle (single draw for performance)
				# Draw rows instead of individual pixels
				for py in range(-void_r, void_r + 1):
					var row_w: int = int(sqrt(float(void_r * void_r - py * py)))
					if row_w > 0:
						draw_rect(Rect2(cx - row_w, cy + py, row_w * 2 + 1, 1), Color(0.0, 0.0, 0.0, 1.0))

				# Event horizon glow ring
				var eh_count: int = mini(200, maxi(30, void_r * 6))  # Dense event horizon
				for ei in range(eh_count):
					var e_angle: float = TAU * float(ei) / float(eh_count)
					var e_r: float = float(void_r) + 1.0 + sin(e_angle * 4.0 + time * 2.5) * 0.5
					var e_pos: Vector2 = center + Vector2(cos(e_angle), sin(e_angle)) * e_r
					var e_pulse: float = 0.6 + 0.4 * sin(e_angle * 2.0 + time * 3.0)
					var efx: float = floor(e_pos.x)
					var efy: float = floor(e_pos.y)
					var ec: Color = Color(1.0, 0.6 * e_pulse, 0.2 * e_pulse, e_pulse * bright)
					var ed: Color = Color(1.0, 0.6 * e_pulse, 0.2 * e_pulse, e_pulse * bright * 0.4)
					draw_rect(Rect2(efx, efy, 1, 1), ec)
					draw_rect(Rect2(efx - 1, efy, 1, 1), ed)
					draw_rect(Rect2(efx + 1, efy, 1, 1), ed)
					draw_rect(Rect2(efx, efy - 1, 1, 1), ed)
					draw_rect(Rect2(efx, efy + 1, 1, 1), ed)

		# 4. Spiral streams — cool logarithmic spiral flowing INWARD
		var spiral_count: int = mini(60, 24 + void_r)
		for si in range(spiral_count):
			var s_angle: float = TAU * float(si) / float(spiral_count) + time * 1.0
			var s_phase: float = fmod(time * 0.5 + float(si) / float(spiral_count), 1.0)
			# Logarithmic spiral: slow at edge, ACCELERATES hard into center
			var accel: float = 1.0 - s_phase * s_phase * s_phase  # Cubic: slow start, fast finish
			var s_r: float = maxf(radius * 0.8, float(void_r) + 5.0) * accel * accel
			var spiral_twist: float = s_phase * 6.0  # Lots of twist
			var s_pos: Vector2 = center + Vector2(cos(s_angle + spiral_twist), sin(s_angle + spiral_twist)) * s_r
			if s_pos.distance_to(center) < float(void_r) + 1.0:
				continue
			# Fade out as approaching center (consumed by the void)
			var fade_near_center: float = clampf(s_r / (float(void_r) + 5.0), 0.0, 1.0)
			var s_alpha: float = s_phase * fade_near_center * 2.5 * bright
			# Color: blue-white at border, orange-red near center
			var rc: float = lerpf(0.4, 1.0, s_phase)
			var gc: float = lerpf(0.6, 0.2, s_phase)
			var bc: float = lerpf(1.0, 0.0, s_phase)
			draw_rect(Rect2(floor(s_pos.x), floor(s_pos.y), px_size, px_size), Color(rc, gc, bc, s_alpha))

		# 5. Inward flow lines — start at border, ACCELERATE toward center
		for i in range(8):
			var line_angle: float = TAU * float(i) / 8.0 + time * 0.15
			var flow_phase: float = fmod(time * 0.3 + float(i) * 0.125, 1.0)
			# Cubic acceleration: slow at border, fast near center
			var accel_phase: float = flow_phase * flow_phase * flow_phase
			var head_r: float = lerpf(radius * 0.9, float(void_r) + 3.0, accel_phase)
			var line_len: int = int(radius * 0.1) + 3
			var line_alpha: float = (1.0 - flow_phase * 0.5) * 0.4 * bright
			var dir: Vector2 = Vector2(cos(line_angle), sin(line_angle))
			for li in range(line_len):
				var lr: float = head_r + float(li)  # Trail extends OUTWARD from head
				var l_pos: Vector2 = center + dir * lr
				draw_rect(Rect2(floor(l_pos.x), floor(l_pos.y), px_size, px_size), Color(0.6, 0.3, 1.0, line_alpha * (1.0 - float(li) / float(line_len))))
