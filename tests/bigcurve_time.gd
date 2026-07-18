extends Node
## Times placing a HUGE folded U-curve (4000 pts at 1px) through the full
## add_polyline pipeline — the web freeze repro. Prints ms.

func _ready() -> void:
	WorldManager.build_sample_room()
	var pts: PackedVector2Array = PackedVector2Array()
	# Giant U: down 2000px, U-turn, back up — guaranteed pinch candidates
	for i in range(2000):
		pts.append(Vector2(400.0 + sin(i * 0.01) * 40.0, 300.0 + i))
	for a in range(60):
		var ang: float = PI * a / 59.0
		pts.append(Vector2(400.0 + sin(2000 * 0.01) * 40.0 + 30.0 - cos(ang) * 30.0, 2300.0 + sin(ang) * 30.0))
	for i2 in range(2000):
		pts.append(Vector2(460.0 + sin((2000 - i2) * 0.01) * 40.0, 2300.0 - i2))
	var t0: int = Time.get_ticks_usec()
	WorldManager.add_polyline(pts, "both", 5058)
	var t1: int = Time.get_ticks_usec()
	WorldManager.build_curve_colliders()
	var t2: int = Time.get_ticks_usec()
	print("BIGCURVE: pts=%d add=%.1fms colliders=%.1fms polys=%d" % [
		pts.size(), (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, WorldManager.polylines.size()])
	get_tree().quit(0)
