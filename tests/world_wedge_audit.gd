extends Node
## Load the REAL dumped world and test wedge-jump at EVERY upward-opening
## hairpin vertex of every curve: settle the ball into the V, jump, report.

var physics: EEPhysics

func _tile_solid(tx: int, ty: int) -> bool:
	return WorldManager.is_solid_at(tx, ty)

func _ready() -> void:
	var f: FileAccess = FileAccess.open("user://world_dump.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	WorldManager.deserialize_world(data)
	WorldManager.build_curve_colliders()
	# Sample drop points every ~60px along every curve; wherever the ball
	# settles cradled (in_valley / 2 contacts), test the jump.
	var spots: Array = []
	for poly in WorldManager.polylines:
		if poly.get("collision_only", false) or poly.get("render_only", false):
			continue
		var pts: PackedVector2Array = poly.points
		var acc: float = 999.0
		for i in range(1, pts.size()):
			acc += pts[i].distance_to(pts[i - 1])
			if acc >= 60.0:
				acc = 0.0
				spots.append(pts[i] + Vector2(0, -40))
	print("AUDIT: %d drop spots" % spots.size())
	var fails: int = 0
	var valleys: int = 0
	for sp in spots:
		var v: Vector2 = sp
		physics = EEPhysics.new()
		physics.set_collides_fn(Callable(self, "_tile_solid"))
		physics.x = v.x - 8.0
		physics.y = v.y - 8.0
		physics._speedX = 0.0
		physics._speedY = 0.0
		for i in range(1000):
			physics.tick(0, 0, false, false)
		var rest_y: float = physics.y
		var grounded: bool = physics.is_grounded
		var min_y: float = physics.y
		for i in range(30):
			physics.tick(0, 0, true, false)
			min_y = minf(min_y, physics.y)
		for i in range(200):
			physics.tick(0, 0, false, false)
			min_y = minf(min_y, physics.y)
		var apex: float = rest_y - min_y
		var ok: bool = apex > 24.0
		if physics.in_valley or physics.is_wedged:
			valleys += 1
			if not ok:
				fails += 1
				print("AUDIT STUCK valley at rest (%.0f,%.0f): grounded=%s apex=%.1f" % [physics.x + 8.0, rest_y + 8.0, str(grounded), apex])
		elif grounded and not ok:
			fails += 1
			print("AUDIT STUCK grounded at rest (%.0f,%.0f): apex=%.1f" % [physics.x + 8.0, rest_y + 8.0, apex])
	print("WEDGE AUDIT: %s (%d stuck, %d valleys, %d spots)" % ["PASS" if fails == 0 else "FAIL", fails, valleys, spots.size()])
	get_tree().quit(0 if fails == 0 else 1)
