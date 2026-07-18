class_name CurveSolver
extends RefCounted
## Curve (polyline) collision solver — substepped movement + contact velocity clipping.
##
## Replaces the old push-out/CCD/wedge-state-machine approach with real physics:
##
##   * The player is a point (its center) and every polyline centerline is a
##     capsule of radius 16.0px (8 player half-size + 8 curve visual half —
##     curve tiles are EXACTLY block-sized).
##     This is exactly the hitbox the old code enforced, minus its edge cases.
##   * Movement is split into substeps small enough (<= 2px per axis) that a
##     substep can never carry the center from one side of a centerline to the
##     other — tunneling/clip-through at high speed is geometrically impossible.
##   * Grid-tile stepping runs inside each substep with the exact EE algorithm
##     (_step_position), so tile feel is unchanged. Away from curves a single
##     full-size step runs, i.e. behavior is bit-identical to plain EE physics.
##   * On contact, velocity loses only its into-surface component (the same rule
##     EE tile physics applies on floors/walls, generalized to any angle), so
##     momentum along the curve is preserved and rolling feels like EE.
##   * V-junctions (wedge points) need no special cases: both arms contribute
##     contacts, a 2-contact solve places the ball exactly at the wedge point,
##     and clipping against both normals brings it to rest. Jumping out works
##     because the combined contact normal opposes gravity -> grounded.

const RADIUS: float = 16.0           # 8 (player half) + 8 (curve visual half)
const TOUCH: float = 0.25            # Separation band that still counts as contact
const SUBSTEP: float = 2.0           # Max per-axis movement per substep (px)
const MAX_SUBSTEPS: int = 12
const RESOLVE_PASSES: int = 5
const BRANCH_GAP: int = 20           # Segment index gap = different branch of same poly
const PUSH_CAP: float = 6.0          # Max position correction per resolve pass


static func tick_move(p) -> void:
	## Full movement for one physics tick: EE tile stepping + curve contacts.
	if p.is_god_mode or not _near_curves_swept(p):
		p._step_position()
		return
	# Movement this tick is speed * EE_TICK_FRAC px per axis.
	var move_max: float = maxf(absf(p._speedX), absf(p._speedY)) * p.EE_TICK_FRAC
	var steps: int = clampi(int(ceil(move_max / SUBSTEP)), 1, MAX_SUBSTEPS)
	var frac: float = 1.0 / float(steps)
	for _i in range(steps):
		var prev_x: float = p.x
		var prev_y: float = p.y
		p._step_position(frac)
		resolve_and_clip(p, prev_x, prev_y)


static func finalize(p) -> void:
	## After line/free-block collisions moved the player: re-enforce the capsule
	## constraint and derive grounding/valley/wedge flags from the contact set.
	if p.is_god_mode:
		return
	if not _near_curves_point(p):
		return
	var contacts: Array = resolve_and_clip(p, p._pre_step_x, p._pre_step_y)
	_apply_contact_flags(p, contacts)


static func resolve_and_clip(p, prev_x: float, prev_y: float) -> Array:
	## Push the player center out of all capsules (simultaneous 2-contact solve),
	## then clip velocity against every touching contact. Returns final contacts.
	## prev_x/prev_y: last known-good top-left position (side reference + revert
	## target for the degenerate dead-pinch case).
	var ref_cx: float = prev_x + 8.0
	var ref_cy: float = prev_y + 8.0
	var contacts: Array = []
	for _pass in range(RESOLVE_PASSES):
		contacts = gather_contacts(p.x + 8.0, p.y + 8.0, ref_cx, ref_cy)
		var ca: Dictionary = {}
		var cb: Dictionary = {}
		for c in contacts:
			if c.depth <= 0.01:
				continue
			if ca.is_empty() or c.depth > ca.depth:
				cb = ca
				ca = c
			elif cb.is_empty() or c.depth > cb.depth:
				cb = c
		if ca.is_empty():
			break
		var push: Vector2
		if not cb.is_empty():
			var na: Vector2 = ca.n
			var nb: Vector2 = cb.n
			var dot_ab: float = na.dot(nb)
			if dot_ab < -0.985:
				# Perfectly opposed contacts: dead pinch (inside the overlap zone
				# of a V). Undo this substep and stop — wedge surfaces are solid.
				p.x = prev_x
				p.y = prev_y
				p._speedX = 0.0
				p._speedY = 0.0
				return gather_contacts(p.x + 8.0, p.y + 8.0, ref_cx, ref_cy)
			if dot_ab > 0.985:
				push = na * ca.depth
			else:
				# Solve push = a*na + b*nb so BOTH contacts resolve exactly:
				# push.dot(na) = depth_a and push.dot(nb) = depth_b.
				var inv: float = 1.0 / (1.0 - dot_ab * dot_ab)
				var wa: float = maxf((ca.depth - dot_ab * cb.depth) * inv, 0.0)
				var wb: float = maxf((cb.depth - dot_ab * ca.depth) * inv, 0.0)
				push = na * wa + nb * wb
		else:
			push = ca.n * ca.depth
		var plen: float = push.length()
		if plen < 0.0001:
			break
		if plen > PUSH_CAP:
			push *= PUSH_CAP / plen
		# Never push into grid tiles: a curve/tile squeeze acts like a wall.
		var nx: float = p.x + push.x
		var ny: float = p.y + push.y
		if not p._collides_px(nx, ny):
			p.x = nx
			p.y = ny
		elif not p._collides_px(nx, p.y):
			p.x = nx
		elif not p._collides_px(p.x, ny):
			p.y = ny
		else:
			# Fully squeezed between curve and tiles: stop motion into the curve.
			var vsq: Vector2 = Vector2(p._speedX, p._speedY)
			var pn: Vector2 = push / plen
			var into_sq: float = vsq.dot(pn)
			if into_sq < 0.0:
				vsq -= pn * into_sq
				p._speedX = vsq.x
				p._speedY = vsq.y
			break
	# Velocity clipping: remove into-surface components only. Tangential
	# momentum is preserved — the same rule EE tile collisions apply on
	# floors/walls, generalized to arbitrary surface angles.
	var vx: float = p._speedX
	var vy: float = p._speedY
	for _cp in range(2):
		for c in contacts:
			if c.depth < -TOUCH:
				continue
			var into: float = vx * c.n.x + vy * c.n.y
			if into < 0.0:
				vx -= c.n.x * into
				vy -= c.n.y * into
	p._speedX = vx
	p._speedY = vy
	return contacts


static func gather_contacts(cx: float, cy: float, ref_x: float, ref_y: float) -> Array:
	## Contacts between the player center and all polyline capsules.
	## Per polyline: the closest segment, plus (for sharp V/U drawn as a single
	## stroke) the closest segment of a genuinely different branch.
	## ref_x/ref_y: recent known-good center, used to orient normals when the
	## center is suspiciously deep so resolution never flips sides.
	var out: Array = []
	var max_d: float = RADIUS + TOUCH
	for pi in range(WorldManager.polylines.size()):
		var poly: Dictionary = WorldManager.polylines[pi]
		if poly.get("render_only", false):
			continue
		# bbox is pre-padded by 24px (> RADIUS + TOUCH)
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		if cx < bb_min.x or cx > bb_max.x or cy < bb_min.y or cy > bb_max.y:
			continue
		var pts: PackedVector2Array = poly.points
		var shash: Dictionary = poly.get("spatial_hash", {})
		var cs: int = shash.get("cell_size", 32)
		var gx: int = int(floor(cx / cs))
		var gy: int = int(floor(cy / cs))
		var best_d: float = 999999.0
		var best_si: int = -1
		var best_on: Vector2 = Vector2.ZERO
		var sec_d: float = 999999.0
		var sec_si: int = -1
		var sec_on: Vector2 = Vector2.ZERO
		var checked: Dictionary = {}
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var key: int = (gx + dx) * 10000 + (gy + dy)
				if not shash.has(key):
					continue
				for si in shash[key]:
					if checked.has(si):
						continue
					checked[si] = true
					if si >= pts.size() - 1:
						continue
					var sa: Vector2 = pts[si]
					var ab: Vector2 = pts[si + 1] - sa
					var t: float = clampf((Vector2(cx, cy) - sa).dot(ab) / maxf(ab.dot(ab), 0.001), 0.0, 1.0)
					var on_pt: Vector2 = sa + ab * t
					var d: float = Vector2(cx, cy).distance_to(on_pt)
					if d < best_d:
						if best_si >= 0 and abs(si - best_si) > BRANCH_GAP and best_d < sec_d:
							sec_d = best_d
							sec_si = best_si
							sec_on = best_on
						best_d = d
						best_si = si
						best_on = on_pt
					elif best_si >= 0 and abs(si - best_si) > BRANCH_GAP and d < sec_d:
						sec_d = d
						sec_si = si
						sec_on = on_pt
		if best_si < 0 or best_d >= max_d:
			continue
		out.append(_make_contact(cx, cy, ref_x, ref_y, best_d, best_on, pi))
		if sec_si >= 0 and sec_d < max_d and abs(sec_si - best_si) > BRANCH_GAP and sec_on.distance_to(best_on) > 6.0:
			out.append(_make_contact(cx, cy, ref_x, ref_y, sec_d, sec_on, pi))
	return out


static func _make_contact(cx: float, cy: float, ref_x: float, ref_y: float, d: float, on_pt: Vector2, pi: int) -> Dictionary:
	## Radial capsule normal: from closest centerline point toward the player.
	## Handles segment interiors, sharp corners and endpoints (rounded) uniformly.
	var n: Vector2
	if d > 0.05:
		n = (Vector2(cx, cy) - on_pt) / d
		# Suspiciously deep (an external push moved us near/past the centerline):
		# orient by the reference position so we always exit the side we came from.
		if d < 8.0:
			var ref_side: Vector2 = Vector2(ref_x, ref_y) - on_pt
			if ref_side.length() > 0.5 and ref_side.dot(n) < 0.0:
				n = -n
	else:
		var ref_side2: Vector2 = Vector2(ref_x, ref_y) - on_pt
		n = ref_side2.normalized() if ref_side2.length() > 0.05 else Vector2(0, -1)
	return {"n": n, "depth": RADIUS - d, "pi": pi}


static func _apply_contact_flags(p, contacts: Array) -> void:
	## Grounding / valley / wedge state from the final contact set.
	if contacts.is_empty():
		return
	var g: Vector2 = Vector2(p.mox, p.moy)
	var ghat: Vector2 = g.normalized() if g.length() > 0.01 else Vector2(0, 1)
	var that: Vector2 = Vector2(-ghat.y, ghat.x)
	var sum_n: Vector2 = Vector2.ZERO
	var best_floor_n: Vector2 = Vector2.ZERO
	var best_floor_ag: float = -2.0
	var tan_min: float = 999.0
	var tan_max: float = -999.0
	var touching: int = 0
	for c in contacts:
		if c.depth < -TOUCH:
			continue
		touching += 1
		sum_n += c.n
		var ag: float = -c.n.dot(ghat)
		tan_min = minf(tan_min, c.n.dot(that))
		tan_max = maxf(tan_max, c.n.dot(that))
		if ag > best_floor_ag:
			best_floor_ag = ag
			best_floor_n = c.n
		if ag >= 0.05:
			p.on_rotated_block = true
		if ag > 0.35:
			p.is_grounded = true
			if ag > 0.45:
				p._jump_cooldown = 0
				p._coyote_ticks = p.COYOTE_TICKS
	if best_floor_ag >= 0.05:
		p._surface_normal = best_floor_n
	# V-junction (wedge point): 2+ touching contacts opposing along the walk
	# axis whose combined normal opposes gravity -> the ball is cradled.
	if touching >= 2 and tan_min < -0.05 and tan_max > 0.05:
		var bis: Vector2 = sum_n.normalized() if sum_n.length() > 0.05 else -ghat
		if -bis.dot(ghat) > 0.3:
			p.in_valley = true
			p.is_grounded = true
			p.on_rotated_block = true
			p._surface_normal = bis
			p._jump_cooldown = 0
			p._coyote_ticks = p.COYOTE_TICKS
			if absf(p._speedX) + absf(p._speedY) < 0.8:
				p.is_wedged = true


static func _near_curves_swept(p) -> bool:
	## Broad phase: does this tick's movement come anywhere near a polyline?
	## (bboxes are pre-padded by 24px > capsule radius)
	if WorldManager.polylines.is_empty():
		return false
	var x0: float = p.x + 8.0
	var y0: float = p.y + 8.0
	var x1: float = x0 + p._speedX * p.EE_TICK_FRAC
	var y1: float = y0 + p._speedY * p.EE_TICK_FRAC
	var mnx: float = minf(x0, x1)
	var mxx: float = maxf(x0, x1)
	var mny: float = minf(y0, y1)
	var mxy: float = maxf(y0, y1)
	for poly in WorldManager.polylines:
		if poly.get("render_only", false):
			continue
		if mxx < poly.bbox_min.x or mnx > poly.bbox_max.x or mxy < poly.bbox_min.y or mny > poly.bbox_max.y:
			continue
		return true
	return false


static func _near_curves_point(p) -> bool:
	if WorldManager.polylines.is_empty():
		return false
	var cx: float = p.x + 8.0
	var cy: float = p.y + 8.0
	for poly in WorldManager.polylines:
		if poly.get("render_only", false):
			continue
		if cx < poly.bbox_min.x or cx > poly.bbox_max.x or cy < poly.bbox_min.y or cy > poly.bbox_max.y:
			continue
		return true
	return false
