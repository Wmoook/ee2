extends Node
## Visual check: curve ENDS are entire blocks. Places a horizontal, a
## diagonal, and an arced curve (editor-style: truncated to whole tiles +
## cap blocks) and saves user://curve_caps.png.

func _add_curve(raw: PackedVector2Array, bid: int) -> void:
	# Same pipeline as the editor: truncate to a 16px boundary, then caps
	var pts: PackedVector2Array = raw.duplicate()
	var tlen: float = 0.0
	for i in range(1, pts.size()):
		tlen += pts[i].distance_to(pts[i - 1])
	var tmax: float = floor(tlen / 16.0) * 16.0
	if tmax >= 16.0 and tlen - tmax > 0.05:
		var acc: float = 0.0
		for i in range(1, pts.size()):
			var seg: float = pts[i].distance_to(pts[i - 1])
			if acc + seg >= tmax:
				var t: float = (tmax - acc) / maxf(seg, 0.001)
				var cut: Vector2 = pts[i - 1].lerp(pts[i], t)
				pts.resize(i)
				pts.append(cut)
				break
			acc += seg
	WorldManager.add_polyline(pts, "both", bid)
	for cap in WorldManager.curve_cap_blocks(pts, bid):
		WorldManager.free_blocks.append(cap)

func _ready() -> void:
	GameState.battle_mode = false
	WorldManager.build_sample_room()
	# Floor so the player lands; camera (3x zoom) frames both curves
	for tx in range(2, 47):
		WorldManager.set_fg_tile(tx, 14, 5000)
	var h: PackedVector2Array = PackedVector2Array()
	for i in range(0, 177, 2):
		h.append(Vector2(160.0 + i, 120.0))
	_add_curve(h, 5058)
	var a: PackedVector2Array = PackedVector2Array()
	for i in range(0, 181, 2):
		a.append(Vector2(400.0 + i, 200.0 - sin(i * 0.017) * 55.0))
	_add_curve(a, 6084)
	WorldManager.build_curve_colliders()
	WorldManager.spawn_points[0] = Vector2(22, 12)
	var game: Node = (load("res://scenes/world/game.tscn") as PackedScene).instantiate()
	game._world_ready = true
	add_child(game)
	await get_tree().create_timer(1.4).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://curve_caps.png")
	print("CURVE CAPS SHOT SAVED")
	get_tree().quit(0)
