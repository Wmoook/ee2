extends Node
## Root-level action driver (survives scene changes): erases the stray probe
## V-curve near the far corner if a previous run left one in the world save.
var t: float = 0.0
var cleaned: bool = false
func _corner() -> Vector2:
	return Vector2(WorldManager.world_width * 16.0 - 120.0, WorldManager.world_height * 16.0 - 120.0)
func _process(delta: float) -> void:
	t += delta
	if NetPlay.my_room != "world":
		return
	if t > 8.0 and not cleaned:
		cleaned = true
		var target: Vector2 = _corner() + Vector2(24, 12)
		var found: bool = false
		for poly in WorldManager.polylines:
			for pt in poly.points:
				if pt.distance_to(target) < 40.0:
					found = true
					break
			if found:
				break
		if found:
			print("PROBE stray test curve found — erasing")
			WorldManager.net_remove_polyline_near(target, 40.0)
			print("PROBE cleanup done polys=%d online=%s" % [WorldManager.polylines.size(), str(NetPlay.online)])
		else:
			print("PROBE no stray curve (clean)")
