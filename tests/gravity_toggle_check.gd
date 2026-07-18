extends Node
## BLOCK GRAVITY (attached) check: floating tiles fall, curves crumble into
## debris then rubble, bottom-supported tiles stay, nothing is lost.

func _ready() -> void:
	WorldManager.init_empty_world(60, 40)
	# Grounded column on the bottom border (must SURVIVE)
	for cy in range(35, 39):
		WorldManager.set_fg_tile(8, cy, 5000)
	# Floating platform (must FALL)
	for cx in range(20, 28):
		WorldManager.set_fg_tile(cx, 10, 6008)
	# A curve (must CRUMBLE into ~10 tiles)
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(0, 161, 2):
		pts.append(Vector2(560.0 + i, 300.0 + sin(i * 0.02) * 12.0))
	WorldManager.add_polyline(pts, "both", 5058)
	WorldManager.build_curve_colliders()
	var grav: GravityMode = GravityMode.new()
	grav.attached = true
	add_child(grav)
	await get_tree().create_timer(0.3).timeout
	var mid_debris: int = grav._debris.size()
	await get_tree().create_timer(4.0).timeout
	var col_ok: bool = WorldManager.get_tile(8, 35) == 5000
	var plat_gone: bool = WorldManager.get_tile(23, 10) == 0
	var polys_gone: bool = WorldManager.polylines.is_empty()
	var settled: bool = grav._debris.size() == 0
	var rubble: int = 0
	for fb in WorldManager.free_blocks:
		if fb.get("rubble", false):
			rubble += 1
	var grid: int = 0
	for y in range(1, 39):
		for x in range(1, 59):
			var t: int = WorldManager.get_tile(x, y)
			if t != 0 and t != 9:
				grid += 1
	# initial: 4 column + 8 platform = 12 grid; curve ~10 tiles extra
	var mass_ok: bool = grid + rubble >= 20 and grid + rubble <= 26
	print("GTOG: mid_debris=%d col=%s plat_fell=%s polys_gone=%s settled=%s grid=%d rubble=%d" % [mid_debris, col_ok, plat_gone, polys_gone, settled, grid, rubble])
	var ok: bool = mid_debris > 6 and col_ok and plat_gone and polys_gone and settled and mass_ok
	print("GRAVITY TOGGLE CHECK: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
