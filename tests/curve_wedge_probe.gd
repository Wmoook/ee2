extends Node
## Reproduce: serpentine corridor narrowing right, ball held RIGHT into the
## squeeze. The capsule constraint must keep center >= ~16 from BOTH arms.

var physics: EEPhysics

func _tile_solid(tx: int, ty: int) -> bool:
	return WorldManager.is_solid_at(tx, ty)

func _ready() -> void:
	WorldManager.init_empty_world(400, 200)
	var pts: PackedVector2Array = PackedVector2Array()
	var x: float = 100.0
	while x < 2000.0:
		pts.append(Vector2(x, 200.0 + (x - 100.0) * 0.0165))
		x += 2.0
	x = 2000.0
	while x > 100.0:
		pts.append(Vector2(x, 234.0 + (2000.0 - x) * 0.052))
		x -= 2.0
	WorldManager.add_polyline(pts, "both", 5058)
	WorldManager.build_curve_colliders()
	physics = EEPhysics.new()
	physics.set_collides_fn(Callable(self, "_tile_solid"))
	# Start resting on the LOWER arm inside the corridor
	physics.x = 592.0
	physics.y = 240.0
	physics._speedX = 0.0
	physics._speedY = 0.0
	for i in range(300):
		physics.tick(0, 0, false, false)
	var min_d: float = 999.0
	var min_at: Vector2 = Vector2.ZERO
	for i in range(4000):
		physics.tick(1, 0, false, false)
		var d: float = WorldManager.dist_to_nearest_polyline(physics.x + 8.0, physics.y + 8.0)
		if d < min_d:
			min_d = d
			min_at = Vector2(physics.x + 8.0, physics.y + 8.0)
	var fin_d: float = WorldManager.dist_to_nearest_polyline(physics.x + 8.0, physics.y + 8.0)
	print("WEDGE PROBE: min_dist=%.2f at (%.1f,%.1f)  final_dist=%.2f final=(%.1f,%.1f)" % [min_d, min_at.x, min_at.y, fin_d, physics.x + 8.0, physics.y + 8.0])
	print("WEDGE PROBE: %s" % ("PASS" if min_d > 15.0 else "FAIL — penetrated %.1fpx" % (16.0 - min_d)))
	get_tree().quit(0)
