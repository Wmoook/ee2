extends SceneTree
## MEGA BLOCK PACK GENERATOR — run:
##   godot --headless --path . --script res://tools/gen_packs2.gd
## Writes assets/sprites/BLOCK_PACKS/<id>.png (40x40) + <id>_16.png (LANCZOS).
## 9 new packs (JUNGLE OCEAN SPACE FACTORY DESERT DREAM ARCADE GEMS SPOOKY,
## ids 6000..6071) + CURVES II ribbons (6080..6089, horizontally symmetric
## for seamless curve-mesh mirroring).

const OUT: String = "res://assets/sprites/BLOCK_PACKS/"
var img: Image
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_build()
	_init_ribbons()
	var ids: Array = []
	for id in RECIPES:
		rng.seed = id * 7919 + 13
		img = Image.create(40, 40, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 1))
		RECIPES[id].call()
		img.save_png(OUT + "%d.png" % id)
		var small: Image = img.duplicate()
		small.resize(16, 16, Image.INTERPOLATE_LANCZOS)
		small.save_png(OUT + "%d_16.png" % id)
		ids.append(id)
	print("PACKS2 DONE: %d blocks" % ids.size())
	quit()

# ==================== toolkit ====================

func px(x: int, y: int, c: Color) -> void:
	if x >= 0 and x < 40 and y >= 0 and y < 40:
		img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))

func getp(x: int, y: int) -> Color:
	return img.get_pixel(clampi(x, 0, 39), clampi(y, 0, 39))

func fill_all(c: Color) -> void:
	img.fill(Color(c.r, c.g, c.b, 1.0))

func vgrad(top: Color, bot: Color) -> void:
	for y in range(40):
		var c: Color = top.lerp(bot, y / 39.0)
		for x in range(40):
			px(x, y, c)

func rgrad(center: Color, edge: Color, cx: float = 19.5, cy: float = 19.5, r: float = 28.0) -> void:
	for y in range(40):
		for x in range(40):
			var d: float = clampf(Vector2(x - cx, y - cy).length() / r, 0.0, 1.0)
			px(x, y, center.lerp(edge, d))

func mul_rect(x0: int, y0: int, w: int, h: int, f: float) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			var c: Color = getp(x, y)
			px(x, y, Color(c.r * f, c.g * f, c.b * f))

func rect(x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			px(x, y, c)

func frame(x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for x in range(x0, x0 + w):
		px(x, y0, c)
		px(x, y0 + h - 1, c)
	for y in range(y0, y0 + h):
		px(x0, y, c)
		px(x0 + w - 1, y, c)

func bevel(amt: float = 0.16) -> void:
	for i in range(40):
		for e in [[0, i, 1.0], [i, 0, 1.0], [1, i, 0.5], [i, 1, 0.5]]:
			var c: Color = getp(e[0], e[1])
			px(e[0], e[1], Color(c.r + amt * e[2], c.g + amt * e[2], c.b + amt * e[2]))
		for e2 in [[39, i, 1.0], [i, 39, 1.0], [38, i, 0.5], [i, 38, 0.5]]:
			var c2: Color = getp(e2[0], e2[1])
			px(e2[0], e2[1], Color(c2.r - amt * e2[2], c2.g - amt * e2[2], c2.b - amt * e2[2]))

func speckle(n: int, c: Color, sz: int = 1) -> void:
	for _i in range(n):
		var x: int = rng.randi_range(2, 37)
		var y: int = rng.randi_range(2, 37)
		rect(x, y, sz, sz, c)

func glow(cx: float, cy: float, r: float, c: Color, power: float = 1.0) -> void:
	for y in range(maxi(0, int(cy - r)), mini(40, int(cy + r + 1))):
		for x in range(maxi(0, int(cx - r)), mini(40, int(cx + r + 1))):
			var d: float = Vector2(x - cx, y - cy).length()
			if d < r:
				var f: float = pow(1.0 - d / r, 2.0) * power
				var b: Color = getp(x, y)
				px(x, y, Color(b.r + c.r * f, b.g + c.g * f, b.b + c.b * f))

func bricks(bw: int, bh: int, base: Color, mortar: Color, jitter: float = 0.06) -> void:
	for y in range(40):
		var row: int = y / bh
		var off: int = (row % 2) * (bw / 2)
		for x in range(40):
			var bx: int = (x + off) % bw
			var col_i: int = (x + off) / bw
			var h: float = fmod(sin(float(row * 37 + col_i * 91 + 7)) * 43758.5453, 1.0)
			var shade: float = 1.0 + (h - 0.5) * jitter * 2.0
			if y % bh >= bh - 2 or bx >= bw - 2:
				px(x, y, mortar)
			else:
				px(x, y, Color(base.r * shade, base.g * shade, base.b * shade))

func diag_stripes(w: int, a: Color, b: Color) -> void:
	for y in range(40):
		for x in range(40):
			px(x, y, a if ((x + y) / w) % 2 == 0 else b)

func checker(sz: int, a: Color, b: Color) -> void:
	for y in range(40):
		for x in range(40):
			px(x, y, a if ((x / sz) + (y / sz)) % 2 == 0 else b)

func scanlines(period: int, c: Color, strength: float = 1.0) -> void:
	for y in range(0, 40, period):
		for x in range(40):
			var b: Color = getp(x, y)
			px(x, y, b.lerp(c, strength))

func sparkle(cx: int, cy: int, r: int, c: Color) -> void:
	for i in range(-r, r + 1):
		px(cx + i, cy, c)
		px(cx, cy + i, c)
	px(cx, cy, Color(1, 1, 1))

func wave_rows(colors: Array, amp: float, period: float) -> void:
	var n: int = colors.size()
	for y in range(40):
		for x in range(40):
			var w: float = sin(x * period) * amp
			var band: int = clampi(int((y + w) / (40.0 / n)), 0, n - 1)
			px(x, y, colors[band])

func facet_gem(base: Color, hi: Color, lo: Color) -> void:
	## Brilliant-cut gem: triangular facets around a bright table
	vgrad(lo.lerp(base, 0.4), lo)
	var pts: Array = []
	for i in range(8):
		var a: float = TAU * i / 8.0 + 0.39
		pts.append(Vector2(19.5, 19.5) + Vector2.from_angle(a) * 17.0)
	for y in range(2, 38):
		for x in range(2, 38):
			var v: Vector2 = Vector2(x, y)
			var d: float = v.distance_to(Vector2(19.5, 19.5))
			if d > 17.5:
				continue
			var ang: float = fmod(atan2(y - 19.5, x - 19.5) + TAU + 0.39, TAU)
			var seg: int = int(ang / (TAU / 8.0)) % 8
			var f: float = fmod(sin(float(seg * 51 + 17)) * 137.13, 1.0)
			var c: Color = base.lerp(hi, f * 0.55)
			if d < 8.0:
				c = base.lerp(hi, 0.75)  # table
			elif fmod(ang, TAU / 8.0) < 0.09:
				c = lo  # facet edge
			px(x, y, c)
	frame(1, 1, 38, 38, lo)
	sparkle(13, 12, 2, hi)

func stud(cx: int, cy: int, r: int, base: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			var d: float = Vector2(x - cx, y - cy).length()
			if d <= r:
				var f: float = 1.25 - d / r * 0.6
				px(x, y, Color(base.r * f, base.g * f, base.b * f))

# curve ribbons: mirror-safe (sx folded), cylinder shading
func ribbon(fn: Callable) -> void:
	for y in range(40):
		for x in range(40):
			var sx: int = x if x < 20 else 39 - x
			px(x, y, fn.call(sx, y))

func cyl(y: int) -> float:
	return 0.52 + 0.48 * sin(PI * y / 39.0)

# ==================== recipes ====================

var RECIPES: Dictionary = {}

func _build() -> void:
	# ---- JUNGLE 6000-6007 ----
	RECIPES[6000] = func() -> void:  # Canopy Leaf
		vgrad(Color(0.22, 0.55, 0.2), Color(0.08, 0.3, 0.1))
		for _i in range(26):
			var x: int = rng.randi_range(2, 35)
			var y: int = rng.randi_range(2, 35)
			var g: float = rng.randf_range(0.35, 0.7)
			rect(x, y, rng.randi_range(3, 6), 2, Color(0.18, g, 0.16))
			rect(x + 1, y - 1, 2, 1, Color(0.3, g + 0.2, 0.25))
		bevel()
	RECIPES[6001] = func() -> void:  # Mossy Log
		vgrad(Color(0.42, 0.29, 0.15), Color(0.28, 0.18, 0.08))
		for y in range(0, 40, 6):
			for x in range(40):
				px(x, y + (x / 13) % 2, Color(0.22, 0.13, 0.05))
		for _i in range(5):
			var mx: int = rng.randi_range(0, 32)
			rect(mx, rng.randi_range(0, 3), rng.randi_range(5, 9), rng.randi_range(2, 4), Color(0.3, 0.55, 0.2))
		bevel()
	RECIPES[6002] = func() -> void:  # Bamboo
		fill_all(Color(0.1, 0.2, 0.08))
		for i in range(4):
			var x0: int = i * 10 + 1
			for x in range(x0, x0 + 8):
				for y in range(40):
					var f: float = 1.0 - absf(x - x0 - 3.5) / 6.0
					px(x, y, Color(0.35 * f + 0.25, 0.62 * f + 0.25, 0.2 * f + 0.1))
			for y in [9, 24, 33]:
				rect(x0, y + i, 8, 2, Color(0.25, 0.38, 0.12))
		bevel()
	RECIPES[6003] = func() -> void:  # Temple Stone
		bricks(20, 10, Color(0.42, 0.46, 0.38), Color(0.2, 0.24, 0.18))
		rect(14, 14, 12, 12, Color(0.3, 0.36, 0.26))
		frame(14, 14, 12, 12, Color(0.55, 0.6, 0.42))
		rect(18, 18, 4, 4, Color(0.72, 0.68, 0.4))
		bevel()
	RECIPES[6004] = func() -> void:  # Vine Wall
		bricks(13, 13, Color(0.35, 0.36, 0.33), Color(0.18, 0.2, 0.17))
		var vx: float = 6.0
		for y in range(40):
			vx += sin(y * 0.5) * 1.6
			rect(int(vx), y, 2, 1, Color(0.2, 0.5, 0.16))
			rect(int(38.0 - vx), y, 2, 1, Color(0.16, 0.42, 0.14))
			if y % 7 == 3:
				rect(int(vx) - 2, y, 2, 2, Color(0.35, 0.68, 0.25))
		bevel()
	RECIPES[6005] = func() -> void:  # Bloom
		vgrad(Color(0.16, 0.4, 0.18), Color(0.1, 0.26, 0.12))
		for i in range(6):
			var a: float = TAU * i / 6.0
			var p: Vector2 = Vector2(19.5, 19.5) + Vector2.from_angle(a) * 9.0
			glow(p.x, p.y, 8.0, Color(0.55, 0.12, 0.3), 0.9)
		glow(19.5, 19.5, 7.0, Color(0.9, 0.65, 0.2), 1.2)
		sparkle(20, 19, 2, Color(1.0, 0.95, 0.7))
		bevel()
	RECIPES[6006] = func() -> void:  # Root Tangle
		vgrad(Color(0.24, 0.16, 0.1), Color(0.14, 0.09, 0.05))
		for _i in range(6):
			var y: float = rng.randf_range(4, 36)
			var ph: float = rng.randf_range(0.0, TAU)
			for x in range(40):
				var yy: int = int(y + sin(x * 0.3 + ph) * 3.0)
				rect(x, yy, 1, 2, Color(0.45, 0.32, 0.18))
				px(x, yy - 1, Color(0.55, 0.42, 0.26))
		bevel()
	RECIPES[6007] = func() -> void:  # Glowshroom
		vgrad(Color(0.09, 0.07, 0.16), Color(0.05, 0.04, 0.1))
		for _i in range(4):
			var x: int = rng.randi_range(6, 33)
			var y: int = rng.randi_range(10, 33)
			rect(x - 1, y, 2, 6, Color(0.5, 0.48, 0.42))
			for dx in range(-4, 5):
				var h: int = int(sqrt(maxf(16.0 - dx * dx, 0.0)) * 0.9)
				rect(x + dx - 1, y - h, 1, h, Color(0.2, 0.75, 0.85))
			glow(x, y - 3, 7.0, Color(0.1, 0.5, 0.6), 1.0)
		bevel()

	# ---- OCEAN 6008-6015 ----
	RECIPES[6008] = func() -> void:  # Deep Water
		vgrad(Color(0.1, 0.4, 0.65), Color(0.02, 0.12, 0.32))
		for _i in range(5):
			var y: int = rng.randi_range(3, 34)
			for x in range(40):
				var yy: int = y + int(sin(x * 0.35 + y) * 1.8)
				px(x, yy, Color(0.3, 0.6, 0.85))
		speckle(8, Color(0.75, 0.9, 1.0))
	RECIPES[6009] = func() -> void:  # Coral Pink
		vgrad(Color(0.9, 0.4, 0.5), Color(0.6, 0.16, 0.3))
		for _i in range(7):
			var x: float = rng.randf_range(5, 34)
			var ph2: float = rng.randf_range(0.0, TAU)
			for y in range(6, 40):
				var xx: int = int(x + sin(y * 0.35 + ph2) * 2.5)
				rect(xx, y, 2, 1, Color(1.0, 0.6, 0.68))
		speckle(20, Color(1.0, 0.78, 0.8))
		bevel()
	RECIPES[6010] = func() -> void:  # Coral Cyan
		vgrad(Color(0.2, 0.75, 0.75), Color(0.05, 0.42, 0.5))
		for _i in range(9):
			var cx: float = rng.randf_range(4, 36)
			var cy: float = rng.randf_range(4, 36)
			for a in range(6):
				var v: Vector2 = Vector2.from_angle(TAU * a / 6.0) * 4.0
				rect(int(cx + v.x), int(cy + v.y), 2, 2, Color(0.5, 0.95, 0.9))
		bevel()
	RECIPES[6011] = func() -> void:  # Golden Sand
		vgrad(Color(0.93, 0.82, 0.55), Color(0.78, 0.62, 0.35))
		for y in range(0, 40, 7):
			for x in range(40):
				px(x, y + int(sin(x * 0.3) * 2.0) + 3, Color(0.85, 0.7, 0.42))
		speckle(40, Color(0.98, 0.92, 0.7))
		speckle(16, Color(0.65, 0.5, 0.28))
		bevel()
	RECIPES[6012] = func() -> void:  # Shell Tile
		vgrad(Color(0.92, 0.88, 0.84), Color(0.7, 0.6, 0.62))
		for i in range(7):
			var a: float = PI * (0.15 + 0.7 * i / 6.0)
			for r in range(6, 19):
				var p: Vector2 = Vector2(19.5, 30.0) - Vector2(cos(a), sin(a)) * r
				px(int(p.x), int(p.y), Color(0.82, 0.7, 0.72))
		glow(19.5, 28.0, 6.0, Color(0.3, 0.2, 0.24), 0.6)
		bevel()
	RECIPES[6013] = func() -> void:  # Kelp Weave
		vgrad(Color(0.05, 0.3, 0.28), Color(0.02, 0.16, 0.16))
		for i in range(5):
			var x0: float = 4.0 + i * 8.0
			for y in range(40):
				var xx: int = int(x0 + sin(y * 0.25 + i * 1.7) * 3.0)
				rect(xx, y, 3, 1, Color(0.15, 0.55, 0.3))
				px(xx + 1, y, Color(0.3, 0.72, 0.4))
		bevel()
	RECIPES[6014] = func() -> void:  # Bubble Stone
		vgrad(Color(0.3, 0.44, 0.52), Color(0.16, 0.26, 0.34))
		for _i in range(9):
			var cx: float = rng.randf_range(5, 35)
			var cy: float = rng.randf_range(5, 35)
			var r: float = rng.randf_range(2, 5)
			for y in range(int(cy - r), int(cy + r) + 1):
				for x in range(int(cx - r), int(cx + r) + 1):
					var d: float = Vector2(x - cx, y - cy).length()
					if absf(d - r) < 0.8:
						px(x, y, Color(0.6, 0.82, 0.9))
			px(int(cx - r * 0.4), int(cy - r * 0.4), Color(0.9, 1.0, 1.0))
		bevel()
	RECIPES[6015] = func() -> void:  # Treasure Hoard
		vgrad(Color(0.5, 0.36, 0.14), Color(0.3, 0.2, 0.06))
		for _i in range(30):
			var x: int = rng.randi_range(2, 35)
			var y: int = rng.randi_range(int(8 + x / 4), 37)
			rect(x, y, 3, 2, Color(1.0, 0.8, 0.25))
			px(x + 1, y, Color(1.0, 0.95, 0.6))
		sparkle(9, 12, 2, Color(1.0, 1.0, 0.8))
		sparkle(30, 18, 2, Color(1.0, 1.0, 0.8))
		bevel()

	# ---- SPACE 6016-6023 ----
	RECIPES[6016] = func() -> void:  # Starfield
		vgrad(Color(0.03, 0.03, 0.1), Color(0.01, 0.01, 0.05))
		for _i in range(34):
			var x: int = rng.randi_range(1, 38)
			var y: int = rng.randi_range(1, 38)
			var b: float = rng.randf_range(0.4, 1.0)
			px(x, y, Color(b, b, b * 1.05))
		sparkle(10, 9, 2, Color(0.9, 0.95, 1.0))
		sparkle(29, 27, 1, Color(1.0, 0.9, 0.8))
	RECIPES[6017] = func() -> void:  # Nebula
		rgrad(Color(0.5, 0.2, 0.6), Color(0.06, 0.02, 0.14), 14.0, 24.0, 30.0)
		glow(28.0, 10.0, 14.0, Color(0.15, 0.3, 0.6), 1.0)
		glow(12.0, 26.0, 10.0, Color(0.6, 0.2, 0.3), 0.8)
		for _i in range(22):
			var b2: float = rng.randf_range(0.5, 1.0)
			px(rng.randi_range(1, 38), rng.randi_range(1, 38), Color(b2, b2, 1.0))
	RECIPES[6018] = func() -> void:  # Asteroid
		rgrad(Color(0.5, 0.46, 0.44), Color(0.2, 0.18, 0.17))
		for _i in range(7):
			var cx: float = rng.randf_range(5, 35)
			var cy: float = rng.randf_range(5, 35)
			var r: float = rng.randf_range(2.5, 5.5)
			for y in range(int(cy - r), int(cy + r) + 1):
				for x in range(int(cx - r), int(cx + r) + 1):
					var d: float = Vector2(x - cx, y - cy).length()
					if d < r:
						px(x, y, Color(0.24, 0.22, 0.21).lerp(Color(0.12, 0.11, 0.1), d / r))
			for x2 in range(int(cx - r), int(cx + r)):
				px(x2, int(cy - r), Color(0.55, 0.52, 0.5))
		bevel()
	RECIPES[6019] = func() -> void:  # Hull Plate
		vgrad(Color(0.55, 0.58, 0.66), Color(0.34, 0.37, 0.45))
		frame(1, 1, 38, 38, Color(0.24, 0.26, 0.32))
		rect(1, 19, 38, 2, Color(0.28, 0.3, 0.37))
		for p in [[6, 6], [33, 6], [6, 33], [33, 33]]:
			stud(p[0], p[1], 2, Color(0.6, 0.64, 0.72))
		bevel()
	RECIPES[6020] = func() -> void:  # Portlight
		vgrad(Color(0.4, 0.43, 0.5), Color(0.25, 0.27, 0.33))
		for y in range(40):
			for x in range(40):
				var d: float = Vector2(x - 19.5, y - 19.5).length()
				if d < 12.0:
					var deep: Color = Color(0.05, 0.1, 0.25).lerp(Color(0.2, 0.5, 0.9), 1.0 - d / 12.0)
					px(x, y, deep)
				elif d < 15.0:
					px(x, y, Color(0.65, 0.68, 0.75))
		for _i in range(6):
			px(rng.randi_range(12, 27), rng.randi_range(12, 27), Color(0.9, 0.95, 1.0))
		bevel()
	RECIPES[6021] = func() -> void:  # Solar Cell
		fill_all(Color(0.05, 0.1, 0.3))
		for y in range(0, 40, 10):
			for x in range(40):
				rect(x, y, 1, 2, Color(0.2, 0.3, 0.55))
		for x in range(0, 40, 10):
			for y in range(40):
				rect(x, y, 2, 1, Color(0.2, 0.3, 0.55))
		for y2 in range(40):
			for x2 in range(40):
				if (x2 + y2) % 17 == 0:
					px(x2, y2, Color(0.5, 0.7, 1.0))
		bevel(0.2)
	RECIPES[6022] = func() -> void:  # Hazard Stripe
		diag_stripes(8, Color(0.95, 0.75, 0.1), Color(0.12, 0.12, 0.14))
		mul_rect(0, 32, 40, 8, 0.75)
		mul_rect(0, 0, 40, 6, 1.15)
		bevel()
	RECIPES[6023] = func() -> void:  # Reactor Core
		fill_all(Color(0.08, 0.1, 0.12))
		frame(2, 2, 36, 36, Color(0.3, 0.36, 0.4))
		glow(19.5, 19.5, 15.0, Color(0.1, 0.9, 0.5), 1.3)
		glow(19.5, 19.5, 7.0, Color(0.6, 1.0, 0.7), 1.2)
		for i in range(4):
			var a2: float = TAU * i / 4.0 + 0.4
			var p2: Vector2 = Vector2(19.5, 19.5) + Vector2.from_angle(a2) * 13.0
			rect(int(p2.x) - 1, int(p2.y) - 1, 3, 3, Color(0.2, 0.26, 0.3))
		bevel()

	# ---- FACTORY 6024-6031 ----
	RECIPES[6024] = func() -> void:  # Steel Plate
		vgrad(Color(0.6, 0.62, 0.66), Color(0.4, 0.42, 0.47))
		for y in range(0, 40, 4):
			for x in range(40):
				var c3: Color = getp(x, y)
				px(x, y, Color(c3.r * 1.06, c3.g * 1.06, c3.b * 1.06))
		for p3 in [[5, 5], [34, 5], [5, 34], [34, 34]]:
			stud(p3[0], p3[1], 2, Color(0.55, 0.57, 0.62))
		bevel()
	RECIPES[6025] = func() -> void:  # Rust Plate
		vgrad(Color(0.5, 0.34, 0.24), Color(0.35, 0.2, 0.13))
		for _i in range(14):
			var x3: int = rng.randi_range(2, 33)
			var y3: int = rng.randi_range(2, 33)
			rect(x3, y3, rng.randi_range(3, 7), rng.randi_range(2, 5), Color(0.66, 0.42, 0.2))
		speckle(30, Color(0.3, 0.16, 0.1))
		frame(1, 1, 38, 38, Color(0.28, 0.17, 0.11))
		bevel()
	RECIPES[6026] = func() -> void:  # Vent Grate
		fill_all(Color(0.2, 0.22, 0.25))
		for y in range(4, 36, 5):
			rect(4, y, 32, 3, Color(0.07, 0.08, 0.1))
			rect(4, y, 32, 1, Color(0.34, 0.37, 0.42))
		frame(2, 2, 36, 36, Color(0.4, 0.43, 0.48))
		bevel()
	RECIPES[6027] = func() -> void:  # Gearbox
		fill_all(Color(0.24, 0.25, 0.28))
		for g in [[12.0, 12.0, 9.0], [30.0, 28.0, 7.0]]:
			for i in range(10):
				var a3: float = TAU * i / 10.0
				var p4: Vector2 = Vector2(g[0], g[1]) + Vector2.from_angle(a3) * g[2]
				rect(int(p4.x) - 1, int(p4.y) - 1, 3, 3, Color(0.55, 0.55, 0.5))
			for y4 in range(40):
				for x4 in range(40):
					var d2: float = Vector2(x4 - g[0], y4 - g[1]).length()
					if d2 < g[2] - 1.0:
						px(x4, y4, Color(0.45, 0.45, 0.42).lerp(Color(0.3, 0.3, 0.28), d2 / g[2]))
					if d2 < 2.2:
						px(x4, y4, Color(0.16, 0.16, 0.18))
		bevel()
	RECIPES[6028] = func() -> void:  # Pipe Grid
		fill_all(Color(0.16, 0.18, 0.2))
		for x in [7, 25]:
			for xx2 in range(x, x + 8):
				for y in range(40):
					var f2: float = 1.0 - absf(xx2 - x - 3.5) / 6.0
					px(xx2, y, Color(0.3 + 0.35 * f2, 0.34 + 0.35 * f2, 0.4 + 0.35 * f2))
			rect(x - 1, 8, 10, 3, Color(0.5, 0.52, 0.58))
			rect(x - 1, 29, 10, 3, Color(0.5, 0.52, 0.58))
		bevel()
	RECIPES[6029] = func() -> void:  # Caution Tape
		fill_all(Color(0.85, 0.65, 0.05))
		diag_stripes(10, Color(0.95, 0.78, 0.12), Color(0.1, 0.1, 0.1))
		rect(0, 0, 40, 4, Color(0.16, 0.16, 0.16))
		rect(0, 36, 40, 4, Color(0.16, 0.16, 0.16))
		bevel()
	RECIPES[6030] = func() -> void:  # Server Rack
		fill_all(Color(0.1, 0.11, 0.14))
		for y in range(3, 37, 6):
			rect(3, y, 34, 4, Color(0.17, 0.19, 0.23))
			for i in range(6):
				var on: bool = rng.randf() < 0.6
				px(6 + i * 3, y + 1, Color(0.2, 0.9, 0.4) if on else Color(0.5, 0.12, 0.12))
			rect(28, y + 1, 6, 2, Color(0.06, 0.07, 0.09))
		frame(1, 1, 38, 38, Color(0.3, 0.32, 0.38))
		bevel()
	RECIPES[6031] = func() -> void:  # Conveyor
		vgrad(Color(0.3, 0.32, 0.36), Color(0.18, 0.2, 0.23))
		for x in range(0, 40, 8):
			for y in range(6, 34):
				rect(x + (y / 6) % 2, y, 3, 1, Color(0.1, 0.11, 0.13))
		rect(0, 2, 40, 3, Color(0.5, 0.53, 0.6))
		rect(0, 35, 40, 3, Color(0.5, 0.53, 0.6))
		stud(4, 20, 3, Color(0.44, 0.46, 0.52))
		stud(35, 20, 3, Color(0.44, 0.46, 0.52))
		bevel()

	# ---- DESERT 6032-6039 ----
	RECIPES[6032] = func() -> void:  # Sandstone
		bricks(20, 10, Color(0.85, 0.68, 0.42), Color(0.6, 0.45, 0.26), 0.1)
		speckle(24, Color(0.92, 0.78, 0.52))
		bevel()
	RECIPES[6033] = func() -> void:  # Glyph Stone
		vgrad(Color(0.78, 0.6, 0.36), Color(0.6, 0.44, 0.24))
		frame(3, 3, 34, 34, Color(0.45, 0.32, 0.16))
		var glyphs: Array = [[8, 8], [20, 8], [30, 8], [8, 19], [20, 19], [30, 19], [8, 30], [20, 30]]
		for gp in glyphs:
			var kind: int = rng.randi_range(0, 2)
			var c4: Color = Color(0.4, 0.26, 0.12)
			if kind == 0:
				frame(gp[0] - 2, gp[1] - 2, 5, 5, c4)
			elif kind == 1:
				rect(gp[0] - 2, gp[1], 5, 1, c4)
				rect(gp[0], gp[1] - 2, 1, 5, c4)
			else:
				stud(gp[0], gp[1], 2, Color(0.5, 0.34, 0.16))
		bevel()
	RECIPES[6034] = func() -> void:  # Pharaoh Gold
		vgrad(Color(0.98, 0.8, 0.3), Color(0.75, 0.55, 0.12))
		for y in range(0, 40, 8):
			rect(0, y, 40, 2, Color(0.55, 0.38, 0.08))
			rect(0, y + 2, 40, 1, Color(1.0, 0.92, 0.55))
		rect(14, 12, 12, 16, Color(0.25, 0.5, 0.65))
		frame(14, 12, 12, 16, Color(0.5, 0.34, 0.06))
		bevel()
	RECIPES[6035] = func() -> void:  # Dune Sand
		vgrad(Color(0.95, 0.85, 0.6), Color(0.8, 0.66, 0.4))
		for i in range(4):
			var yb: float = 8.0 + i * 9.0
			for x in range(40):
				var yy2: int = int(yb + sin(x * 0.18 + i * 2.0) * 3.5)
				px(x, yy2, Color(0.72, 0.56, 0.32))
				px(x, yy2 + 1, Color(0.99, 0.92, 0.68))
		speckle(18, Color(0.7, 0.55, 0.3))
	RECIPES[6036] = func() -> void:  # Cracked Clay
		vgrad(Color(0.72, 0.45, 0.3), Color(0.55, 0.32, 0.2))
		for _i in range(6):
			var x5: float = rng.randf_range(2, 37)
			var y5: float = rng.randf_range(2, 37)
			for _s in range(9):
				var step: Vector2 = Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(2.0, 4.0)
				var nx: float = clampf(x5 + step.x, 1, 38)
				var ny: float = clampf(y5 + step.y, 1, 38)
				for t in range(6):
					var q: Vector2 = Vector2(x5, y5).lerp(Vector2(nx, ny), t / 5.0)
					px(int(q.x), int(q.y), Color(0.35, 0.18, 0.1))
				x5 = nx
				y5 = ny
		bevel()
	RECIPES[6037] = func() -> void:  # Pyramid Brick
		bricks(13, 13, Color(0.88, 0.74, 0.5), Color(0.62, 0.48, 0.28), 0.12)
		for y in range(40):
			for x in range(40):
				if x + y < 12:
					var c5: Color = getp(x, y)
					px(x, y, Color(c5.r * 1.15, c5.g * 1.15, c5.b * 1.12))
		bevel()
	RECIPES[6038] = func() -> void:  # Oasis Tile
		vgrad(Color(0.2, 0.75, 0.68), Color(0.06, 0.45, 0.44))
		for _i in range(4):
			var y6: int = rng.randi_range(4, 34)
			for x in range(40):
				px(x, y6 + int(sin(x * 0.4) * 1.5), Color(0.55, 0.95, 0.85))
		frame(1, 1, 38, 38, Color(0.9, 0.75, 0.4))
		frame(2, 2, 36, 36, Color(0.8, 0.62, 0.3))
		bevel()
	RECIPES[6039] = func() -> void:  # Scarab Lapis
		vgrad(Color(0.12, 0.2, 0.55), Color(0.06, 0.1, 0.35))
		speckle(20, Color(0.3, 0.45, 0.85))
		speckle(10, Color(0.95, 0.8, 0.35))
		stud(19, 17, 6, Color(0.16, 0.3, 0.7))
		stud(19, 12, 3, Color(0.2, 0.36, 0.78))
		rect(13, 22, 3, 8, Color(0.95, 0.8, 0.3))
		rect(24, 22, 3, 8, Color(0.95, 0.8, 0.3))
		bevel()

	# ---- DREAM 6040-6047 ----
	RECIPES[6040] = func() -> void:  # Cloud Puff
		rgrad(Color(1.0, 1.0, 1.0), Color(0.78, 0.84, 0.95), 16.0, 14.0, 34.0)
		for _i in range(6):
			glow(rng.randf_range(6, 34), rng.randf_range(6, 34), rng.randf_range(6, 11), Color(0.06, 0.06, 0.1), 0.25)
		bevel(0.08)
	RECIPES[6041] = func() -> void:  # Mint Whip
		vgrad(Color(0.72, 0.97, 0.86), Color(0.5, 0.85, 0.72))
		for y in range(40):
			for x in range(40):
				if sin((x + y * 2) * 0.35) > 0.6:
					var c6: Color = getp(x, y)
					px(x, y, Color(c6.r * 1.08, c6.g * 1.06, c6.b * 1.06))
		bevel(0.1)
	RECIPES[6042] = func() -> void:  # Lavender Haze
		vgrad(Color(0.8, 0.72, 0.97), Color(0.6, 0.5, 0.85))
		glow(12.0, 12.0, 12.0, Color(0.16, 0.1, 0.2), 0.3)
		glow(30.0, 28.0, 12.0, Color(0.2, 0.12, 0.25), 0.3)
		speckle(8, Color(0.95, 0.9, 1.0))
		bevel(0.1)
	RECIPES[6043] = func() -> void:  # Peach Sky
		vgrad(Color(1.0, 0.8, 0.65), Color(0.95, 0.6, 0.55))
		for i in range(3):
			var y7: int = 8 + i * 11
			for x in range(40):
				px(x, y7 + int(sin(x * 0.2 + i) * 2.0), Color(1.0, 0.9, 0.75))
		bevel(0.09)
	RECIPES[6044] = func() -> void:  # Star Cream
		vgrad(Color(0.98, 0.96, 0.86), Color(0.9, 0.84, 0.68))
		sparkle(10, 10, 2, Color(1.0, 0.85, 0.4))
		sparkle(28, 16, 3, Color(1.0, 0.75, 0.3))
		sparkle(16, 30, 2, Color(1.0, 0.85, 0.4))
		bevel(0.09)
	RECIPES[6045] = func() -> void:  # Cotton Rose
		rgrad(Color(1.0, 0.85, 0.9), Color(0.94, 0.62, 0.75), 22.0, 24.0, 32.0)
		for _i in range(5):
			glow(rng.randf_range(5, 35), rng.randf_range(5, 35), 8.0, Color(0.1, 0.02, 0.05), 0.2)
		bevel(0.08)
	RECIPES[6046] = func() -> void:  # Moon Milk
		vgrad(Color(0.88, 0.9, 0.99), Color(0.7, 0.74, 0.92))
		stud(27, 12, 7, Color(0.95, 0.96, 1.0))
		glow(27.0, 12.0, 11.0, Color(0.2, 0.2, 0.3), 0.25)
		speckle(6, Color(1.0, 1.0, 1.0))
		bevel(0.09)
	RECIPES[6047] = func() -> void:  # Aurora Silk
		for y in range(40):
			for x in range(40):
				var t: float = y / 39.0 + sin(x * 0.2) * 0.08
				var c7: Color
				if t < 0.33:
					c7 = Color(0.55, 0.95, 0.85).lerp(Color(0.6, 0.7, 0.98), t * 3.0)
				elif t < 0.66:
					c7 = Color(0.6, 0.7, 0.98).lerp(Color(0.9, 0.65, 0.9), (t - 0.33) * 3.0)
				else:
					c7 = Color(0.9, 0.65, 0.9).lerp(Color(0.99, 0.85, 0.7), (t - 0.66) * 3.0)
				px(x, y, c7)
		bevel(0.09)

	# ---- ARCADE 6048-6055 ----
	RECIPES[6048] = func() -> void:  # Pixel Brick
		bricks(10, 8, Color(0.8, 0.3, 0.2), Color(0.3, 0.08, 0.05), 0.08)
		bevel(0.2)
	RECIPES[6049] = func() -> void:  # Pixel Grass
		rect(0, 0, 40, 12, Color(0.35, 0.8, 0.3))
		rect(0, 8, 40, 4, Color(0.28, 0.65, 0.24))
		for x in range(0, 40, 4):
			rect(x, 10 + (x / 4) % 3, 2, 3, Color(0.35, 0.8, 0.3))
		rect(0, 13, 40, 27, Color(0.5, 0.32, 0.2))
		for _i in range(10):
			rect(rng.randi_range(2, 35), rng.randi_range(16, 36), 3, 2, Color(0.42, 0.26, 0.15))
		bevel(0.15)
	RECIPES[6050] = func() -> void:  # Bonus Star
		fill_all(Color(0.85, 0.6, 0.1))
		frame(0, 0, 40, 40, Color(0.5, 0.3, 0.02))
		frame(1, 1, 38, 38, Color(1.0, 0.85, 0.4))
		var star_pts: Array = []
		for i in range(10):
			var a4: float = -PI / 2.0 + TAU * i / 10.0
			var r2: float = 13.0 if i % 2 == 0 else 5.5
			star_pts.append(Vector2(19.5, 21.0) + Vector2.from_angle(a4) * r2)
		for y in range(6, 36):
			for x in range(6, 34):
				var inside: bool = Geometry2D.is_point_in_polygon(Vector2(x, y), PackedVector2Array(star_pts))
				if inside:
					px(x, y, Color(1.0, 0.95, 0.75))
		bevel(0.18)
	RECIPES[6051] = func() -> void:  # Checker
		checker(10, Color(0.92, 0.92, 0.95), Color(0.15, 0.15, 0.2))
		bevel(0.12)
	RECIPES[6052] = func() -> void:  # Pipe Green
		vgrad(Color(0.25, 0.75, 0.25), Color(0.1, 0.45, 0.12))
		for x in range(40):
			var f3: float = 1.0 - absf(x - 19.5) / 26.0
			for y in range(40):
				var c8: Color = getp(x, y)
				px(x, y, Color(c8.r * (0.7 + f3 * 0.6), c8.g * (0.7 + f3 * 0.6), c8.b * (0.7 + f3 * 0.6)))
		rect(0, 0, 40, 5, Color(0.35, 0.9, 0.35))
		rect(0, 35, 40, 5, Color(0.08, 0.35, 0.1))
		bevel(0.15)
	RECIPES[6053] = func() -> void:  # Sky Block
		vgrad(Color(0.45, 0.75, 0.98), Color(0.3, 0.55, 0.9))
		for cl in [[10, 12], [26, 24]]:
			rect(cl[0] - 5, cl[1], 12, 4, Color(1, 1, 1))
			rect(cl[0] - 2, cl[1] - 3, 7, 3, Color(1, 1, 1))
		bevel(0.1)
	RECIPES[6054] = func() -> void:  # Coin Tile
		fill_all(Color(0.2, 0.14, 0.05))
		for cp in [[11.0, 11.0], [29.0, 11.0], [11.0, 29.0], [29.0, 29.0]]:
			for y in range(40):
				for x in range(40):
					var d3: float = Vector2((x - cp[0]) * 1.6, y - cp[1]).length()
					if d3 < 7.0:
						px(x, y, Color(1.0, 0.85, 0.3))
					if d3 < 3.0:
						px(x, y, Color(1.0, 0.95, 0.6))
		bevel(0.16)
	RECIPES[6055] = func() -> void:  # Glitch
		fill_all(Color(0.06, 0.06, 0.1))
		for y in range(0, 40, 3):
			var off2: int = rng.randi_range(-4, 4)
			var c9: Color = [Color(0.9, 0.2, 0.5), Color(0.2, 0.9, 0.9), Color(0.9, 0.9, 0.2), Color(0.3, 0.3, 0.4)][rng.randi_range(0, 3)]
			rect(maxi(0, off2), y, rng.randi_range(12, 40), rng.randi_range(1, 2), c9)
		scanlines(4, Color(0.0, 0.0, 0.0), 0.35)

	# ---- GEMS 6056-6063 ----
	RECIPES[6056] = func() -> void: facet_gem(Color(0.85, 0.1, 0.25), Color(1.0, 0.6, 0.65), Color(0.4, 0.02, 0.1))
	RECIPES[6057] = func() -> void: facet_gem(Color(0.1, 0.75, 0.35), Color(0.65, 1.0, 0.75), Color(0.02, 0.35, 0.14))
	RECIPES[6058] = func() -> void: facet_gem(Color(0.12, 0.3, 0.9), Color(0.6, 0.8, 1.0), Color(0.04, 0.1, 0.45))
	RECIPES[6059] = func() -> void: facet_gem(Color(0.6, 0.25, 0.85), Color(0.85, 0.65, 1.0), Color(0.28, 0.08, 0.45))
	RECIPES[6060] = func() -> void: facet_gem(Color(0.95, 0.7, 0.15), Color(1.0, 0.92, 0.6), Color(0.5, 0.32, 0.04))
	RECIPES[6061] = func() -> void: facet_gem(Color(0.75, 0.85, 0.92), Color(1.0, 1.0, 1.0), Color(0.35, 0.45, 0.55))
	RECIPES[6062] = func() -> void: facet_gem(Color(0.2, 0.14, 0.28), Color(0.5, 0.4, 0.65), Color(0.06, 0.04, 0.1))
	RECIPES[6063] = func() -> void:  # Opal — shifting colors
		facet_gem(Color(0.85, 0.85, 0.9), Color(1.0, 1.0, 1.0), Color(0.5, 0.5, 0.6))
		for y in range(40):
			for x in range(40):
				var c10: Color = getp(x, y)
				var hshift: float = sin(x * 0.3) * 0.5 + sin(y * 0.4) * 0.5
				if c10.get_luminance() > 0.5:
					px(x, y, Color(c10.r + 0.12 * sin(hshift * 3.0), c10.g + 0.12 * sin(hshift * 3.0 + 2.1), c10.b + 0.12 * sin(hshift * 3.0 + 4.2)))

	# ---- SPOOKY 6064-6071 ----
	RECIPES[6064] = func() -> void:  # Pumpkin
		rgrad(Color(1.0, 0.55, 0.1), Color(0.7, 0.3, 0.03), 19.5, 22.0, 26.0)
		for i in range(5):
			var x6: int = 4 + i * 8
			for y in range(4, 38):
				px(x6, y, Color(0.8, 0.4, 0.05))
		rect(17, 1, 6, 5, Color(0.3, 0.5, 0.2))
		for tri in [[11, 14], [26, 14]]:
			for dy in range(5):
				rect(tri[0] - dy / 2, tri[1] + dy, dy + 1, 1, Color(0.15, 0.05, 0.0))
		for x7 in range(10, 30, 4):
			rect(x7, 28 + (x7 / 4) % 2 * 2, 4, 3, Color(0.15, 0.05, 0.0))
		bevel()
	RECIPES[6065] = func() -> void:  # Bone Pile
		vgrad(Color(0.25, 0.22, 0.26), Color(0.12, 0.1, 0.14))
		for _i in range(6):
			var x8: int = rng.randi_range(3, 28)
			var y8: int = rng.randi_range(5, 33)
			var len2: int = rng.randi_range(7, 11)
			rect(x8, y8, len2, 3, Color(0.92, 0.9, 0.82))
			stud(x8, y8 + 1, 2, Color(0.95, 0.93, 0.85))
			stud(x8 + len2, y8 + 1, 2, Color(0.95, 0.93, 0.85))
		bevel()
	RECIPES[6066] = func() -> void:  # Cobweb Stone
		bricks(20, 13, Color(0.3, 0.28, 0.34), Color(0.14, 0.13, 0.17))
		for i in range(5):
			var a5: float = PI * 0.5 * i / 4.0
			for r3 in range(0, 22):
				var p5: Vector2 = Vector2(1, 1) + Vector2(cos(a5), sin(a5)) * r3
				px(int(p5.x), int(p5.y), Color(0.75, 0.75, 0.8))
		for r4 in [7, 13, 19]:
			for t2 in range(20):
				var a6: float = PI * 0.5 * t2 / 19.0
				var p6: Vector2 = Vector2(1, 1) + Vector2(cos(a6), sin(a6)) * r4
				px(int(p6.x), int(p6.y), Color(0.7, 0.7, 0.76))
		bevel()
	RECIPES[6067] = func() -> void:  # Witchbrick
		bricks(13, 10, Color(0.3, 0.16, 0.4), Color(0.12, 0.05, 0.18))
		speckle(12, Color(0.6, 0.3, 0.8))
		glow(30.0, 8.0, 6.0, Color(0.3, 0.9, 0.4), 0.6)
		bevel()
	RECIPES[6068] = func() -> void:  # Tombstone
		vgrad(Color(0.2, 0.24, 0.2), Color(0.1, 0.13, 0.1))
		for y in range(6, 40):
			for x in range(8, 32):
				var top_r: float = Vector2(x - 19.5, maxf(0, 14 - y)).length()
				if y >= 14 or top_r < 11.5:
					px(x, y, Color(0.55, 0.56, 0.6).lerp(Color(0.4, 0.42, 0.46), (y - 6) / 34.0))
		rect(14, 17, 12, 2, Color(0.3, 0.32, 0.36))
		rect(14, 22, 12, 2, Color(0.3, 0.32, 0.36))
		rect(14, 27, 8, 2, Color(0.3, 0.32, 0.36))
		rect(6, 36, 28, 3, Color(0.24, 0.4, 0.2))
		bevel()
	RECIPES[6069] = func() -> void:  # Ghostglow
		vgrad(Color(0.07, 0.09, 0.16), Color(0.03, 0.04, 0.09))
		glow(19.5, 18.0, 14.0, Color(0.5, 0.85, 0.85), 0.9)
		stud(19, 16, 8, Color(0.75, 0.98, 0.95))
		for dx2 in range(-8, 9, 4):
			rect(19 + dx2 - 1, 23, 3, 3 + absi(dx2) / 3, Color(0.72, 0.95, 0.92))
		px(16, 14, Color(0.1, 0.2, 0.25))
		px(23, 14, Color(0.1, 0.2, 0.25))
		bevel(0.08)
	RECIPES[6070] = func() -> void:  # Blood Moon
		vgrad(Color(0.12, 0.03, 0.05), Color(0.05, 0.01, 0.02))
		glow(26.0, 13.0, 15.0, Color(0.6, 0.06, 0.06), 1.1)
		stud(26, 13, 8, Color(0.85, 0.2, 0.15))
		glow(26.0, 13.0, 9.0, Color(0.4, 0.05, 0.02), 0.8)
		speckle(10, Color(0.5, 0.1, 0.1))
		bevel(0.1)
	RECIPES[6071] = func() -> void:  # Coffin Wood
		vgrad(Color(0.32, 0.2, 0.12), Color(0.2, 0.11, 0.06))
		for y in range(0, 40, 8):
			rect(0, y, 40, 1, Color(0.14, 0.07, 0.03))
			for x9 in range(40):
				if (x9 * 7 + y * 13) % 23 == 0:
					px(x9, y + 4, Color(0.42, 0.28, 0.16))
		rect(18, 4, 4, 22, Color(0.75, 0.68, 0.5))
		rect(12, 10, 16, 4, Color(0.75, 0.68, 0.5))
		bevel()

# CURVES II — appended into RECIPES at init via _ribbons()
func _init_ribbons() -> void:
	RECIPES[6080] = func() -> void:  # Voltage
		ribbon(func(sx: int, y: int) -> Color:
			var d: float = absf(y - 19.5)
			var bolt: float = absf(float(y - 20) - sin(sx * 0.9) * 6.0)
			if bolt < 1.6:
				return Color(1.0, 1.0, 0.75)
			if bolt < 3.6:
				return Color(0.95, 0.85, 0.2)
			if d > 15.0:
				return Color(0.1, 0.09, 0.03)
			return Color(0.25, 0.2, 0.05).lerp(Color(0.5, 0.42, 0.08), 1.0 - d / 15.0))
	RECIPES[6081] = func() -> void:  # Rose Vine
		ribbon(func(sx: int, y: int) -> Color:
			var m: float = cyl(y)
			var d2: float = Vector2(sx - 9, y - 14).length()
			if d2 < 3.4:
				return Color(1.0, 0.5, 0.65)
			if d2 < 4.6:
				return Color(0.85, 0.25, 0.45)
			var d3: float = Vector2(sx - 16, y - 27).length()
			if d3 < 2.6:
				return Color(1.0, 0.62, 0.72)
			return Color(0.12, 0.4 * m + 0.15, 0.1))
	RECIPES[6082] = func() -> void:  # Toxic Flow
		ribbon(func(sx: int, y: int) -> Color:
			var d: float = absf(y - 19.5)
			if d > 15.0:
				return Color(0.1, 0.14, 0.05)
			var blob: float = sin(sx * 0.6) * 3.0 + sin(y * 0.8) * 1.5
			if d < 6.0 + blob:
				return Color(0.55, 0.95, 0.15)
			return Color(0.25, 0.5, 0.08).lerp(Color(0.4, 0.75, 0.1), 1.0 - d / 15.0))
	RECIPES[6083] = func() -> void:  # River Run
		ribbon(func(sx: int, y: int) -> Color:
			var m: float = cyl(y)
			var w: float = sin(sx * 0.5 + y * 0.3) * 0.5 + 0.5
			var c: Color = Color(0.15, 0.45, 0.8).lerp(Color(0.45, 0.75, 0.98), w * 0.5)
			if y >= 3 and y <= 6:
				c = Color(0.8, 0.95, 1.0)
			return Color(c.r * (0.6 + m * 0.5), c.g * (0.6 + m * 0.5), c.b * (0.6 + m * 0.5)))
	RECIPES[6084] = func() -> void:  # Chrome
		ribbon(func(sx: int, y: int) -> Color:
			var t: float = y / 39.0
			var c: Color
			if t < 0.28:
				c = Color(0.95, 0.97, 1.0).lerp(Color(0.55, 0.6, 0.7), t / 0.28)
			elif t < 0.52:
				c = Color(0.55, 0.6, 0.7).lerp(Color(0.15, 0.17, 0.22), (t - 0.28) / 0.24)
			elif t < 0.62:
				c = Color(0.9, 0.95, 1.0)
			else:
				c = Color(0.35, 0.4, 0.5).lerp(Color(0.1, 0.12, 0.16), (t - 0.62) / 0.38)
			return c)
	RECIPES[6085] = func() -> void:  # Ember Rope
		ribbon(func(sx: int, y: int) -> Color:
			var m: float = cyl(y)
			var braid: float = sin(y * 0.5 + sx * 0.55) + sin(y * 0.5 - sx * 0.55)
			var base: Color = Color(0.5 * m + 0.2, 0.16 * m + 0.05, 0.02)
			if braid > 0.9:
				return Color(1.0, 0.6, 0.15)
			if braid > 0.3:
				return Color(0.85 * m + 0.15, 0.35 * m, 0.05)
			return base)
	RECIPES[6086] = func() -> void:  # Cloudstream
		ribbon(func(sx: int, y: int) -> Color:
			var d: float = absf(y - 19.5)
			var puff: float = sin(sx * 0.45) * 2.5 + sin(y * 0.7) * 1.2
			if d < 9.0 + puff:
				return Color(1.0, 1.0, 1.0).lerp(Color(0.85, 0.9, 0.99), d / 14.0)
			return Color(0.55, 0.68, 0.92).lerp(Color(0.4, 0.52, 0.8), d / 20.0))
	RECIPES[6087] = func() -> void:  # Royal Ribbon
		ribbon(func(sx: int, y: int) -> Color:
			var m: float = cyl(y)
			if y <= 3 or y >= 36:
				return Color(0.9, 0.75, 0.25)
			if y == 5 or y == 34:
				return Color(1.0, 0.9, 0.5)
			var c: Color = Color(0.15, 0.2, 0.6).lerp(Color(0.3, 0.4, 0.9), m)
			var fl: float = Vector2(sx - 12, absf(y - 19.5)).length()
			if fl < 3.0:
				return Color(0.95, 0.82, 0.35)
			return c)
	RECIPES[6088] = func() -> void:  # Void Trail
		ribbon(func(sx: int, y: int) -> Color:
			var d: float = absf(y - 19.5)
			if d > 16.0:
				return Color(0.02, 0.01, 0.05)
			var rim: Color = Color(0.45, 0.15, 0.75)
			var core: Color = Color(0.08, 0.03, 0.16)
			var c: Color = core.lerp(rim, pow(d / 16.0, 1.6))
			var st: float = Vector2(sx - 10, y - 16).length()
			if st < 1.2:
				return Color(0.9, 0.8, 1.0)
			var st2: float = Vector2(sx - 17, y - 25).length()
			if st2 < 1.0:
				return Color(0.8, 0.7, 1.0)
			return c)
	RECIPES[6089] = func() -> void:  # Sakura Stream
		ribbon(func(sx: int, y: int) -> Color:
			var m: float = cyl(y)
			var base: Color = Color(0.98, 0.8, 0.88).lerp(Color(0.9, 0.55, 0.72), 1.0 - m)
			for p in [[7, 11], [15, 24], [4, 30]]:
				var d4: float = Vector2(sx - p[0], y - p[1]).length()
				if d4 < 2.2:
					return Color(0.98, 0.35, 0.55)
			if y <= 2:
				return Color(1.0, 0.95, 0.97)
			return base)
