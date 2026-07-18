extends Node
## Capless curve END collision: the capsule model must hold the ball at the
## very end of a curve (rounded stub), mid-curve as always, and let it FALL
## past the end (open air is open).

var physics: EEPhysics

func _tick_n(n: int, ix: int = 0) -> void:
	for _i in range(n):
		physics.tick(ix, 0, false, false)

func _ready() -> void:
	WorldManager.init_empty_world(120, 80)
	# A gentle arc like an editor-placed curve, ending mid-air at x=900
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(0, 600, 2):
		pts.append(Vector2(300.0 + i, 500.0 + sin(i * 0.004) * 40.0))
	WorldManager.add_polyline(pts, "both", 5058)
	WorldManager.build_curve_colliders()
	var fails: int = 0
	physics = EEPhysics.new()
	physics.set_collides_fn(func(_x, _y): return false)
	# 1) Drop on the very END of the curve
	var end_p: Vector2 = pts[pts.size() - 1]
	physics.x = end_p.x - 8.0
	physics.y = end_p.y - 80.0
	physics._speedX = 0.0
	physics._speedY = 0.0
	_tick_n(600)
	var rest_d: float = Vector2(physics.x + 8.0, physics.y + 8.0).distance_to(end_p)
	if rest_d > 24.0:
		fails += 1
		print("FAIL end rest: dist=%.1f (ball at %.1f,%.1f end %.1f,%.1f)" % [rest_d, physics.x + 8, physics.y + 8, end_p.x, end_p.y])
	else:
		print("pass: rests on curve END (dist=%.1f)" % rest_d)
	# 2) Drop on the middle
	var mid_p: Vector2 = pts[pts.size() / 2]
	physics.x = mid_p.x - 8.0
	physics.y = mid_p.y - 80.0
	physics._speedX = 0.0
	physics._speedY = 0.0
	_tick_n(600)
	# It may roll along the arc to a local valley — assert it rests ON the
	# curve (capsule distance), not at the exact drop point
	var mid_d: float = WorldManager.dist_to_nearest_polyline(physics.x + 8.0, physics.y + 8.0)
	if absf(mid_d - 16.35) > 2.5:
		fails += 1
		print("FAIL mid rest: capsule dist=%.1f (want ~16.35)" % mid_d)
	else:
		print("pass: rests mid-curve (capsule dist=%.1f)" % mid_d)
	# 3) Drop 60px PAST the end — must fall freely
	physics.x = end_p.x + 60.0 - 8.0
	physics.y = end_p.y - 80.0
	physics._speedX = 0.0
	physics._speedY = 0.0
	_tick_n(600)
	if physics.y < end_p.y + 100.0:
		fails += 1
		print("FAIL past-end: ball hung at y=%.1f" % physics.y)
	else:
		print("pass: falls past the open end (y=%.1f)" % physics.y)
	print("CURVE END TEST: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
