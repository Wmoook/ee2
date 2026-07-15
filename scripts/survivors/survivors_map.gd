class_name SurvivorsMap
extends RefCounted
## THE DOT DEPTHS (100x56): a classic EE dot cave — the whole void is
## filled with dots (zero gravity, free flight, pure EE dot physics) with
## floating obsidian islands for cover, energy arcs to weave through, and
## a giant summoning circle where the horde pours in. Built in-memory.

const W: int = 100
const H: int = 56

const WALL: int = 5011
const FLOOR_B: int = 5012
const RUNE: int = 5013
const VOID: int = 5014
const ENERGY_B: int = 5015
const DOT: int = 4

const MIN_X: float = 48.0
const MAX_X: float = 1552.0
const MIN_Y: float = 48.0
const MAX_Y: float = 848.0

# Floating islands: [x, y, w, h] in tiles
const ISLANDS: Array = [
	[10, 12, 8, 2], [26, 24, 10, 2], [12, 38, 7, 2],
	[40, 8, 8, 2], [46, 30, 12, 3], [38, 46, 8, 2],
	[62, 16, 9, 2], [70, 38, 8, 2], [84, 10, 7, 2],
	[86, 28, 9, 2], [80, 48, 8, 2], [22, 6, 6, 2],
]


static func build() -> void:
	WorldManager.init_empty_world(W, H)
	WorldManager.free_blocks.clear()
	WorldManager.polylines.clear()
	WorldManager.wedge_pairs.clear()
	WorldManager.curve_colliders.clear()
	WorldManager.lines.clear()
	WorldManager.block_groups.clear()
	WorldManager.gravity_zones.zones.clear()
	WorldManager.spawn_points.clear()

	# ── Shell ──
	for x in range(W):
		_fg(x, 0, WALL)
		_fg(x, 1, WALL)
		_fg(x, H - 1, WALL)
		_fg(x, H - 2, WALL)
	for y in range(H):
		_fg(0, y, WALL)
		_fg(1, y, WALL)
		_fg(W - 2, y, WALL)
		_fg(W - 1, y, WALL)

	# ── Floating islands (cover from spiker shrapnel) ──
	for isl in ISLANDS:
		var ix: int = isl[0]
		var iy: int = isl[1]
		var iw: int = isl[2]
		var ih: int = isl[3]
		for y in range(iy, iy + ih):
			for x in range(ix, ix + iw):
				_fg(x, y, FLOOR_B if y == iy else WALL)
		_fg(ix, iy, RUNE)
		_fg(ix + iw - 1, iy, RUNE)
		for y in range(iy + ih, mini(iy + ih + 2, H - 2)):
			for x in range(ix + 1, ix + iw - 1):
				WorldManager.set_bg_tile(x, y, WALL + 100)

	# ── THE DOT FIELD: every other tile of open void is a dot ──
	for y in range(3, H - 3):
		for x in range(3, W - 3):
			if x % 2 == 0 and y % 2 == 0 and WorldManager.get_tile(x, y) == 0:
				_fg(x, y, DOT)

	# ── Central summoning circle (BG) — where it all pours out ──
	for y in range(20, 37):
		for x in range(42, 59):
			var dx: float = float(x) - 50.0
			var dy: float = float(y) - 28.0
			var d: float = sqrt(dx * dx + dy * dy)
			if d >= 6.0 and d <= 7.4:
				WorldManager.set_bg_tile(x, y, RUNE + 100)

	# ── Energy arcs to weave through ──
	WorldManager.add_polyline(_spline([
		Vector2(170, 200), Vector2(300, 300), Vector2(430, 330), Vector2(560, 280),
	]), "both", ENERGY_B)
	WorldManager.add_polyline(_spline([
		Vector2(1400, 620), Vector2(1280, 540), Vector2(1140, 520), Vector2(1010, 570),
	]), "both", ENERGY_B)

	WorldManager.spawn_points.append(Vector2(50, 28))

	WorldManager.tile_changed.emit(0, 0, 0)
	WorldManager.free_blocks_changed.emit()
	WorldManager.polylines_changed.emit()
	WorldManager.gravity_zones.zones_changed.emit()


static func _fg(x: int, y: int, id: int) -> void:
	if x >= 0 and x < WorldManager.world_width and y >= 0 and y < WorldManager.world_height:
		WorldManager.fg_tiles[y][x] = id


static func _spline(points: Array) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var cp: Array = [points[0] - (points[1] - points[0])]
	cp.append_array(points)
	cp.append(points[-1] + (points[-1] - points[-2]))
	for seg in range(1, cp.size() - 2):
		var p0: Vector2 = cp[seg - 1]
		var p1: Vector2 = cp[seg]
		var p2: Vector2 = cp[seg + 1]
		var p3: Vector2 = cp[seg + 2]
		var steps: int = maxi(4, int(ceil(p1.distance_to(p2))))
		for i in range(steps):
			var t: float = float(i) / float(steps)
			var tt: float = t * t
			var ttt: float = tt * t
			var pos: Vector2 = 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * tt + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * ttt)
			if out.size() == 0 or out[-1].distance_to(pos) > 1.0:
				out.append(pos)
	if out.size() > 0 and out[-1].distance_to(points[-1]) > 0.5:
		out.append(points[-1])
	return out
