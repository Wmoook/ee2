extends Node
## Curve ENDS are ENTIRE blocks: a square cap free block sits flush against
## each ribbon end. This proves (1) the ball RESTS on the cap, (2) rolling
## along the curve carries the ball OVER the cap and off its outer face with
## no invisible wall, (3) pushing into the end face stops with the ball's
## side flush against the visible block, (4) open air past the cap is open,
## (5) heal_curve_caps() regenerates missing caps (capless-era worlds).

var physics: EEPhysics

func _tile_solid(tx: int, ty: int) -> bool:
	return WorldManager.is_solid_at(tx, ty)

func _tick_n(n: int, ix: int = 0) -> void:
	for _i in range(n):
		physics.tick(ix, 0, false, false)

func _reset(cx: float, cy: float) -> void:
	physics.x = cx - 8.0
	physics.y = cy - 8.0
	physics._speedX = 0.0
	physics._speedY = 0.0

func _ready() -> void:
	WorldManager.init_empty_world(120, 80)
	# Floor row (top at y=512) so the ball can roll INTO the cap end face,
	# plus a wall at x=720 so the roll-off test ends in a deterministic spot
	for tx in range(30, 61):
		WorldManager.set_fg_tile(tx, 32, 5000)
	WorldManager.set_fg_tile(45, 31, 5000)
	# Straight horizontal curve half-buried in the floor: centerline y=504,
	# exactly 320px = 20 whole tiles, ends at x=620
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(0, 321, 2):
		pts.append(Vector2(300.0 + i, 504.0))
	WorldManager.add_polyline(pts, "both", 5058)
	var caps: Array = WorldManager.curve_cap_blocks(pts, 5058)
	for cap in caps:
		WorldManager.free_blocks.append(cap)
	WorldManager.build_curve_colliders()
	# End cap spans x 619.7..635.7, y 496..512 (an entire block past the cut)
	var cap_face: float = 619.7 + 16.0
	var fails: int = 0
	physics = EEPhysics.new()
	physics.set_collides_fn(Callable(self, "_tile_solid"))
	# 1) Drop centered over the end cap — must REST ON the cap top (y=496)
	_reset(627.7, 448.0)
	_tick_n(600)
	if absf((physics.y + 16.0) - 496.0) > 1.5:
		fails += 1
		print("FAIL cap rest: ball bottom=%.1f want 496.0" % (physics.y + 16.0))
	else:
		print("pass: rests ON the end cap (bottom=%.1f)" % (physics.y + 16.0))
	# 2) Roll right from mid-curve: over the cap, off its outer face, onto
	# the floor — NO invisible wall anywhere near the end
	_reset(460.0, 480.0)
	_tick_n(200)  # settle onto the curve top
	_tick_n(700, 1)  # hold right until pinned against the far wall
	var went_past: bool = physics.x + 8.0 > cap_face + 20.0
	var on_floor: bool = absf((physics.y + 16.0) - 512.0) < 1.5
	if not (went_past and on_floor):
		fails += 1
		print("FAIL roll-off: center_x=%.1f bottom=%.1f (want past %.1f, bottom 512)" % [physics.x + 8.0, physics.y + 16.0, cap_face + 20.0])
	else:
		print("pass: rolls over the cap and off the end (x=%.1f)" % (physics.x + 8.0))
	# 3) Roll LEFT along the floor into the cap end face — the ball's side
	# must touch the visible block face (flush within 1px)
	_reset(700.0, 504.0)
	_tick_n(600, -1)
	if absf(physics.x - cap_face) > 1.0:
		fails += 1
		print("FAIL flush: ball left edge=%.2f want %.2f" % [physics.x, cap_face])
	else:
		print("pass: side of ball flush on cap face (edge=%.2f face=%.2f)" % [physics.x, cap_face])
	# 4) Drop in open air past the cap — must fall to the floor, never hang
	# at cap height on phantom collision
	_reset(680.0, 448.0)
	_tick_n(600)
	if absf((physics.y + 16.0) - 512.0) > 1.5:
		fails += 1
		print("FAIL open air: ball bottom=%.1f want 512.0 (floor)" % (physics.y + 16.0))
	else:
		print("pass: open air past the cap is open (fell to floor)")
	# 5) Delete both caps (capless-era world) — heal must regenerate them
	var fi: int = WorldManager.free_blocks.size() - 1
	while fi >= 0:
		if WorldManager.free_blocks[fi].get("is_cap", false):
			WorldManager.free_blocks.remove_at(fi)
		fi -= 1
	WorldManager.heal_curve_caps()
	var healed: int = 0
	for fb in WorldManager.free_blocks:
		if fb.get("is_cap", false):
			for cap in caps:
				if ((fb.pos as Vector2)).distance_to(cap.pos as Vector2) < 1.0:
					healed += 1
	var count_after: int = WorldManager.free_blocks.size()
	WorldManager.heal_curve_caps()  # idempotent: second run changes nothing
	if healed != 2 or WorldManager.free_blocks.size() != count_after:
		fails += 1
		print("FAIL heal: regenerated=%d (want 2), size %d -> %d" % [healed, count_after, WorldManager.free_blocks.size()])
	else:
		print("pass: heal regenerates both caps, idempotent")
	print("CURVE END TEST: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)
