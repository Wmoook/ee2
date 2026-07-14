class_name BattleMap
extends RefCounted
## Builds the 1v1 bot arena directly into WorldManager (never touches the
## player's saved world — saving is disabled while battle_mode is active).
## Art: 100% custom generated arena sprites (5005-5010).
##
## LAYOUT PLAN — LONG arena (96x36 tiles = 1536px), symmetric around x=47.5:
##
##   [wall pipe][high shelf]--long slide--[open floor][tower][LIFT][tower][open floor]--slide--[shelf][pipe wall]
##
##   * FLOW LINES: corner quarter-pipe launches you up the wall onto the HIGH
##     SHELF; from there a LONG SLIDE curve carves ~500px down across the
##     midfield to the floor. Pipe up -> slide down = a full skate loop.
##   * TOWERS by the center: shelf (y29) -> mid platform (y26, scatter pad)
##     -> perch (y23). Every hop is exactly 3 tiles (48px) — jump apex ~63px.
##   * CENTER LIFT: up-arrows from PLATFORM height (y22) through the bridge
##     slot to the rail pad. The floor below stays freely crossable — hop in
##     from a mid platform's inner tip. Riding it is fast but exposed.
##   * SPIKE STRIPS only under the mid platforms, placed so no walk-off or
##     bridge dismount can land on them (all landing zones >=1 tile clear).
##   * Every curve END POINT is buried inside solid tiles — no wedge creases.

const W: int = 96
const H: int = 36

const PLATE: int = 5005    # Wall/platform plate (cyan-edged gunmetal)
const CORE: int = 5006     # Amber hazard-striped accent
const FLOOR: int = 5007    # Brushed steel floor plate with cyan seam
const FILL: int = 5008     # Deep dark fill
const ENERGY: int = 5009   # Violet energy block (curves)
const SPIKES: int = 5010   # Plasma spikes (custom hazard, kills on touch)
const ARROW_UP: int = 2

# Standing spots on the mid platforms — waypoints the bot climbs through
# when it wants the rail pad high above (the lift entrance is up there).
const RAIL_VIA: Array = [Vector2(680.0, 402.0), Vector2(840.0, 402.0)]


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

	# ── High catch shelves (pipe-launch reward, slide entry) y=19 ──
	for x in range(3, 10):
		_fg(x, 19, PLATE)
	for x in range(86, 93):
		_fg(x, 19, PLATE)
	_fg(9, 19, CORE)
	_fg(86, 19, CORE)

	# ── Center towers (mirrored): shelf -> mid -> perch, all 48px hops ──
	# Shelves y=29
	for x in range(33, 39):
		_fg(x, 29, PLATE)
	for x in range(57, 63):
		_fg(x, 29, PLATE)
	_fg(38, 29, CORE)
	_fg(57, 29, CORE)
	# Mid platforms y=26 (scatter pads live here; lift entry from inner tips)
	for x in range(40, 46):
		_fg(x, 26, PLATE)
	for x in range(50, 56):
		_fg(x, 26, PLATE)
	_fg(45, 26, CORE)
	_fg(50, 26, CORE)
	# Perches y=23 (cover + sightlines)
	for x in range(34, 38):
		_fg(x, 23, PLATE)
	for x in range(58, 62):
		_fg(x, 23, PLATE)
	_fg(34, 23, CORE)
	_fg(61, 23, CORE)
	# Slide landing ledges y=29: the long slides END buried in these, elevated
	# off the floor — you launch off the lip at speed, and the ground below
	# stays fully passable (48px clearance), so the spawn zone is never sealed.
	for x in range(25, 29):
		_fg(x, 29, PLATE)
	for x in range(67, 71):
		_fg(x, 29, PLATE)
	_fg(28, 29, CORE)
	_fg(67, 29, CORE)

	# ── Spike strips: ONLY under the mid platforms (80px headroom, and all
	# walk-off / dismount landing zones stay >=1 tile clear) ──
	for x in [41, 42, 53, 54]:
		_fg(x, 31, SPIKES)

	# ── Top bridge y=9: dismount balconies around the central lift slot ──
	for x in range(45, 51):
		if x == 47 or x == 48:
			continue  # Lift passes through
		_fg(x, 9, CORE if (x == 45 or x == 50) else PLATE)
	# UP-ARROW LIFT: from platform height (y22) through the slot to the rail.
	# The floor below stays freely crossable.
	for y in range(7, 23):
		_fg(47, y, ARROW_UP)
		_fg(48, y, ARROW_UP)

	# ── Structural background: lift shaft + support pillars ──
	for y in range(7, 23):
		for x in range(46, 50):
			WorldManager.set_bg_tile(x, y, PLATE + 100)
	for col in [40, 45, 50, 55]:        # Under mid platform tips
		for y in range(27, 32):
			WorldManager.set_bg_tile(col, y, PLATE + 100)
	for col in [33, 38, 57, 62]:        # Under shelf tips
		for y in range(30, 32):
			WorldManager.set_bg_tile(col, y, PLATE + 100)

	# ── CURVES (energy art) — every end point buried in solids ──
	# Corner quarter-pipes: wall-buried top, floor-buried tail
	WorldManager.add_polyline(_spline([
		Vector2(18, 320), Vector2(28, 420), Vector2(64, 482), Vector2(140, 502), Vector2(208, 526),
	]), "both", ENERGY)
	WorldManager.add_polyline(_spline([
		Vector2(1518, 320), Vector2(1508, 420), Vector2(1472, 482), Vector2(1396, 502), Vector2(1328, 526),
	]), "both", ENERGY)
	# LONG SLIDES: start buried in the high shelf, carve down across the
	# midfield, end buried in the ELEVATED landing ledge — ride them for big
	# speed and launch off the lip. The floor below stays open.
	WorldManager.add_polyline(_spline([
		Vector2(130, 312), Vector2(240, 360), Vector2(340, 424), Vector2(430, 470),
	]), "both", ENERGY)
	WorldManager.add_polyline(_spline([
		Vector2(1406, 312), Vector2(1296, 360), Vector2(1196, 424), Vector2(1106, 470),
	]), "both", ENERGY)

	# ── Spawns: open floor between pipe tail and the slide's overhead arc ──
	WorldManager.spawn_points.append(Vector2(18, 30))
	WorldManager.spawn_points.append(Vector2(77, 30))

	WorldManager.tile_changed.emit(0, 0, 0)
	WorldManager.free_blocks_changed.emit()
	WorldManager.polylines_changed.emit()
	WorldManager.gravity_zones.zones_changed.emit()


static func add_weapon_pads(ws: WeaponSystem) -> void:
	ws.add_pad(Vector2(352, 494), "blaster")     # Left floor, by the spawn
	ws.add_pad(Vector2(1184, 494), "blaster")    # Right floor, by the spawn
	ws.add_pad(Vector2(680, 398), "scatter")     # Left mid platform (contested)
	ws.add_pad(Vector2(840, 398), "scatter")     # Right mid platform (contested)
	ws.add_pad(Vector2(768, 126), "rail")        # Top of the lift
	ws.super_pos = Vector2(768.0, 494.0)         # DOOM RAY materializes center floor


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
