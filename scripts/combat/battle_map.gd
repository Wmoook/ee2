class_name BattleMap
extends RefCounted
## Builds the 1v1 bot arena directly into WorldManager (never touches the
## player's saved world — saving is disabled while battle_mode is active).
##
## Art: 100% custom generated arena sprites (5005-5010) — none of the regular
## palette blocks appear here. Curves use the energy block (5009).
##
## Traversability rules baked into the layout:
##   * every platform tier is exactly 3 tiles (48px) above the previous one —
##     jump apex is ~63px, so every hop is comfortable
##   * every curve END POINT is buried inside solid tiles (wall or floor), so
##     the exposed surface is only the smooth arc — no tail creases to wedge in
##   * the corner pockets behind the quarter-pipes are fully sealed dead space
##   * the top bridge (rail gun) is reached by the central UP-ARROW LIFT:
##     hop in from an upper platform or the mound crest and ride the arrows
##     through the bridge slot to the rail pad

const W: int = 64
const H: int = 36

const PLATE: int = 5005    # Wall/platform plate (cyan-edged gunmetal)
const CORE: int = 5006     # Amber hazard-striped accent
const FLOOR: int = 5007    # Brushed steel floor plate with cyan seam
const FILL: int = 5008     # Deep dark fill
const ENERGY: int = 5009   # Violet energy block (curves)
const SPIKES: int = 5010   # Plasma spikes (custom hazard, kills on touch)


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

	# ── Shell (2 thick) ──
	for x in range(W):
		_fg(x, 0, PLATE)
		_fg(x, 1, PLATE)
		_fg(x, H - 1, PLATE)
	for y in range(H):
		_fg(0, y, PLATE)
		_fg(1, y, PLATE)
		_fg(W - 2, y, PLATE)
		_fg(W - 1, y, PLATE)

	# ── Floor: bright plate surface over dark fill ──
	for x in range(2, W - 2):
		_fg(x, 32, FLOOR)
		_fg(x, 33, FILL)
		_fg(x, 34, FILL)

	# ── Plasma spike bed inside the sealed pocket under the mound (visible
	# through the dome — pure set dressing, unreachable) ──
	for x in range(29, 35):
		_fg(x, 31, SPIKES)

	# ── Platform tiers (all 3-tile hops, mirrored) ──
	# Low: y=29
	for x in range(9, 15):
		_fg(x, 29, PLATE)
	for x in range(49, 55):
		_fg(x, 29, PLATE)
	_fg(14, 29, CORE)
	_fg(49, 29, CORE)
	# Mid: y=26
	for x in range(16, 22):
		_fg(x, 26, PLATE)
	for x in range(42, 48):
		_fg(x, 26, PLATE)
	_fg(21, 26, CORE)
	_fg(42, 26, CORE)
	# Upper platforms: y=23, flanking the central lift
	for x in range(22, 28):
		_fg(x, 23, PLATE)
	for x in range(36, 42):
		_fg(x, 23, PLATE)
	_fg(27, 23, CORE)
	_fg(36, 23, CORE)
	# Wall cover ledges (decor/cover, reachable via pipe launch)
	for x in range(4, 8):
		_fg(x, 19, PLATE)
	for x in range(56, 60):
		_fg(x, 19, PLATE)
	# Top bridge: y=9 — the rail gun prize, with a central lift slot
	for x in range(28, 36):
		if x == 31 or x == 32:
			continue  # Lift passes through here
		_fg(x, 9, CORE if (x == 28 or x == 35) else PLATE)
	# UP-ARROW LIFT: two columns from the mound crest, through the bridge
	# slot, up to the rail pad. Hop in from an upper platform (y=23) or ride
	# up from the mound top.
	for y in range(7, 27):
		_fg(31, y, 2)
		_fg(32, y, 2)

	# ── Background depth pattern (custom plate BG) ──
	for y in range(6, 31):
		for x in range(4, W - 4):
			if (x + y) % 7 == 0:
				WorldManager.set_bg_tile(x, y, PLATE + 100)

	# ── Curves (energy block art) — ALL end points buried in solids ──
	# Left quarter-pipe: starts inside the wall, ends under the floor
	WorldManager.add_polyline(_spline([
		Vector2(18, 320), Vector2(28, 420), Vector2(64, 482), Vector2(140, 502), Vector2(208, 526),
	]), "both", ENERGY)
	# Right quarter-pipe (mirror)
	WorldManager.add_polyline(_spline([
		Vector2(1006, 320), Vector2(996, 420), Vector2(960, 482), Vector2(884, 502), Vector2(816, 526),
	]), "both", ENERGY)
	# Center mound under the hole — both ends buried under the floor
	WorldManager.add_polyline(_spline([
		Vector2(380, 526), Vector2(448, 460), Vector2(512, 444), Vector2(576, 460), Vector2(644, 526),
	]), "both", ENERGY)

	# ── Spawns: open floor past the pipe tails, next to the blaster pads ──
	WorldManager.spawn_points.append(Vector2(14, 30))
	WorldManager.spawn_points.append(Vector2(49, 30))

	WorldManager.tile_changed.emit(0, 0, 0)
	WorldManager.free_blocks_changed.emit()
	WorldManager.polylines_changed.emit()
	WorldManager.gravity_zones.zones_changed.emit()


static func add_weapon_pads(ws: WeaponSystem) -> void:
	ws.add_pad(Vector2(248, 494), "blaster")     # Left floor, by the spawn
	ws.add_pad(Vector2(776, 494), "blaster")     # Right floor, by the spawn
	ws.add_pad(Vector2(392, 350), "scatter")     # Left upper platform
	ws.add_pad(Vector2(632, 350), "scatter")     # Right upper platform
	ws.add_pad(Vector2(512, 126), "rail")        # Top of the arrow lift


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
