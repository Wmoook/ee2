extends Node
## Headless regression tests for curve physics (CurveSolver).
## Run: godot --headless --path . res://tests/curve_test.tscn
## Asserts: no tunneling at terminal velocity, stable wedge rest + jump escape,
## U-tube (pinch split) containment, speed preservation while riding, and that
## plain tile physics still behaves exactly like EE.

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	WorldManager.init_empty_world(80, 60)
	_test_ee_equivalence()
	_test_flat_tiles()
	_test_terminal_drop()
	_test_diagonal_slam()
	_test_v_wedge_and_jump()
	_test_u_tube()
	_test_ride_speed()
	_test_pinch_slam()
	print("==== RESULT: %d checks, %d FAILED ====" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _t(ee_ticks: int) -> int:
	## Convert a tick count tuned for the original 100Hz engine to the current
	## tick rate (same wall-clock duration).
	return int(ceil(ee_ticks * EEPhysics.TPS / 100.0))


func _test_ee_equivalence() -> void:
	print("[240Hz reproduces the 100Hz EE reference]")
	_clear()
	var d: float = pow(0.9981, 10.0) * 1.00016093
	var a: float = 2.0 / 7.752
	# Free fall: velocity must match the 100Hz engine EXACTLY at EE boundaries
	var p: EEPhysics = _mk_phys(400.0, 100.0)
	var ee_ticks: int = 60
	var y0: float = p.y
	for i in range(int(round(ee_ticks * EEPhysics.TPS / 100.0))):
		p.tick(0, 0, false, false)
	var v_ref: float = 0.0
	var dy_ref: float = 0.0
	for i in range(ee_ticks):
		v_ref = (v_ref + a) * d
		dy_ref += v_ref
	_check(absf(p._speedY - v_ref) < 0.002, "fall speed matches 100Hz exactly (%.4f vs %.4f)" % [p._speedY, v_ref])
	_check(absf((p.y - y0) - dy_ref) < 4.0, "fall distance within 4px of 100Hz (%.1f vs %.1f)" % [p.y - y0, dy_ref])
	# Jump apex must match the 100Hz reference (block clearances preserved)
	var p2: EEPhysics = _mk_phys(400.0, 936.0)
	for i in range(_t(50)):
		p2.tick(0, 0, false, false)
	var rest_y: float = p2.y
	_check(p2.is_grounded, "settled on floor for jump test")
	p2.tick(0, 0, true, true)
	var min_y: float = rest_y
	for i in range(_t(120)):
		p2.tick(0, 0, false, false)
		min_y = minf(min_y, p2.y)
	var apex_new: float = rest_y - min_y
	var v_j: float = -(2.0 * 26.0 * 0.995) / 7.752
	var apex_ref: float = 0.0
	var vv: float = v_j
	for i in range(5000):
		vv = (vv + a) * d
		if vv >= 0.0:
			break
		apex_ref -= vv
	_check(absf(apex_new - apex_ref) < 0.5, "jump apex matches 100Hz (%.2f vs %.2f px)" % [apex_new, apex_ref])


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  pass: " + label)
	else:
		_fails += 1
		print("  FAIL: " + label)


func _tile_solid(tx: int, ty: int) -> bool:
	return WorldManager.is_solid_at(tx, ty)


func _mk_phys(cx: float, cy: float) -> EEPhysics:
	var p: EEPhysics = EEPhysics.new()
	p.set_collides_fn(Callable(self, "_tile_solid"))
	p.x = cx - 8.0
	p.y = cy - 8.0
	return p


func _clear() -> void:
	WorldManager.polylines.clear()
	WorldManager.free_blocks.clear()
	WorldManager.wedge_pairs.clear()
	WorldManager.lines.clear()


func _densify(pts: Array) -> PackedVector2Array:
	## 1px point resolution, like the in-game curve tool output.
	var out: PackedVector2Array = PackedVector2Array()
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n: int = maxi(1, int(round(a.distance_to(b))))
		for k in range(n):
			out.append(a.lerp(b, float(k) / float(n)))
	out.append(pts[pts.size() - 1])
	return out


func _min_curve_dist(cx: float, cy: float) -> float:
	var best: float = 999999.0
	for poly in WorldManager.polylines:
		if poly.get("render_only", false):
			continue
		var pts: PackedVector2Array = poly.points
		for si in range(pts.size() - 1):
			var sa: Vector2 = pts[si]
			var ab: Vector2 = pts[si + 1] - sa
			var t: float = clampf((Vector2(cx, cy) - sa).dot(ab) / maxf(ab.dot(ab), 0.001), 0.0, 1.0)
			var d: float = Vector2(cx, cy).distance_to(sa + ab * t)
			if d < best:
				best = d
	return best


func _test_flat_tiles() -> void:
	print("[flat tiles: EE base physics unchanged]")
	_clear()
	# Bottom border row is at tile y=59 -> pixels 944..960. Player rests at y=928.
	var p: EEPhysics = _mk_phys(400.0, 800.0)
	for i in range(_t(300)):
		p.tick(0, 0, false, false)
	_check(p.is_grounded, "grounded on border floor")
	_check(absf(p.y - 928.0) < 0.01, "rests exactly on tile top (y=%.3f)" % p.y)
	var peak: float = 0.0
	for i in range(_t(300)):
		p.tick(1, 0, false, false)
		peak = maxf(peak, p._speedX)
	_check(peak > 6.0 and peak < 7.0, "peak walk speed ~6.7 (got %.2f)" % peak)
	_check(absf(p.x - 1248.0) < 0.01, "stopped exactly at right border wall (x=%.2f)" % p.x)


func _test_terminal_drop() -> void:
	print("[terminal-velocity drop onto horizontal curve]")
	_clear()
	WorldManager.add_polyline(_densify([Vector2(200, 400), Vector2(600, 400)]), "both", 9)
	var p: EEPhysics = _mk_phys(400.0, 100.0)
	p._speedY = 16.0
	var crossed: bool = false
	for i in range(_t(300)):
		p.tick(0, 0, false, false)
		if p.y + 8.0 > 400.0:
			crossed = true
	_check(not crossed, "center never crossed the centerline")
	_check(absf((p.y + 8.0) - 383.65) < 1.0, "rests on capsule surface (cy=%.2f, want ~383.65)" % (p.y + 8.0))
	_check(p.is_grounded, "grounded on curve")
	_check(p._speedY < 0.2, "vertical speed absorbed")


func _test_diagonal_slam() -> void:
	print("[diagonal slam at max speed (16,16)]")
	_clear()
	WorldManager.add_polyline(_densify([Vector2(200, 400), Vector2(600, 400)]), "both", 9)
	var p: EEPhysics = _mk_phys(300.0, 340.0)
	p._speedX = 16.0
	p._speedY = 16.0
	var breached: bool = false
	for i in range(_t(150)):
		p.tick(1, 0, false, false)
		var cx: float = p.x + 8.0
		var cy: float = p.y + 8.0
		if cx > 210.0 and cx < 590.0 and cy > 400.0:
			breached = true
	_check(not breached, "no clip-through anywhere over the curve span")


func _test_v_wedge_and_jump() -> void:
	print("[V wedge: slide in, rest at pinch, jump out]")
	_clear()
	# Sharp 90-degree V drawn as ONE stroke (exercises same-poly branch contacts)
	WorldManager.add_polyline(_densify([Vector2(250, 300), Vector2(350, 400), Vector2(450, 300)]), "both", 9)
	var p: EEPhysics = _mk_phys(356.0, 200.0)
	var below_pinch: bool = false
	for i in range(_t(500)):
		p.tick(0, 0, false, false)
		if p.y + 8.0 > 400.0:
			below_pinch = true
	# Expected rest: on the V bisector, 16.0/sin(45deg) above the pinch
	var want_cy: float = 400.0 - 16.0 / sin(deg_to_rad(45.0))
	var cx: float = p.x + 8.0
	var cy: float = p.y + 8.0
	_check(not below_pinch, "never fell through the pinch")
	_check(absf(p._speedX) + absf(p._speedY) < 0.3, "came to rest (|v|=%.3f)" % (absf(p._speedX) + absf(p._speedY)))
	_check(absf(cx - 350.0) < 1.5, "rest centered on wedge X (cx=%.2f)" % cx)
	_check(absf(cy - want_cy) < 1.5, "rest at wedge point Y (cy=%.2f want %.2f)" % [cy, want_cy])
	_check(_min_curve_dist(cx, cy) > 15.9, "capsule constraint satisfied (d=%.2f)" % _min_curve_dist(cx, cy))
	_check(p.is_grounded, "grounded while wedged")
	_check(p.in_valley, "in_valley reported")
	_check(p.is_wedged, "is_wedged reported")
	# Stability: no oscillation over 100 further ticks
	var min_x: float = 99999.0
	var max_x: float = -99999.0
	for i in range(_t(100)):
		p.tick(0, 0, false, false)
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
	_check(max_x - min_x < 0.3, "no oscillation while resting (dx=%.3f)" % (max_x - min_x))
	# Jump out
	var rest_cy: float = p.y + 8.0
	p.tick(0, 0, true, true)
	for i in range(_t(30)):
		p.tick(0, 0, false, false)
	_check(rest_cy - (p.y + 8.0) > 15.0, "jump escapes the wedge (rose %.1fpx)" % (rest_cy - (p.y + 8.0)))


func _test_u_tube() -> void:
	print("[U tube: fold-back curve (pinch split path)]")
	_clear()
	WorldManager.add_polyline(_densify([
		Vector2(380, 180), Vector2(380, 320), Vector2(383, 332), Vector2(390, 338),
		Vector2(400, 340), Vector2(410, 338), Vector2(417, 332), Vector2(420, 320), Vector2(420, 180)
	]), "both", 9)
	var p: EEPhysics = _mk_phys(400.0, 150.0)
	p._speedY = 8.0
	var escaped_side: bool = false
	for i in range(_t(600)):
		p.tick(0, 0, false, false)
		var cx: float = p.x + 8.0
		var cy: float = p.y + 8.0
		if cy > 200.0 and (cx < 380.0 or cx > 420.0):
			escaped_side = true
	var fcx: float = p.x + 8.0
	var fcy: float = p.y + 8.0
	_check(not escaped_side, "never clipped through a tube arm")
	_check(absf(p._speedX) + absf(p._speedY) < 0.4, "settled in tube (|v|=%.3f)" % (absf(p._speedX) + absf(p._speedY)))
	_check(fcy > 300.0 and fcy < 328.0, "rests near tube bottom (cy=%.2f)" % fcy)
	_check(fcx > 395.0 and fcx < 405.0, "centered in tube (cx=%.2f)" % fcx)
	_check(_min_curve_dist(fcx, fcy) > 15.9, "capsule constraint satisfied (d=%.2f)" % _min_curve_dist(fcx, fcy))
	_check(p.is_grounded, "grounded at tube bottom")


func _test_ride_speed() -> void:
	print("[riding a slope curve keeps speed (old CCD bug regression)]")
	_clear()
	WorldManager.add_polyline(_densify([Vector2(150, 500), Vector2(650, 420)]), "both", 9)
	var p: EEPhysics = _mk_phys(200.0, 460.0)
	var breached: bool = false
	var reached_end: bool = false
	var speed_at_end: float = 0.0
	for i in range(_t(400)):
		p.tick(1, 0, false, false)
		var cx: float = p.x + 8.0
		var cy: float = p.y + 8.0
		var line_y: float = 500.0 - 0.16 * (cx - 150.0)
		if cx > 160.0 and cx < 640.0 and cy > line_y + 0.5:
			breached = true
		if cx > 600.0 and not reached_end:
			reached_end = true
			speed_at_end = Vector2(p._speedX, p._speedY).length()
	_check(not breached, "stayed on top of the slope the whole ride")
	_check(reached_end, "rode the full slope uphill (cx=%.1f)" % (p.x + 8.0))
	_check(speed_at_end > 4.0, "no phantom hard-stops (speed at end %.2f)" % speed_at_end)


func _test_pinch_slam() -> void:
	print("[straight terminal drop into V mouth]")
	_clear()
	WorldManager.add_polyline(_densify([Vector2(250, 300), Vector2(350, 400), Vector2(450, 300)]), "both", 9)
	var p: EEPhysics = _mk_phys(350.0, 250.0)
	p._speedY = 16.0
	var breached: bool = false
	for i in range(_t(200)):
		p.tick(0, 0, false, false)
		if p.y + 8.0 > 395.0:
			breached = true
	var want_cy: float = 400.0 - 16.0 / sin(deg_to_rad(45.0))
	var cx: float = p.x + 8.0
	var cy: float = p.y + 8.0
	_check(not breached, "never passed the pinch at terminal velocity")
	_check(absf(cx - 350.0) < 2.0, "rest centered (cx=%.2f)" % cx)
	_check(absf(cy - want_cy) < 2.5, "rest at wedge point (cy=%.2f want %.2f)" % [cy, want_cy])
	_check(absf(p._speedX) + absf(p._speedY) < 0.3, "at rest (|v|=%.3f)" % (absf(p._speedX) + absf(p._speedY)))
