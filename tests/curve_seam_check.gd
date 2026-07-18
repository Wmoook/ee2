extends Node2D
## WORST CASE seam check: coarse 700-pt decimation (~22px chords) — every
## chord crosses 1-2 tile boundaries. After the seam-walk fix, no dark smears.
## 1px spline -> decimate -> 16px truncate -> add_polyline + caps.

func _editor_place(raw: PackedVector2Array, bid: int) -> void:
	var pts: PackedVector2Array = raw.duplicate()
	if pts.size() > 700:
		var keep_step: int = int(ceil(float(pts.size()) / 700.0))
		var dec: PackedVector2Array = PackedVector2Array()
		for i in range(0, pts.size(), keep_step):
			dec.append(pts[i])
		if dec[dec.size() - 1] != pts[pts.size() - 1]:
			dec.append(pts[pts.size() - 1])
		pts = dec
	var tlen: float = 0.0
	for i in range(1, pts.size()):
		tlen += pts[i].distance_to(pts[i - 1])
	var tmax: float = floor(tlen / 16.0) * 16.0
	if tmax >= 16.0 and tlen - tmax > 0.05:
		var acc: float = 0.0
		for i in range(1, pts.size()):
			var seg: float = pts[i].distance_to(pts[i - 1])
			if acc + seg >= tmax:
				pts.resize(i)
				pts.append(pts[i - 1].lerp(raw[mini(i, raw.size() - 1)], 0.0) if false else pts[i - 1])
				break
			acc += seg
	WorldManager.add_polyline(pts, "both", bid)
	for cap in WorldManager.curve_cap_blocks(pts, bid):
		WorldManager.free_blocks.append(cap)

func _ready() -> void:
	WorldManager.init_empty_world(400, 200)
	# Steep tall oscillations like the user's curve: ~15,000px arc length
	var raw: PackedVector2Array = PackedVector2Array()
	var prev: Vector2 = Vector2(100, 500)
	raw.append(prev)
	var x: float = 100.0
	while x < 3100.0:
		x += 0.25
		var p: Vector2 = Vector2(x, 500.0 + 400.0 * sin((x - 100.0) * 0.02))
		if p.distance_to(prev) >= 1.0:
			raw.append(p)
			prev = p
	print("raw pts=%d" % raw.size())
	_editor_place(raw, 6087)
	WorldManager.build_curve_colliders()
	var r: Node2D = preload("res://scripts/world/world_renderer.gd").new()
	add_child(r)
	var cam: Camera2D = Camera2D.new()
	cam.position = Vector2(1100, 500)
	cam.zoom = Vector2(0.62, 0.62)
	add_child(cam)
	cam.make_current()
	await get_tree().create_timer(1.4).timeout
	get_viewport().get_texture().get_image().save_png("user://curve_seam.png")
	print("LONG CURVE SHOT SAVED pts_stored=%d" % (WorldManager.polylines[0].points.size() if WorldManager.polylines.size() > 0 else -1))
	get_tree().quit(0)
