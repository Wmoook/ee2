extends Node
## Focused diagnostic at the real stuck wedge: contacts + jump-tick trace.
var physics: EEPhysics
func _tile_solid(tx: int, ty: int) -> bool:
	return WorldManager.is_solid_at(tx, ty)
func _ready() -> void:
	var f: FileAccess = FileAccess.open("user://world_dump.json", FileAccess.READ)
	WorldManager.deserialize_world(JSON.parse_string(f.get_as_text()))
	f.close()
	WorldManager.build_curve_colliders()
	physics = EEPhysics.new()
	physics.set_collides_fn(Callable(self, "_tile_solid"))
	physics.x = 2644.0 - 8.0
	physics.y = 1680.0 - 8.0
	physics._speedX = 0.0
	physics._speedY = 0.0
	for i in range(1000):
		physics.tick(0, 0, false, false)
	print("DIAG rest center=(%.2f,%.2f) grounded=%s valley=%s wedged=%s" % [physics.x + 8.0, physics.y + 8.0, physics.is_grounded, physics.in_valley, physics.is_wedged])
	var cons: Array = CurveSolver.gather_contacts(physics.x + 8.0, physics.y + 8.0, physics.x + 8.0, physics.y + 8.0)
	for c in cons:
		print("DIAG contact n=(%.3f,%.3f) depth=%.3f poly=%d" % [c.n.x, c.n.y, c.depth, c.pi])
	for dy in [8, 16, 24, 32, 48, 64]:
		var px: float = physics.x + 8.0
		var py: float = physics.y + 8.0 - float(dy)
		var pd: float = WorldManager.dist_to_nearest_polyline(px, py)
		var ts: bool = WorldManager.is_solid_at(int(px / 16.0), int(py / 16.0))
		print("DIAG above dy=%d: curve_dist=%.1f tile_solid=%s" % [dy, pd, str(ts)])
	for i in range(8):
		physics.tick(0, 0, true, false)
		print("DIAG jump tick %d: y=%.2f vy=%.2f grounded=%s" % [i, physics.y + 8.0, physics._speedY, physics.is_grounded])
	get_tree().quit(0)
