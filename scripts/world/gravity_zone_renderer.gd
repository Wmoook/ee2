extends Node2D
## Renders gravity zone visual effects
## Void core = cached texture (zero lag), everything else = live animated pixels

func _ready() -> void:
	z_index = -1
	WorldManager.gravity_zones.zones_changed.connect(_rebuild_caches)

func _rebuild_caches() -> void:
	for gz in WorldManager.gravity_zones.zones:
		if not gz.has("_void_tex"):
			_build_void_cache(gz)
	queue_redraw()

func _build_void_cache(gz: Dictionary) -> void:
	# Only cache the VOID CORE (solid black circle) — it's the expensive part
	var void_r: int = int(round(gz.get("center_radius", 8.0)))
	var sz: int = (void_r + 2) * 2
	var img: Image = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var ic: int = sz / 2
	for py in range(-void_r, void_r + 1):
		var row_w: int = int(sqrt(float(void_r * void_r - py * py)))
		for px in range(-row_w, row_w + 1):
			img.set_pixel(ic + px, ic + py, Color(0, 0, 0, 1))
	gz["_void_tex"] = ImageTexture.create_from_image(img)
	gz["_void_sz"] = sz

func _process(_delta: float) -> void:
	if WorldManager.gravity_zones.zones.size() > 0:
		for gz in WorldManager.gravity_zones.zones:
			if not gz.has("_void_tex"):
				_build_void_cache(gz)
		queue_redraw()

func _draw() -> void:
	var time: float = Time.get_ticks_msec() * 0.001
	for gz in WorldManager.gravity_zones.zones:
		var center: Vector2 = gz.center
		var radius: float = gz.radius
		var void_r: int = int(round(gz.get("center_radius", 8.0)))
		var edit: bool = GameState.is_edit_mode
		var bright: float = 1.0 if edit else 0.7

		# Zone boundary (edit mode only)
		if edit:
			var bpts: int = int(radius * TAU)  # Fill circumference
			for bi in range(bpts):
				var ba: float = TAU * float(bi) / float(bpts) + time * 0.3
				var bw: float = sin(ba * 6.0 + time * 2.0) * 1.5
				var bp: Vector2 = center + Vector2(cos(ba), sin(ba)) * (radius + bw)
				var bb: float = 0.3 + 0.7 * maxf(0, sin(ba * 3.0 - time * 1.5))
				draw_rect(Rect2(floor(bp.x), floor(bp.y), 1, 1), Color(0.5, 0.2, 0.9, bb * 0.5))

		# Pulsing inward rings
		for i in range(4):
			var phase: float = fmod(time * 0.4 + float(i) * 0.25, 1.0)
			var rr: float = radius * (1.0 - phase)
			var ra: float = phase * (1.0 - phase) * 2.0 * (0.7 if edit else 0.2)
			var rpts: int = int(rr * TAU)  # Fill circumference
			for ri in range(rpts):
				var a: float = TAU * float(ri) / float(rpts)
				var rp: Vector2 = center + Vector2(cos(a), sin(a)) * rr
				draw_rect(Rect2(floor(rp.x), floor(rp.y), 1, 1), Color(0.6, 0.3, 1.0, ra))

		# --- BLACK HOLE ---

		# Back half accretion disk (LIVE animated — behind void)
		_draw_accretion(center, void_r, time, bright, true)

		# Void core — cached texture (ONE draw call)
		if gz.has("_void_tex"):
			var half: float = float(gz["_void_sz"]) * 0.5
			draw_texture(gz["_void_tex"], center - Vector2(half, half))

		# Event horizon glow (live — ring around void edge)
		var eh: int = int(float(void_r) * TAU) + 10  # Fill circumference
		for ei in range(eh):
			var ea: float = TAU * float(ei) / float(eh)
			var er: float = float(void_r) + 1.0 + sin(ea * 4.0 + time * 2.5) * 0.5
			var ep: Vector2 = center + Vector2(cos(ea), sin(ea)) * er
			var pulse: float = 0.6 + 0.4 * sin(ea * 2.0 + time * 3.0)
			draw_rect(Rect2(floor(ep.x), floor(ep.y), 1, 1), Color(1.0, 0.6 * pulse, 0.2 * pulse, pulse * bright))

		# Front half accretion disk (LIVE — in front of void)
		_draw_accretion(center, void_r, time, bright, false)

		# Spiral streams (live animated)
		var sc: int = mini(30, 20 + int(float(void_r) * 0.2))
		for si in range(sc):
			var sa: float = TAU * float(si) / float(sc) + time * 1.0
			var sp: float = fmod(time * 0.5 + float(si) / float(sc), 1.0)
			var accel: float = 1.0 - sp * sp * sp
			var sr: float = maxf(radius * 0.8, float(void_r) + 5.0) * accel * accel
			var twist: float = sp * 6.0
			var spos: Vector2 = center + Vector2(cos(sa + twist), sin(sa + twist)) * sr
			if spos.distance_to(center) < float(void_r) + 1.0:
				continue
			var fade: float = clampf(sr / (float(void_r) + 5.0), 0.0, 1.0)
			var sal: float = sp * fade * 2.5 * bright
			draw_rect(Rect2(floor(spos.x), floor(spos.y), 1, 1), Color(lerpf(0.4, 1.0, sp), lerpf(0.6, 0.2, sp), lerpf(1.0, 0.0, sp), sal))

func _draw_accretion(center: Vector2, void_r: int, time: float, bright: float, back: bool) -> void:
	var ring_thick: float = maxf(8.0, float(void_r) * 0.35)
	var num_layers: int = maxi(4, int(ring_thick / 2.5))
	var front_boost: float = 1.0 if back else 1.3
	for layer in range(num_layers):
		var lt: float = float(layer) / float(maxi(num_layers - 1, 1))
		var lr: float = float(void_r) + 1.0 + lt * ring_thick
		var lc: int = mini(200, int(lr * 4.0))
		var speed: float = 2.5 - lt * 1.0
		var squash: float = lerpf(0.5, 0.25, lt)
		for ai in range(lc):
			var aa: float = TAU * float(ai) / float(lc) + time * speed + float(layer) * 0.5
			var wobble: float = sin(aa * 3.0 + time * 2.5 + float(layer)) * (1.0 + lt)
			var ar: float = lr + wobble
			var ap: Vector2 = center + Vector2(cos(aa) * ar, sin(aa) * ar * squash)
			if back and ap.y > center.y:
				continue
			if not back and ap.y <= center.y:
				continue
			if back and ap.distance_to(center) < float(void_r):
				continue
			var ab: float = 0.5 + 0.5 * maxf(0, sin(aa * 1.5 + time * 3.0 + float(layer) * 0.7))
			var alpha: float = lerpf(1.0, 0.7, lt) * ab * bright * front_boost
			draw_rect(Rect2(floor(ap.x), floor(ap.y), 1, 1), Color(1.0, lerpf(0.95, 0.4, lt) * ab, lerpf(0.7, 0.1, lt) * ab * ab, minf(alpha, 1.0)))
