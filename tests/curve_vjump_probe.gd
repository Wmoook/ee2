extends Node
## Steep-V wedge: ball cradled between two near-vertical curve walls MUST be
## able to jump straight up ("2 walls = ground").

var physics: EEPhysics

func _tile_solid(tx: int, ty: int) -> bool:
	return WorldManager.is_solid_at(tx, ty)

func _probe(half_angle_deg: float) -> void:
	WorldManager.init_empty_world(400, 200)
	# V with walls half_angle from VERTICAL, vertex at (800, 900)
	var s: float = tan(deg_to_rad(half_angle_deg))
	var pts: PackedVector2Array = PackedVector2Array()
	var y: float = 100.0
	while y < 900.0:
		pts.append(Vector2(800.0 - (900.0 - y) * s, y))
		y += 2.0
	y = 900.0
	while y > 100.0:
		pts.append(Vector2(800.0 + (900.0 - y) * s, y))
		y -= 2.0
	WorldManager.add_polyline(pts, "both", 5058)
	WorldManager.build_curve_colliders()
	physics = EEPhysics.new()
	physics.set_collides_fn(Callable(self, "_tile_solid"))
	physics.x = 792.0
	physics.y = 500.0
	physics._speedX = 0.0
	physics._speedY = 0.0
	for i in range(1200):
		physics.tick(0, 0, false, false)
	var rest_y: float = physics.y
	var grounded: bool = physics.is_grounded
	var wedged: bool = physics.is_wedged
	# Hold jump like a real press; track the APEX (ball falls back after)
	var min_y: float = physics.y
	for i in range(30):
		physics.tick(0, 0, true, false)
		min_y = minf(min_y, physics.y)
	for i in range(200):
		physics.tick(0, 0, false, false)
		min_y = minf(min_y, physics.y)
	var apex: float = rest_y - min_y
	print("VJUMP half=%ddeg: rest_y=%.1f grounded=%s wedged=%s apex_rise=%.1fpx -> %s" % [int(half_angle_deg), rest_y, str(grounded), str(wedged), apex, "PASS" if apex > 24.0 else "FAIL"])

func _probe_coarse(half_angle_deg: float) -> void:
	# COARSE ~24px chords (old 700-pt curves): near the vertex the two walls
	# are only a few SEGMENTS apart — the index-gap branch rule rejected the
	# second wall contact, so the wedge never grounded and jump was dead.
	WorldManager.init_empty_world(400, 200)
	var s: float = tan(deg_to_rad(half_angle_deg))
	var pts: PackedVector2Array = PackedVector2Array()
	var y: float = 100.0
	while y < 900.0:
		pts.append(Vector2(800.0 - (900.0 - y) * s, y))
		y += 24.0
	pts.append(Vector2(800.0, 900.0))
	y = 900.0 - 24.0
	while y > 100.0:
		pts.append(Vector2(800.0 + (900.0 - y) * s, y))
		y -= 24.0
	WorldManager.add_polyline(pts, "both", 5058)
	WorldManager.build_curve_colliders()
	physics = EEPhysics.new()
	physics.set_collides_fn(Callable(self, "_tile_solid"))
	physics.x = 792.0
	physics.y = 500.0
	physics._speedX = 0.0
	physics._speedY = 0.0
	for i in range(1200):
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
	print("VJUMP-COARSE half=%ddeg: rest_y=%.1f grounded=%s apex_rise=%.1fpx -> %s" % [int(half_angle_deg), rest_y, str(grounded), apex, "PASS" if apex > 24.0 else "FAIL"])

func _probe_w() -> void:
	# MULTI-hairpin stroke (like the user's serpentine): pinch-split handles
	# only ONE hairpin; in the other, both walls live in one collision poly
	# where the index-gap rule rejected the second wall -> no cradle, no jump.
	WorldManager.init_empty_world(400, 200)
	var s: float = tan(deg_to_rad(12.0))
	var pts: PackedVector2Array = PackedVector2Array()
	var y: float = 200.0
	while y < 900.0:  # down into vertex A (x 600)
		pts.append(Vector2(600.0 - (900.0 - y) * s, y))
		y += 24.0
	pts.append(Vector2(600.0, 900.0))
	y = 900.0 - 24.0
	while y > 300.0:  # up the middle
		pts.append(Vector2(600.0 + (900.0 - y) * s, y))
		y -= 24.0
	var mid_x: float = 600.0 + (900.0 - 300.0) * s
	var bx: float = mid_x + (900.0 - 300.0) * s
	y = 300.0
	while y < 900.0:  # down into vertex B
		pts.append(Vector2(bx - (900.0 - y) * s, y))
		y += 24.0
	pts.append(Vector2(bx, 900.0))
	y = 900.0 - 24.0
	while y > 200.0:  # up and out
		pts.append(Vector2(bx + (900.0 - y) * s, y))
		y -= 24.0
	WorldManager.add_polyline(pts, "both", 5058)
	WorldManager.build_curve_colliders()
	physics = EEPhysics.new()
	physics.set_collides_fn(Callable(self, "_tile_solid"))
	physics.x = bx - 8.0
	physics.y = 500.0
	physics._speedX = 0.0
	physics._speedY = 0.0
	for i in range(1200):
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
	print("VJUMP-W (unsplit hairpin): rest_y=%.1f grounded=%s apex_rise=%.1fpx -> %s" % [rest_y, str(grounded), apex, "PASS" if apex > 24.0 else "FAIL"])

func _ready() -> void:
	_probe(30.0)
	_probe(15.0)
	_probe(8.0)
	_probe_coarse(15.0)
	_probe_coarse(10.0)
	_probe_w()
	get_tree().quit(0)
