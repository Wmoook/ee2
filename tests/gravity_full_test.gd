extends Node
## FULL gravity invariant test. Drives GravityMode with a fixed timestep
## through settle -> tower knock-down -> pile kicking -> freeze, asserting
## at every checkpoint:
##   I1 NO OVERLAP  (every rubble/debris pair separated by real square extents)
##   I2 NO FLOATERS (every resting block has ground/tile/contact support)
##   I3 CONVERGENCE (all debris comes to rest; resting world stops moving)
##   I4 MASS        (movable blocks are never created or destroyed)

const DT: float = 1.0 / 120.0
var grav: GravityMode
var fails: int = 0
var initial_mass: int = 0

func _tile_solid(tx: int, ty: int) -> bool:
	return WorldManager.is_solid_at(tx, ty)

func _movable_grid() -> int:
	var n: int = 0
	for y in range(1, WorldManager.world_height - 1):
		for x in range(1, WorldManager.world_width - 1):
			var t: int = WorldManager.get_tile(x, y)
			if t != 0 and t != 9:
				n += 1
	return n

func _mass() -> int:
	var n: int = _movable_grid()
	for fb in WorldManager.free_blocks:
		if fb.get("rubble", false):
			n += 1
	return n + grav._debris.size()

func _all_bodies() -> Array:
	# [pos: Vector2, rot: float(rad)]
	var out: Array = []
	for fb in WorldManager.free_blocks:
		if fb.get("rubble", false):
			out.append([(fb.pos as Vector2) + Vector2(8, 8), deg_to_rad(float(fb.get("rotation", 0.0)))])
	for d in grav._debris:
		out.append([d.pos, float(d.rot)])
	return out

func _sat_pen(pa: Vector2, ra: float, pb: Vector2, rb: float) -> float:
	## EXACT penetration depth of two 16x16 rotated squares via SAT
	## (0 = separated). The sim itself separates conservatively along the
	## center axis, which is always >= this.
	var min_pen: float = 1e9
	for ang in [ra, ra + PI / 2.0, rb, rb + PI / 2.0]:
		var ax: Vector2 = Vector2(cos(ang), sin(ang))
		var da: float = absf((pb - pa).dot(ax))
		var pen: float = GravityMode._sq_ext(ra, ang) + GravityMode._sq_ext(rb, ang) - da
		if pen <= 0.0:
			return 0.0
		min_pen = minf(min_pen, pen)
	return min_pen

func _check_overlap(tag: String) -> void:
	var bodies: Array = _all_bodies()
	for i in range(bodies.size()):
		for j in range(i + 1, bodies.size()):
			var dv: Vector2 = (bodies[j][0] as Vector2) - (bodies[i][0] as Vector2)
			if dv.length() >= 23.0:
				continue
			var pen: float = _sat_pen(bodies[i][0], bodies[i][1], bodies[j][0], bodies[j][1])
			if pen > 1.0:
				fails += 1
				print("FTEST %s OVERLAP: (%.1f,%.1f)r%.0f vs (%.1f,%.1f)r%.0f pen=%.2f" % [tag,
					bodies[i][0].x, bodies[i][0].y, rad_to_deg(bodies[i][1]),
					bodies[j][0].x, bodies[j][0].y, rad_to_deg(bodies[j][1]), pen])

func _check_floaters(tag: String) -> void:
	for fb in WorldManager.free_blocks:
		if not fb.get("rubble", false):
			continue
		var fc: Vector2 = (fb.pos as Vector2) + Vector2(8, 8)
		var frot: float = deg_to_rad(float(fb.get("rotation", 0.0)))
		var extv: float = GravityMode._sq_ext(frot, PI / 2.0)
		var bty: int = int(floor((fc.y + extv + 2.0) / 16.0))
		if bty >= grav.ground_y or WorldManager.is_solid_at(int(floor(fc.x / 16.0)), bty):
			continue
		var held: bool = false
		for nb in WorldManager.free_blocks:
			if nb == fb or not (nb.get("rubble", false) or nb.get("is_cap", false)):
				continue
			var ncc: Vector2 = (nb.pos as Vector2) + Vector2(8, 8)
			var dvv: Vector2 = fc - ncc
			var ddd: float = dvv.length()
			if ddd < 0.001 or ddd >= 22.8:
				continue
			var naa: float = atan2(dvv.y, dvv.x)
			var need: float = GravityMode._sq_ext(frot, naa) + GravityMode._sq_ext(deg_to_rad(float(nb.get("rotation", 0.0))), naa)
			if ddd <= need + 2.0 and (dvv / ddd).y < -0.35:
				held = true
				break
		if not held:
			fails += 1
			print("FTEST %s FLOATER: rubble at (%.1f,%.1f)" % [tag, fc.x, fc.y])

func _check_mass(tag: String) -> void:
	var m: int = _mass()
	if m != initial_mass:
		fails += 1
		print("FTEST %s MASS: %d != initial %d" % [tag, m, initial_mass])

func _sim(steps: int, tag: String, check_every: int = 60) -> void:
	for i in range(steps):
		# manual stepping runs many sim steps per engine frame — the fb
		# spatial grid caches per-frame, so force a rebuild every step
		WorldManager._fb_grid_frame = -1
		grav._step_debris(DT)
		if i % 8 == 0:
			WorldManager._fb_grid_frame = -1
			grav._support_scan()
			grav._rubble_support_scan()
		if i % check_every == check_every - 1:
			_check_overlap(tag)
			_check_mass(tag)

func _ready() -> void:
	WorldManager.init_empty_world(80, 40)
	# Slab floor rows 30..38 (grounded on the bottom border)
	for x in range(1, 79):
		for y in range(30, 39):
			WorldManager.set_fg_tile(x, y, 5000)
	# Towers on the slab
	for cy in range(24, 30):
		WorldManager.set_fg_tile(12, cy, 6004)
	for cy in range(20, 30):
		WorldManager.set_fg_tile(24, cy, 6012)
		WorldManager.set_fg_tile(25, cy, 6012)
	for cy in range(16, 30):
		WorldManager.set_fg_tile(40, cy, 6020)
		WorldManager.set_fg_tile(41, cy, 6020)
	# Staircase
	for stp in range(6):
		for cy in range(29 - stp, 30):
			WorldManager.set_fg_tile(55 + stp, cy, 6051)
	# Floating platform (must fall in settle phase)
	for cx in range(64, 70):
		WorldManager.set_fg_tile(cx, 12, 6008)
	grav = GravityMode.new()
	grav.attached = true
	add_child(grav)
	grav.set_process(false)
	grav._rng.seed = 777
	initial_mass = _mass()
	print("FTEST start mass=%d" % initial_mass)

	# P0: settle — floating platform falls, everything else must NOT move
	var grid_before: int = _movable_grid()
	_sim(360, "P0")
	_check_floaters("P0")
	if WorldManager.get_tile(66, 12) != 0:
		fails += 1
		print("FTEST P0: floating platform did not fall")
	if grav._debris.size() != 0:
		fails += 1
		print("FTEST P0: not converged (%d debris)" % grav._debris.size())
	if _movable_grid() < grid_before - 6 - 1:
		fails += 1
		print("FTEST P0: stable structures lost tiles (%d -> %d)" % [grid_before, _movable_grid()])

	# P1: knock all tower bases (plow-style flings)
	for c in [[12, 29, 1.0], [24, 29, 1.0], [25, 29, -1.0], [40, 29, 1.0], [41, 29, -1.0]]:
		grav._loosen(c[0], c[1], Vector2(200.0 * c[2], -90.0))
	_sim(1440, "P1")
	_check_floaters("P1")
	if grav._debris.size() != 0:
		fails += 1
		print("FTEST P1: not converged (%d debris)" % grav._debris.size())

	# P2: kick 12 resting rubble blocks hard (player plow simulation)
	var kicked: int = 0
	var ri: int = WorldManager.free_blocks.size() - 1
	while ri >= 0 and kicked < 12:
		var fb: Dictionary = WorldManager.free_blocks[ri]
		if fb.get("rubble", false):
			WorldManager.free_blocks.remove_at(ri)
			grav._debris.append({"pos": (fb.pos as Vector2) + Vector2(8, 8),
				"vel": Vector2(220.0 * (1.0 if kicked % 2 == 0 else -1.0), -140.0),
				"rot": deg_to_rad(float(fb.get("rotation", 0.0))), "rv": 2.0,
				"id": fb.id, "bn": 0, "jam": 0})
			kicked += 1
		ri -= 1
	_sim(1440, "P2")
	_check_floaters("P2")
	if grav._debris.size() != 0:
		fails += 1
		print("FTEST P2: not converged (%d debris)" % grav._debris.size())

	# P3: freeze — resting world must not move AT ALL anymore
	var snap: Array = []
	for fb in WorldManager.free_blocks:
		if fb.get("rubble", false):
			snap.append([fb, fb.pos])
	_sim(360, "P3")
	for sp in snap:
		var fb2: Dictionary = sp[0]
		if not WorldManager.free_blocks.has(fb2):
			fails += 1
			print("FTEST P3 CHURN: resting block was ejected again")
			continue
		if ((fb2.pos as Vector2) - (sp[1] as Vector2)).length() > 0.01:
			fails += 1
			print("FTEST P3 CHURN: resting block moved %.2fpx" % ((fb2.pos as Vector2) - (sp[1] as Vector2)).length())
	_check_overlap("P3")
	_check_floaters("P3")
	_check_mass("P3")
	print("GRAVITY FULL TEST: %s (%d violations, mass %d, rubble %d, grid %d)" % ["PASS" if fails == 0 else "FAIL", fails, _mass(), _mass() - _movable_grid() - grav._debris.size(), _movable_grid()])
	get_tree().quit(0 if fails == 0 else 1)
