extends Node
## Root-level action driver (survives scene changes): places a V-curve with
## caps in a far corner of the live world, later erases it (fires fullsync).
var t: float = 0.0
var placed: bool = false
var erased: bool = false
func _corner() -> Vector2:
	return Vector2(WorldManager.world_width * 16.0 - 120.0, WorldManager.world_height * 16.0 - 120.0)
func _process(delta: float) -> void:
	t += delta
	if NetPlay.my_room != "world":
		return
	if t > 8.0 and not placed:
		placed = true
		var o: Vector2 = _corner()
		var pts: PackedVector2Array = PackedVector2Array()
		for i in range(0, 49, 2):
			pts.append(o + Vector2(i, absf(i - 24.0)))
		print("PROBE placing V curve at %s (%d pts)" % [str(o), pts.size()])
		WorldManager.net_add_polyline(pts, "both", 5058)
		for cap in WorldManager.curve_cap_blocks(pts, 5058):
			WorldManager.net_add_free_block(cap)
		print("PROBE placed ok polys=%d online=%s" % [WorldManager.polylines.size(), str(NetPlay.online)])
	if t > 30.0 and not erased:
		erased = true
		print("PROBE erasing test curve (triggers poly fullsync)")
		WorldManager.net_remove_polyline_near(_corner() + Vector2(24, 12), 40.0)
		print("PROBE erase done polys=%d online=%s" % [WorldManager.polylines.size(), str(NetPlay.online)])
