class_name GravityMode
extends Node2D
## GRAVITY sandbox: FULLY destructible arena. Any block with air beneath
## falls as tumbling debris and re-stacks where it lands; running into
## blocks knocks them flying with your momentum, so towers topple and
## collapses cascade. Offline test mode — own file per design rules.

const GROUND_Y: int = 36              # rows >= this are indestructible floor
const SCAN_DT: float = 0.07           # support-scan cadence (cascade speed)
const KNOCK_SPEED: float = 1.0        # min |EE speed| to plow through blocks
const MAX_DEBRIS: int = 900
const G_PX: float = 1150.0            # debris gravity px/s^2
const DEB_R: float = 7.6              # debris collision radius (blocks NEVER overlap)
const REST_SPEED: float = 34.0        # slower than this + supported = comes to rest
const TERMINAL: float = 760.0

## attached=true: BLOCK GRAVITY toggle in a normal world — everything the
## player built obeys gravity (curves crumble into their component tiles).
## attached=false: the standalone GRAVITY arena mode.
var attached: bool = false
var ground_y: int = GROUND_Y
var _debris: Array = []               # {pos, vel, rot, rv, id, bn (bounce count)}
var _scan_accum: float = 0.0
var _player: Node = null
var _renderer: Node2D = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func build_map() -> void:
	var W: int = 110
	var H: int = 42
	WorldManager.init_empty_world(W, H)
	# Solid ground slab
	for x in range(1, W - 1):
		for y in range(GROUND_Y, H - 1):
			WorldManager.set_fg_tile(x, y, 5000)
	# Towers of varying heights and blocks
	var tower_ids: Array = [6004, 6012, 6020, 6033, 6041]
	var tx: int = 14
	for t in range(5):
		var h: int = 8 + t * 3
		var wdt: int = 2 if t % 2 == 0 else 3
		for cx in range(tx, tx + wdt):
			for cy in range(GROUND_Y - h, GROUND_Y):
				WorldManager.set_fg_tile(cx, cy, tower_ids[t])
		tx += wdt + 6
	# Pyramid
	var px: int = 62
	for row in range(9):
		for cx in range(px + row, px + 18 - row):
			WorldManager.set_fg_tile(cx, GROUND_Y - 1 - row, 6008)
	# Staircase fortress (every column grounded — stable until plowed)
	var ax: int = 86
	for stp in range(10):
		for cy in range(GROUND_Y - 3 - stp, GROUND_Y):
			WorldManager.set_fg_tile(ax + stp, cy, 6051)
	# Tall thin spire near spawn to topple immediately
	for cy in range(GROUND_Y - 14, GROUND_Y):
		WorldManager.set_fg_tile(9, cy, 6060)
	WorldManager.spawn_points = [Vector2(4, GROUND_Y - 2)]
	WorldManager.tile_changed.emit(0, 0, 0)

func _ready() -> void:
	z_index = 3
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	if attached:
		ground_y = WorldManager.world_height - 1
		_crumble_curves_and_frees()
		return
	var lay: CanvasLayer = CanvasLayer.new()
	var lbl: Label = Label.new()
	lbl.text = "GRAVITY SANDBOX — plow through the towers! Unsupported blocks FALL. ESC = menu"
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	lbl.position.y = 8
	lay.add_child(lbl)
	add_child(lay)

func _exit_tree() -> void:
	# Toggle OFF mid-collapse: nothing vanishes — airborne debris comes to
	# rest instantly as rubble free blocks
	for d in _debris:
		WorldManager.free_blocks.append({"pos": (d.pos as Vector2) - Vector2(8, 8),
			"id": d.id, "rotation": rad_to_deg(round(d.rot / (PI / 12.0)) * (PI / 12.0)), "rubble": true,
			"jam": int(d.get("jam", 0))})
	if _debris.size() > 0:
		WorldManager.free_blocks_changed.emit()
	_debris.clear()

func _crumble_curves_and_frees() -> void:
	## BLOCK GRAVITY ON: every curve becomes ONE rigid falling object (its
	## whole ribbon + end caps drop together and land intact); placed free
	## blocks go dynamic as debris. Caps ride their curve.
	var claimed: Dictionary = {}
	for poly in WorldManager.polylines:
		poly["gm_vel"] = 0.001  # support check decides whether it actually falls
		var caps: Array = []
		if not poly.get("collision_only", false):
			var pts: PackedVector2Array = poly.points
			if pts.size() >= 2:
				for fi in range(WorldManager.free_blocks.size()):
					if claimed.has(fi):
						continue
					var fb: Dictionary = WorldManager.free_blocks[fi]
					if not fb.get("is_cap", false):
						continue
					var fc: Vector2 = (fb.pos as Vector2) + Vector2(8, 8)
					if fc.distance_to(pts[0]) < 22.0 or fc.distance_to(pts[pts.size() - 1]) < 22.0:
						claimed[fi] = true
						caps.append(fb)
		poly["gm_caps"] = caps
	# Non-cap free blocks become debris
	var keep: Array = []
	for fi in range(WorldManager.free_blocks.size()):
		var fb: Dictionary = WorldManager.free_blocks[fi]
		if claimed.has(fi) or fb.get("is_cap", false) or fb.get("curve_visual", false) or fb.get("curve_collision", false):
			keep.append(fb)
			continue
		if _debris.size() < MAX_DEBRIS:
			_debris.append({"pos": (fb.pos as Vector2) + Vector2(8, 8), "vel": Vector2(0, -20),
				"rot": deg_to_rad(float(fb.get("rotation", 0.0))), "rv": _rng.randf_range(-2.0, 2.0),
				"id": fb.id, "bn": 0})
		else:
			keep.append(fb)
	WorldManager.free_blocks = keep
	WorldManager.free_blocks_changed.emit()

func _family(a: Dictionary, b: Dictionary) -> bool:
	# Same curve's render parent / split halves share endpoints
	var ap: PackedVector2Array = a.points
	var bp: PackedVector2Array = b.points
	if ap.size() < 2 or bp.size() < 2:
		return false
	for e0 in [ap[0], ap[ap.size() - 1]]:
		for e1 in [bp[0], bp[bp.size() - 1]]:
			if e0.distance_to(e1) < 1.5:
				return true
	return false

func _curve_room(poly: Dictionary, max_probe: float) -> float:
	## Vertical room beneath the curve before it touches ground/tiles/another
	## resting curve. Sampled along the ribbon.
	var pts: PackedVector2Array = poly.points
	var stepn: int = maxi(1, pts.size() / 40)
	var room: float = max_probe
	var probe_cells: int = 1 + int(ceil(max_probe / 16.0))
	for i in range(0, pts.size(), stepn):
		var pt: Vector2 = pts[i]
		var bot: float = pt.y + 8.0
		var tx: int = int(floor(pt.x / 16.0))
		var ty0: int = int(floor(bot / 16.0))
		for ty in range(ty0, ty0 + probe_cells + 1):
			if ty >= WorldManager.world_height - 1 or WorldManager.is_solid_at(tx, ty):
				room = minf(room, maxf(float(ty) * 16.0 - bot, 0.0))
				break
	for op in WorldManager.polylines:
		if op == poly or op.get("collision_only", false):
			continue
		if op.has("gm_vel") and float(op.gm_vel) > 0.0:
			continue  # still falling — not support
		if _family(op, poly):
			continue
		if op.bbox_max.x < poly.bbox_min.x or op.bbox_min.x > poly.bbox_max.x:
			continue
		var ops: PackedVector2Array = op.points
		var ostep: int = maxi(1, ops.size() / 60)
		for i in range(0, pts.size(), stepn):
			var pt: Vector2 = pts[i]
			for j in range(0, ops.size(), ostep):
				var q: Vector2 = ops[j]
				if absf(q.x - pt.x) < 12.0 and q.y > pt.y:
					room = minf(room, maxf(q.y - pt.y - 16.7, 0.0))
	return room

func _shift_poly(poly: Dictionary, dy: float) -> void:
	var off: Vector2 = Vector2(0, dy)
	var pts: PackedVector2Array = poly.points
	for i in range(pts.size()):
		pts[i] += off
	poly["points"] = pts
	for key in ["render_top", "render_bot"]:
		if poly.has(key):
			var arr: PackedVector2Array = poly[key]
			for i in range(arr.size()):
				arr[i] += off
			poly[key] = arr
	poly["bbox_min"] = (poly.bbox_min as Vector2) + off
	poly["bbox_max"] = (poly.bbox_max as Vector2) + off
	poly["mesh_off"] = poly.get("mesh_off", Vector2.ZERO) + off
	for fb in poly.get("gm_caps", []):
		fb["pos"] = (fb.pos as Vector2) + off

func _step_curves(delta: float) -> void:
	var any_fall: bool = false
	var landed_now: bool = false
	for poly in WorldManager.polylines:
		if not poly.has("gm_vel"):
			continue
		if (poly.points as PackedVector2Array).size() < 2:
			continue
		var v: float = float(poly.gm_vel)
		if v <= 0.0:
			# Resting — does it still have support? (knock its perch away!)
			if _curve_room(poly, 4.0) >= 3.0:
				poly["gm_vel"] = 0.001
			continue
		v = minf(v + G_PX * delta, TERMINAL)
		var want: float = v * delta
		var room: float = _curve_room(poly, want + 2.0)
		var drop: float = minf(want, room)
		if drop > 0.0:
			_shift_poly(poly, drop)
			any_fall = true
		if room <= want:
			poly["gm_vel"] = 0.0
			landed_now = true
		else:
			poly["gm_vel"] = v
	if landed_now:
		WorldManager.build_curve_colliders()
	if any_fall:
		WorldManager.polylines_changed.emit()
		WorldManager.free_blocks_changed.emit()

func _rubble_support_scan() -> void:
	## Rubble whose perch fell away must fall too (probe BELOW its own
	## rotated body — 12.5 > the 11.4 diagonal — so it can never
	## "stand on itself" and float)
	var changed: bool = false
	var ri: int = WorldManager.free_blocks.size() - 1
	while ri >= 0:
		var fb: Dictionary = WorldManager.free_blocks[ri]
		if not fb.get("rubble", false):
			ri -= 1
			continue
		var fc: Vector2 = (fb.pos as Vector2) + Vector2(8, 8)
		var sup: bool = false
		var bty: int = int(floor((fc.y + 12.5) / 16.0))
		if bty >= ground_y or WorldManager.is_solid_at(int(floor(fc.x / 16.0)), bty):
			sup = true
		var slide_vx: float = _rng.randf_range(-10.0, 10.0)
		if not sup:
			# A block stays put if a support sits reasonably CENTERED under it,
			# or if it is NESTED in the pocket between two supports. A single
			# offset corner-contact topples it off sideways (angle of repose —
			# no impossible balanced spires).
			var cnt: int = 0
			var walls: int = 0
			var centered: bool = false
			var one_dx: float = 0.0
			for nb in WorldManager.fb_near(fc.x - 8.0, fc.y - 8.0, 24.0):
				if nb == fb or not (nb.get("rubble", false) or nb.get("is_cap", false)):
					continue
				var ncc: Vector2 = (nb.pos as Vector2) + Vector2(8, 8)
				var dxx: float = ncc.x - fc.x
				var dyy: float = ncc.y - fc.y
				if dyy > 3.0 and dyy < 15.5 and absf(dxx) < 13.5:
					cnt += 1
					one_dx = dxx
					# Only a SQUARE-SET support can hold a block alone — a
					# tilted block's point balances nothing (diamond columns
					# collapse); pockets (cnt>=2) still hold anything
					var srot: float = absf(fposmod(float(nb.get("rotation", 0.0)), 90.0))
					var square_sup: bool = srot < 10.0 or srot > 80.0
					if absf(dxx) <= 6.0 and square_sup:
						centered = true
				elif absf(dyy) <= 3.0 and absf(dxx) >= 11.0 and absf(dxx) <= 17.0:
					walls += 1  # wedged laterally between neighbors
			if centered or cnt >= 2 or (cnt >= 1 and walls >= 1):
				sup = true
			elif cnt == 1:
				slide_vx = 55.0 * (1.0 if one_dx <= 0.0 else -1.0) + _rng.randf_range(-10.0, 10.0)
			# Jammed: a block toppled twice settles for good (granular
			# systems jam — also guarantees the sim converges, no churn)
			if not sup and int(fb.get("jam", 0)) >= 2:
				sup = true
		if not sup and _debris.size() < MAX_DEBRIS:
			WorldManager.free_blocks.remove_at(ri)
			_debris.append({"pos": fc, "vel": Vector2(slide_vx, 0.0),
				"rot": deg_to_rad(float(fb.get("rotation", 0.0))), "rv": _rng.randf_range(-2.0, 2.0),
				"id": fb.id, "bn": 1, "jam": int(fb.get("jam", 0)) + 1})
			changed = true
		ri -= 1
	if changed:
		WorldManager.free_blocks_changed.emit()

func _find_player() -> Node:
	for ch in get_parent().get_children():
		if ch.get("is_local") == true and ch.get("physics") != null:
			return ch
	return null

func _is_static(cx: int, cy: int) -> bool:
	if cy >= ground_y:
		return true
	if cx <= 0 or cx >= WorldManager.world_width - 1 or cy <= 0:
		return true
	return WorldManager.get_tile(cx, cy) == 9  # border art

func _loosen(cx: int, cy: int, vel: Vector2) -> void:
	var id: int = WorldManager.get_tile(cx, cy)
	if id == 0 or _is_static(cx, cy):
		return
	if _debris.size() >= MAX_DEBRIS:
		return
	WorldManager.set_fg_tile(cx, cy, 0)
	_debris.append({"pos": Vector2(cx * 16 + 8, cy * 16 + 8), "vel": vel,
		"rot": 0.0, "rv": _rng.randf_range(-3.5, 3.5), "id": id, "bn": 0})

func _support_scan() -> void:
	# Bottom-up so a whole hanging column releases in one scan (cascade).
	# Released blocks TOPPLE toward their open side, and the higher a block
	# sits in the released column the harder it is flung — a tower arcs
	# sideways like a falling tree instead of dropping in formation.
	var col_n: Dictionary = {}  # cx -> how many released below (this scan)
	for cy in range(ground_y - 1, 1, -1):
		for cx in range(1, WorldManager.world_width - 1):
			if WorldManager.get_tile(cx, cy) == 0 or _is_static(cx, cy):
				continue
			if WorldManager.get_tile(cx, cy + 1) == 0 and cy + 1 < ground_y:
				var left_open: bool = WorldManager.get_tile(cx - 1, cy) == 0
				var right_open: bool = WorldManager.get_tile(cx + 1, cy) == 0
				var tip: float
				if left_open and not right_open:
					tip = -1.0
				elif right_open and not left_open:
					tip = 1.0
				else:
					tip = 1.0 if _rng.randf() < 0.5 else -1.0
				var n: int = col_n.get(cx, 0)
				col_n[cx] = n + 1
				# Gentle LEAN, growing a little with height (capped): a tower
				# tips and crumbles — support loss never LAUNCHES blocks
				var vx: float = tip * (8.0 + minf(float(n) * 4.0, 42.0) + _rng.randf_range(0.0, 10.0))
				_loosen(cx, cy, Vector2(vx, _rng.randf_range(-20.0, 0.0)))

func _knock_from_player(_delta: float) -> void:
	if _player == null or _player.get("physics") == null:
		return
	var ph = _player.physics
	var sx: float = ph._speedX
	var sy: float = ph._speedY
	var bx: float = ph.x
	var by: float = ph.y
	var rows: Array = [int(floor(by / 16.0)), int(floor((by + 15.0) / 16.0))]
	# Horizontal plow: the column just ahead of the leading edge
	if absf(sx) > KNOCK_SPEED:
		var lead_x: float = bx + 18.0 if sx > 0.0 else bx - 3.0
		var cx: int = int(floor(lead_x / 16.0))
		for cy in rows:
			if WorldManager.get_tile(cx, cy) != 0 and not _is_static(cx, cy):
				_loosen(cx, cy, Vector2(sx * 34.0, minf(sy * 20.0, 0.0) - 90.0))
				if not ph.is_god_mode:
					ph._speedX *= 0.88  # impact costs a little momentum (not as a god)
	# Plow through resting RUBBLE free blocks the same way
	if absf(sx) > KNOCK_SPEED or absf(sy) > KNOCK_SPEED:
		var kicked: Array = []
		for fb in WorldManager.fb_near(bx, by, 26.0):
			if fb.get("rubble", false):
				var fc: Vector2 = (fb.pos as Vector2) + Vector2(8, 8)
				if fc.distance_to(Vector2(bx + 8.0, by + 8.0)) < 24.0:
					kicked.append(fb)
		for fb in kicked:
			WorldManager.free_blocks.erase(fb)
			_debris.append({"pos": (fb.pos as Vector2) + Vector2(8, 8),
				"vel": Vector2(sx * 34.0, minf(sy * 26.0, 0.0) - 110.0),
				"rot": deg_to_rad(float(fb.get("rotation", 0.0))),
				"rv": _rng.randf_range(-5.0, 5.0), "id": fb.id, "bn": 0})
		if kicked.size() > 0:
			WorldManager.free_blocks_changed.emit()
	# Head bonk: knock the ceiling block when jumping up into it
	if sy < -KNOCK_SPEED:
		var cyu: int = int(floor((by - 3.0) / 16.0))
		for cxx in [int(floor(bx / 16.0)), int(floor((bx + 15.0) / 16.0))]:
			if WorldManager.get_tile(cxx, cyu) != 0 and not _is_static(cxx, cyu):
				_loosen(cxx, cyu, Vector2(_rng.randf_range(-40.0, 40.0), sy * 26.0))

func _step_debris(delta: float) -> void:
	## Granular sim: debris collides with OTHER debris (spatial hash + two
	## relaxation passes), with resting rubble piles, tiles, walls, ground
	## and the player. Blocks NEVER overlap — mid-air or landed — and they
	## come to rest exactly where they physically stop (no teleport stacking).
	var n: int = _debris.size()
	if n == 0:
		return
	var pc: Vector2 = Vector2.INF
	var pvel: Vector2 = Vector2.ZERO
	if _player != null and _player.get("physics") != null:
		pc = Vector2(_player.physics.x + 8.0, _player.physics.y + 8.0)
		pvel = Vector2(_player.physics._speedX, _player.physics._speedY) * 100.0
	# 1) integrate
	for d in _debris:
		var vel: Vector2 = d.vel
		vel.y = minf(vel.y + G_PX * delta, TERMINAL)
		vel.x *= pow(0.5, delta)
		d.vel = vel
		d.pos = (d.pos as Vector2) + vel * delta
		d.rot = float(d.rot) + float(d.rv) * delta
	# 2) debris-vs-debris: positional relaxation + inelastic impulse
	var hgrid: Dictionary = {}
	for i in range(n):
		var cp: Vector2 = _debris[i].pos
		var key: Vector2i = Vector2i(int(floor(cp.x / 16.0)), int(floor(cp.y / 16.0)))
		if hgrid.has(key):
			hgrid[key].append(i)
		else:
			hgrid[key] = [i]
	for _pass in range(2):
		for i in range(n):
			var di: Dictionary = _debris[i]
			var ci: Vector2 = di.pos
			var kx: int = int(floor(ci.x / 16.0))
			var ky: int = int(floor(ci.y / 16.0))
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					var cell = hgrid.get(Vector2i(kx + ox, ky + oy))
					if cell == null:
						continue
					for j in cell:
						if j <= i:
							continue
						var dj: Dictionary = _debris[j]
						var dvec: Vector2 = (dj.pos as Vector2) - ci
						var dist: float = dvec.length()
						if dist >= DEB_R * 2.0 or dist < 0.001:
							continue
						var nrm: Vector2 = dvec / dist
						var push: float = (DEB_R * 2.0 - dist) * 0.5
						di.pos = (di.pos as Vector2) - nrm * push
						dj.pos = (dj.pos as Vector2) + nrm * push
						ci = di.pos
						var rel: float = ((dj.vel as Vector2) - (di.vel as Vector2)).dot(nrm)
						if rel < 0.0:
							var imp: float = -rel * 0.55
							di.vel = (di.vel as Vector2) - nrm * imp
							dj.vel = (dj.vel as Vector2) + nrm * imp
	# 3) statics, player, rest
	var rested: bool = false
	var i2: int = n - 1
	while i2 >= 0:
		var d: Dictionary = _debris[i2]
		var pos: Vector2 = d.pos
		var vel: Vector2 = d.vel
		var supported: bool = false
		# player: solid ball — debris deflects off, never through
		if pc.x != INF:
			var away: Vector2 = pos - pc
			var adist: float = away.length()
			if adist < 16.2:
				away = away.normalized() if adist > 0.01 else Vector2(0, -1)
				pos = pc + away * 16.2
				var relp: Vector2 = vel - pvel
				var into: float = relp.dot(-away)
				if into > 0.0:
					vel += away * (into * 1.1) + pvel * 0.2
					d.rv = _rng.randf_range(-5.0, 5.0)
		# resting rubble & caps: static circles — land ON piles, never inside
		for nb in WorldManager.fb_near(pos.x - 8.0, pos.y - 8.0, 24.0):
			if not (nb.get("rubble", false) or nb.get("is_cap", false)):
				continue
			var nc: Vector2 = (nb.pos as Vector2) + Vector2(8, 8)
			var dv: Vector2 = pos - nc
			var dd: float = dv.length()
			if dd >= 15.4 or dd < 0.001:
				continue
			var nn: Vector2 = dv / dd
			pos = nc + nn * 15.4
			var into2: float = vel.dot(-nn)
			if into2 > 0.0:
				vel += nn * (into2 * 1.15)
			if nn.y < -0.5:
				supported = true
		# side walls (grid tiles)
		if vel.x != 0.0:
			var scx: int = int(floor((pos.x + (DEB_R if vel.x > 0.0 else -DEB_R)) / 16.0))
			var scy: int = int(floor(pos.y / 16.0))
			if WorldManager.is_solid_at(scx, scy):
				pos.x = float(scx) * 16.0 + (16.0 + DEB_R if vel.x < 0.0 else -DEB_R)
				vel.x = 0.0
		# ground / tiles below: bounce hard hits, otherwise stand
		var bcx: int = clampi(int(floor(pos.x / 16.0)), 1, WorldManager.world_width - 2)
		var bty: int = int(floor((pos.y + DEB_R) / 16.0))
		if bty >= ground_y or WorldManager.is_solid_at(bcx, bty):
			var top: float = float(bty) * 16.0
			if pos.y + DEB_R > top and vel.y > 0.0:
				pos.y = top - DEB_R
				if vel.y > 240.0 and int(d.get("bn", 0)) < 2:
					d.bn = int(d.get("bn", 0)) + 1
					vel.y = -vel.y * 0.36
					vel.x += _rng.randf_range(-60.0, 60.0)
					d.rv = _rng.randf_range(-6.0, 6.0)
				else:
					vel.y = 0.0
					vel.x *= 0.55
					supported = true
		# rest: supported and slow — become rubble EXACTLY here
		if supported and vel.length() < REST_SPEED:
			if pc.x != INF and pos.distance_to(pc) < 18.0:
				vel.x = 110.0 * (1.0 if pos.x >= pc.x else -1.0)
				vel.y = -70.0
			else:
				var rr: float = round(float(d.rot) / (PI / 12.0)) * (PI / 12.0)
				var rx: float = clampf(pos.x, 16.0 + DEB_R, float(WorldManager.world_width - 1) * 16.0 - DEB_R)
				WorldManager.free_blocks.append({"pos": Vector2(rx - 8.0, pos.y - 8.0),
					"id": d.id, "rotation": rad_to_deg(rr), "rubble": true,
					"jam": int(d.get("jam", 0))})
				rested = true
				_debris.remove_at(i2)
				i2 -= 1
				continue
		d.pos = pos
		d.vel = vel
		i2 -= 1
	if rested:
		WorldManager.free_blocks_changed.emit()

func _process(delta: float) -> void:
	if _player == null:
		_player = _find_player()
	if _renderer == null:
		_renderer = get_parent().get("renderer")
	_knock_from_player(delta)
	if attached:
		_step_curves(delta)
	_scan_accum += delta
	if _scan_accum >= SCAN_DT:
		_scan_accum = 0.0
		_support_scan()
		_rubble_support_scan()
	_step_debris(delta)
	if _debris.size() > 0 or true:
		queue_redraw()

func _draw() -> void:
	if _renderer == null:
		return
	for d in _debris:
		draw_set_transform(d.pos, d.rot, Vector2.ONE)
		_renderer.draw_block_at(self, Rect2(-8, -8, 16, 16), d.id)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
