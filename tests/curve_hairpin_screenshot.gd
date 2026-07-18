extends Node2D
## Hairpin/cusp render check: a curve that goes out and REVERSES back must
## render a smooth ROUNDED turn (round join), not a needle point.

func _ready() -> void:
	WorldManager.init_empty_world(400, 200)
	var pts: PackedVector2Array = PackedVector2Array()
	var x: float = 200.0
	while x < 1200.0:
		pts.append(Vector2(x, 300.0 + (x - 200.0) * 0.02))
		x += 2.0
	x = 1200.0
	while x > 250.0:
		pts.append(Vector2(x, 322.0 + (1200.0 - x) * 0.11))
		x -= 2.0
	WorldManager.add_polyline(pts, "both", 5058)
	for cap in WorldManager.curve_cap_blocks(pts, 5058):
		WorldManager.free_blocks.append(cap)
	WorldManager.build_curve_colliders()
	var r: Node2D = preload("res://scripts/world/world_renderer.gd").new()
	add_child(r)
	var cam: Camera2D = Camera2D.new()
	cam.position = Vector2(1000, 360)
	cam.zoom = Vector2(1.6, 1.6)
	add_child(cam)
	cam.make_current()
	await get_tree().create_timer(1.4).timeout
	get_viewport().get_texture().get_image().save_png("user://curve_hairpin.png")
	print("HAIRPIN SHOT SAVED")
	get_tree().quit(0)
