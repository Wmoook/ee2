extends Node
## Find every segment CROSSING in the real world; drop a ball into the
## upper V of each; verify it can jump out (open sky above assumed —
## report headroom too so real ceilings are distinguishable).

var physics: EEPhysics
func _tile_solid(tx: int, ty: int) -> bool:
	return WorldManager.is_solid_at(tx, ty)

func _seg_cross(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> Variant:
	var r: Vector2 = a2 - a1
	var s: Vector2 = b2 - b1
	var den: float = r.cross(s)
	if absf(den) < 0.0001:
		return null
	var t: float = (b1 - a1).cross(s) / den
	var u: float = (b1 - a1).cross(r) / den
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return null
	return a1 + r * t

func _ready() -> void:
	var f: FileAccess = FileAccess.open("user://world_dump.json", FileAccess.READ)
	WorldManager.deserialize_world(JSON.parse_string(f.get_as_text()))
	f.close()
	WorldManager.build_curve_colliders()
	var polys: Array = []
	for poly in WorldManager.polylines:
		if poly.get("render_only", false):
			continue
		polys.append(poly.points)
	var crossings: Array = []
	for pa in range(polys.size()):
		for pb in range(pa, polys.size()):
			var A: PackedVector2Array = polys[pa]
			var B: PackedVector2Array = polys[pb]
			for i in range(0, A.size() - 1, 2):
				for j in range(0, B.size() - 1, 2):
					if pa == pb and abs(i - j) < 8:
						continue
					var hit = _seg_cross(A[i], A[mini(i + 2, A.size() - 1)], B[j], B[mini(j + 2, B.size() - 1)])
					if hit != null:
						var dup: bool = false
						for cx in crossings:
							if (cx as Vector2).distance_to(hit) < 24.0:
								dup = true
								break
						if not dup:
							crossings.append(hit)
	print("XAUDIT: %d crossings" % crossings.size())
	var fails: int = 0
	var tested: int = 0
	for cr in crossings:
		var v: Vector2 = cr
		physics = EEPhysics.new()
		physics.set_collides_fn(Callable(self, "_tile_solid"))
		physics.x = v.x - 8.0
		physics.y = v.y - 90.0 - 8.0
		physics._speedX = 0.0
		physics._speedY = 0.0
		for i in range(900):
			physics.tick(0, 0, false, false)
		var rest: Vector2 = Vector2(physics.x + 8.0, physics.y + 8.0)
		if rest.distance_to(v) > 120.0:
			continue  # slid away from this crossing
		tested += 1
		var grounded: bool = physics.is_grounded
		var headroom: float = 999.0
		for dy in range(16, 200, 8):
			var pd: float = WorldManager.dist_to_nearest_polyline(rest.x, rest.y - float(dy))
			if pd < 16.0:
				headroom = float(dy)
				break
		var rest_y: float = physics.y
		var min_y: float = physics.y
		for i in range(30):
			physics.tick(0, 0, true, false)
			min_y = minf(min_y, physics.y)
		for i in range(200):
			physics.tick(0, 0, false, false)
			min_y = minf(min_y, physics.y)
		var apex: float = rest_y - min_y
		var expect: float = minf(52.0, headroom - 18.0)
		var ok: bool = apex > 24.0 or (headroom < 60.0 and apex > maxf(expect * 0.4, 2.0)) or headroom < 30.0
		if not ok:
			fails += 1
		print("XAUDIT (%.0f,%.0f): rest=(%.0f,%.0f) grounded=%s headroom=%.0f apex=%.1f -> %s" % [v.x, v.y, rest.x, rest.y, str(grounded), headroom, apex, "ok" if ok else "STUCK"])
	print("XAUDIT: %s (%d stuck of %d tested)" % ["PASS" if fails == 0 else "FAIL", fails, tested])
	get_tree().quit(0)
