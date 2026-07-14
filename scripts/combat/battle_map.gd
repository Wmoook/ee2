class_name BattleMap
extends RefCounted
## Builds the 1v1 bot arena directly into WorldManager (never touches the
## player's saved world — saving is disabled while battle_mode is active).
##
## Layout (64x36 tiles): symmetric arena around a central BLACK HOLE.
## Quarter-pipe curves in both corners, a curved mound under the hole,
## three platform tiers with hazard-striped edges, side towers with slopes,
## and four weapon pads (blaster low, scatter mid, rail on the top bridge).

const W: int = 64
const H: int = 36

const PLATE: int = 5005     # Arena plate (cyan-edged gunmetal, generated art)
const CORE: int = 5006      # Hazard core (amber warning stripes, generated art)
const STONE_A: int = 5000
const STONE_B: int = 5001
const CURVE_BLOCK: int = 5002
const SPIKE: int = 368      # Classic hazard (kills on touch)


static func build() -> void:
	# ── Full world reset (in-memory only) ──
	WorldManager.init_empty_world(W, H)
	WorldManager.free_blocks.clear()
	WorldManager.polylines.clear()
	WorldManager.wedge_pairs.clear()
	WorldManager.curve_colliders.clear()
	WorldManager.lines.clear()
	WorldManager.block_groups.clear()
	WorldManager.gravity_zones.zones.clear()
	WorldManager.spawn_points.clear()

	# ── Shell: replace the plain border with arena plate ──
	for x in range(W):
		_fg(x, 0, PLATE)
		_fg(x, 1, PLATE)
		_fg(x, H - 1, PLATE)
	for y in range(H):
		_fg(0, y, PLATE)
		_fg(1, y, PLATE)
		_fg(W - 2, y, PLATE)
		_fg(W - 1, y, PLATE)

	# ── Floor (y=32 surface, filled below) with plate/stone detail ──
	for x in range(2, W - 2):
		_fg(x, 32, PLATE if (x % 4 != 3) else STONE_B)
		_fg(x, 33, STONE_A)
		_fg(x, 34, STONE_A)
		_fg(x, 35, PLATE)

	# ── Central spike trench under the hole (punishes falling out of orbit) ──
	for x in range(29, 35):
		WorldManager.fg_tiles[31][x] = SPIKE

	# ── Mid platforms flanking the hole (hazard-striped inner tips) ──
	for x in range(16, 25):
		_fg(x, 20, CORE if x >= 23 else PLATE)
	for x in range(39, 48):
		_fg(x, 20, CORE if x <= 40 else PLATE)

	# ── Low side platforms ──
	for x in range(8, 15):
		_fg(x, 26, STONE_B)
	for x in range(49, 56):
		_fg(x, 26, STONE_B)

	# ── High perches ──
	for x in range(12, 17):
		_fg(x, 13, STONE_A)
	for x in range(47, 52):
		_fg(x, 13, STONE_A)

	# ── Top bridge (rail weapon lives here — worth the climb) ──
	for x in range(27, 37):
		_fg(x, 8, CORE if (x == 27 or x == 36) else PLATE)

	# ── Background depth behind the arena center (dim plate pattern) ──
	for y in range(6, 31):
		for x in range(4, W - 4):
			if (x + y) % 7 == 0:
				WorldManager.set_bg_tile(x, y, PLATE + 100)

	# ── Curves: corner quarter-pipes + a mound under the black hole ──
	WorldManager.add_polyline(_spline([
		Vector2(40, 340), Vector2(52, 420), Vector2(96, 480), Vector2(180, 505),
	]), "both", CURVE_BLOCK)
	WorldManager.add_polyline(_spline([
		Vector2(984, 340), Vector2(972, 420), Vector2(928, 480), Vector2(844, 505),
	]), "both", CURVE_BLOCK)
	WorldManager.add_polyline(_spline([
		Vector2(400, 510), Vector2(452, 468), Vector2(512, 452), Vector2(572, 468), Vector2(624, 510),
	]), "both", CURVE_BLOCK)

	# ── THE BLACK HOLE ──
	WorldManager.gravity_zones.add_zone(Vector2(512, 250), 128.0, 2.4, 10.0)

	# ── Spawns: opposite corners of the floor ──
	WorldManager.spawn_points.append(Vector2(4, 30))
	WorldManager.spawn_points.append(Vector2(59, 30))

	WorldManager.tile_changed.emit(0, 0, 0)
	WorldManager.free_blocks_changed.emit()
	WorldManager.polylines_changed.emit()
	WorldManager.gravity_zones.zones_changed.emit()


static func add_weapon_pads(ws: WeaponSystem) -> void:
	ws.add_pad(Vector2(248, 494), "blaster")     # Left floor
	ws.add_pad(Vector2(776, 494), "blaster")     # Right floor
	ws.add_pad(Vector2(328, 302), "scatter")     # Left mid platform
	ws.add_pad(Vector2(696, 302), "scatter")     # Right mid platform
	ws.add_pad(Vector2(512, 110), "rail")        # Top bridge, above the hole


static func _fg(x: int, y: int, id: int) -> void:
	if x >= 0 and x < WorldManager.world_width and y >= 0 and y < WorldManager.world_height:
		WorldManager.fg_tiles[y][x] = id


static func _spline(points: Array) -> PackedVector2Array:
	## Catmull-Rom through the control points, sampled at ~1px (same as the
	## in-game curve tool output).
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
