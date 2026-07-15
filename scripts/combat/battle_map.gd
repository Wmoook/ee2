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

# Tower climb ladders (standing positions, bottom -> top): the bot walks
# these waypoint by waypoint whenever its goal is high above (scatter pads,
# the lift entrance, a player camping a platform).
const CLIMB_LEFT: Array = [Vector2(568.0, 456.0), Vector2(624.0, 408.0), Vector2(680.0, 390.0)]
const CLIMB_RIGHT: Array = [Vector2(952.0, 456.0), Vector2(912.0, 408.0), Vector2(840.0, 390.0)]
const SUPER_POS: Vector2 = Vector2(768.0, 104.0)  # DOOM RAY drop: crown of the arrow lift — ride up to claim it
# Ability orbs appear at these open-air spots
const ABILITY_SPOTS: Array = [
	Vector2(300.0, 440.0), Vector2(1236.0, 440.0), Vector2(768.0, 300.0),
	Vector2(560.0, 360.0), Vector2(976.0, 360.0), Vector2(200.0, 260.0),
	Vector2(1336.0, 260.0),
]

# Curated respawn spots (tile coords, all in open air above solid ground) on
# both sides of the map — respawns pick randomly among these, never inside a
# block, and never right next to the opponent.
const SPAWN_SPOTS: Array = [
	Vector2(18, 30), Vector2(28, 30), Vector2(35, 27),
	Vector2(77, 30), Vector2(67, 30), Vector2(60, 27),
]


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
	# Mid platforms y=25 (scatter pads live here; lift entry from inner tips).
	# One tile HIGHER than a plain 3-tile hop so the floor beneath has 96px
	# of headroom — a full jump over the spike strips clears the underside by
	# 17px instead of 1px (no more head-bonk-onto-spikes deaths).
	for x in range(40, 46):
		_fg(x, 25, PLATE)
	for x in range(50, 56):
		_fg(x, 25, PLATE)
	_fg(45, 25, CORE)
	_fg(50, 25, CORE)
	# SOLID STAIRCASES fused to the shelf inner ends:
	# shelf (y29, top 464) -> step top (y26, top 416) -> mid (y25, top 400).
	# One standard 48px hop up, then a trivial 16px hop onto the mid — no
	# corner-clip margins, no gaps, no fall-chutes anywhere in the chain.
	for sx in [38, 39]:
		_fg(sx, 26, CORE if sx == 38 else PLATE)
		_fg(sx, 27, PLATE)
		_fg(sx, 28, PLATE)
	_fg(39, 29, PLATE)
	for sx in [56, 57]:
		_fg(sx, 26, CORE if sx == 57 else PLATE)
		_fg(sx, 27, PLATE)
		_fg(sx, 28, PLATE)
	_fg(56, 29, PLATE)
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

	# ── Spike strip: center floor, under the LIFT (160px of open sky above,
	# every hop clears with huge margin, and the shaft + aprons catch any
	# fall from above). ──
	for x in [47, 48]:
		_fg(x, 31, SPIKES)

	# ── Top bridge y=9: dismount balconies around the central lift slot ──
	for x in range(45, 51):
		if x == 47 or x == 48:
			continue  # Lift passes through
		_fg(x, 9, CORE if (x == 45 or x == 50) else PLATE)
	# UP-ARROW LIFT: from just above the mid platforms (y24) through the slot
	# to the rail. Reaching down to y24 makes the shaft a SAFETY NET: any hop
	# or fall into the slot gets caught and lifted — a failed entry can never
	# free-fall down the shaft onto the spikes at its base. The floor below
	# stays freely crossable (jump apex tops out well beneath the arrows).
	for y in range(7, 25):
		_fg(47, y, ARROW_UP)
		_fg(48, y, ARROW_UP)
	# Catch aprons flanking the shaft: anything falling down the side gap
	# columns gets juggled back up instead of dropping onto the spikes below.
	for y in range(23, 25):
		_fg(46, y, ARROW_UP)
		_fg(49, y, ARROW_UP)

	# ── Structural background: lift shaft + support pillars ──
	for y in range(7, 23):
		for x in range(46, 50):
			WorldManager.set_bg_tile(x, y, PLATE + 100)
	for col in [40, 45, 50, 55]:        # Under mid platform tips
		for y in range(26, 32):
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
	# Guns live in the permanent loadout now (slots 2/3) — the only world
	# pickup is the DOOM RAY's 60s materialization
	ws.super_pos = SUPER_POS


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
