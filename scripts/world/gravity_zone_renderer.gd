extends Node2D
## Renders gravity zone visual effects — cached texture for zero lag

func _ready() -> void:
	z_index = -1
	WorldManager.gravity_zones.zones_changed.connect(_rebuild_all_caches)

func _rebuild_all_caches() -> void:
	for gz in WorldManager.gravity_zones.zones:
		if not gz.has("_cached_tex"):
			_build_cache(gz)
	queue_redraw()

func _build_cache(gz: Dictionary) -> void:
	var center_r: int = int(round(gz.get("center_radius", 8.0)))
	var radius: float = gz.radius
	var ring_thick: float = maxf(8.0, float(center_r) * 0.35)
	var outer_r: int = center_r + int(ring_thick) + 4
	var img_size: int = (outer_r + 2) * 2
	var img: Image = Image.create(img_size, img_size, false, Image.FORMAT_RGBA8)
	var ic: int = img_size / 2  # Image center

	# 1. Back half of accretion disk (top = behind void)
	_draw_accretion_to_image(img, ic, center_r, ring_thick, true)
	# 2. Void core
	for py in range(-center_r, center_r + 1):
		var row_w: int = int(sqrt(float(center_r * center_r - py * py)))
		if row_w > 0:
			for px in range(-row_w, row_w + 1):
				img.set_pixel(ic + px, ic + py, Color(0, 0, 0, 1))
	# 3. Event horizon glow
	var eh_count: int = int(float(center_r) * TAU)
	for ei in range(eh_count):
		var e_angle: float = TAU * float(ei) / float(eh_count)
		var e_r: float = float(center_r) + 1.0
		var ex: int = ic + int(round(cos(e_angle) * e_r))
		var ey: int = ic + int(round(sin(e_angle) * e_r))
		if ex >= 0 and ex < img_size and ey >= 0 and ey < img_size:
			img.set_pixel(ex, ey, Color(1.0, 0.5, 0.1, 0.8))
	# 4. Front half of accretion disk (bottom = in front of void)
	_draw_accretion_to_image(img, ic, center_r, ring_thick, false)

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	gz["_cached_tex"] = tex
	gz["_cached_size"] = img_size

func _draw_accretion_to_image(img: Image, ic: int, void_r: int, ring_thick: float, back_half: bool) -> void:
	var img_size: int = img.get_width()
	var num_layers: int = maxi(4, int(ring_thick / 2.5))
	for layer in range(num_layers):
		var layer_t: float = float(layer) / float(maxi(num_layers - 1, 1))
		var layer_r: float = float(void_r) + 1.0 + layer_t * ring_thick
		var layer_count: int = int(layer_r * 4.0)
		var squash: float = lerpf(0.5, 0.25, layer_t)
		for ai in range(layer_count):
			var a_angle: float = TAU * float(ai) / float(layer_count) + float(layer) * 0.5
			var wobble: float = sin(a_angle * 3.0 + float(layer)) * (1.0 + layer_t)
			var a_r: float = layer_r + wobble
			var ax: int = ic + int(round(cos(a_angle) * a_r))
			var ay: int = ic + int(round(sin(a_angle) * a_r * squash))
			# Back = above center, Front = below
			if back_half and ay > ic:
				continue
			if not back_half and ay <= ic:
				continue
			if ax < 0 or ax >= img_size or ay < 0 or ay >= img_size:
				continue
			var a_bright: float = 0.5 + 0.5 * maxf(0, sin(a_angle * 1.5 + float(layer) * 0.7))
			var r_c: float = 1.0
			var g_c: float = lerpf(0.95, 0.4, layer_t) * a_bright
			var b_c: float = lerpf(0.7, 0.1, layer_t) * a_bright * a_bright
			var a_alpha: float = lerpf(1.0, 0.7, layer_t) * a_bright
			if not back_half:
				a_alpha *= 1.3
			img.set_pixel(ax, ay, Color(r_c, g_c, b_c, minf(a_alpha, 1.0)))

func _process(_delta: float) -> void:
	if WorldManager.gravity_zones.zones.size() > 0:
		# Build cache for any uncached zones
		for gz in WorldManager.gravity_zones.zones:
			if not gz.has("_cached_tex"):
				_build_cache(gz)
		queue_redraw()

func _draw() -> void:
	var time: float = Time.get_ticks_msec() * 0.001
	for gz in WorldManager.gravity_zones.zones:
		var center: Vector2 = gz.center
		var radius: float = gz.radius
		var void_r: float = gz.get("center_radius", 8.0)
		var edit: bool = GameState.is_edit_mode
		var bright: float = 1.0 if edit else 0.7

		# Draw cached black hole texture (ONE draw call, rotates for animation)
		if gz.has("_cached_tex"):
			var tex: Texture2D = gz["_cached_tex"]
			var sz: int = gz.get("_cached_size", 32)
			var half: float = float(sz) * 0.5
			# Slow rotation for animation
			draw_set_transform(center, time * 0.15, Vector2.ONE)
			draw_texture(tex, Vector2(-half, -half), Color(1, 1, 1, bright))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

		# Lightweight animated elements (drawn per-frame, few draw calls)
		# Zone boundary — swirling pixel ring
		if edit:
			var border_pts: int = int(radius * 2.5) + 20
			for bi in range(border_pts):
				var b_angle: float = TAU * float(bi) / float(border_pts) + time * 0.3
				var b_wobble: float = sin(b_angle * 6.0 + time * 2.0) * 1.5
				var b_pos: Vector2 = center + Vector2(cos(b_angle), sin(b_angle)) * (radius + b_wobble)
				var b_bright: float = 0.3 + 0.7 * maxf(0, sin(b_angle * 3.0 - time * 1.5))
				draw_rect(Rect2(floor(b_pos.x), floor(b_pos.y), 1, 1), Color(0.5, 0.2, 0.9, b_bright * 0.5))

		# Pulsing inward rings (lightweight — 4 rings)
		for i in range(4):
			var phase: float = fmod(time * 0.4 + float(i) * 0.25, 1.0)
			var ring_r: float = radius * (1.0 - phase)
			var ring_alpha: float = phase * (1.0 - phase) * 2.0 * (0.7 if edit else 0.2)
			var ring_pts: int = mini(60, int(ring_r * 1.5) + 8)
			for ri in range(ring_pts):
				var r_angle: float = TAU * float(ri) / float(ring_pts)
				var r_pos: Vector2 = center + Vector2(cos(r_angle), sin(r_angle)) * ring_r
				draw_rect(Rect2(floor(r_pos.x), floor(r_pos.y), 1, 1), Color(0.6, 0.3, 1.0, ring_alpha))

		# Spiral streams (lightweight — per-frame animation)
		var spiral_count: int = mini(30, 20 + int(void_r * 0.2))
		for si in range(spiral_count):
			var s_angle: float = TAU * float(si) / float(spiral_count) + time * 1.0
			var s_phase: float = fmod(time * 0.5 + float(si) / float(spiral_count), 1.0)
			var accel: float = 1.0 - s_phase * s_phase * s_phase
			var s_r: float = maxf(radius * 0.8, void_r + 5.0) * accel * accel
			var spiral_twist: float = s_phase * 6.0
			var s_pos: Vector2 = center + Vector2(cos(s_angle + spiral_twist), sin(s_angle + spiral_twist)) * s_r
			if s_pos.distance_to(center) < void_r + 1.0:
				continue
			var fade: float = clampf(s_r / (void_r + 5.0), 0.0, 1.0)
			var s_alpha: float = s_phase * fade * 2.5 * bright
			var rc: float = lerpf(0.4, 1.0, s_phase)
			var gc: float = lerpf(0.6, 0.2, s_phase)
			var bc: float = lerpf(1.0, 0.0, s_phase)
			draw_rect(Rect2(floor(s_pos.x), floor(s_pos.y), 1, 1), Color(rc, gc, bc, s_alpha))
