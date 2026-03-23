extends Node

signal world_loaded()
signal tile_changed(x: int, y: int, block_type: int)
signal bg_tile_changed(x: int, y: int, block_type: int)

var fg_tiles: Array = []
var bg_tiles: Array = []
var fg_rotations: Array = []  # Rotation in degrees per tile (0, 45, 90, ...)
var world_width: int = 50
var world_height: int = 30
var dynamic_objects: Dictionary = {}
var spawn_points: Array[Vector2] = []
var key_timers: Dictionary = {}

# Freeform lines: smooth diagonal ramps not bound to grid
# Each line: {start: Vector2, end: Vector2, color: Color, width: float}
var lines: Array = []
signal lines_changed()

# Free blocks: rotated/off-grid blocks, not bound to tile array
# Each: {pos: Vector2 (pixels), id: int, rotation: float (degrees), group: int (-1=none)}
var free_blocks: Array = []
signal free_blocks_changed()

# Groups: block groups with properties
# Each: {id: int, name: String}
var block_groups: Array = []
var _next_group_id: int = 1
var active_group_filter: int = 0  # 0 = All, >0 = specific group ID

# Polyline spline colliders: smooth curves with interpolated normals
# Each: {points: PackedVector2Array, normals: Array[Vector2], side: String,
#         bbox_min: Vector2, bbox_max: Vector2}
var polylines: Array = []
signal polylines_changed()

# Gravity zones (circular areas with inward gravity)
var gravity_zones = preload("res://scripts/world/gravity_zone_manager.gd").new()

func create_group(name: String = "") -> int:
	var gid: int = _next_group_id
	_next_group_id += 1
	if name.is_empty():
		name = "Group %d" % gid
	block_groups.append({"id": gid, "name": name})
	return gid

func get_group(gid: int) -> Dictionary:
	for g in block_groups:
		if g.id == gid:
			return g
	return {}

func remove_group(gid: int) -> void:
	for i in range(block_groups.size()):
		if block_groups[i].id == gid:
			block_groups.remove_at(i)
			# Unassign blocks from this group
			for fb in free_blocks:
				if fb.get("group", -1) == gid:
					fb["group"] = -1
			break

func add_polyline(points: PackedVector2Array, side: String = "top", block_id: int = 9) -> void:
	if points.size() < 2:
		return
	# Compute per-vertex normals by averaging adjacent segment normals
	var vert_normals: Array = []
	var seg_count: int = points.size() - 1
	var seg_normals: Array = []
	# Determine consistent normal direction from first segment
	var first_dir: Vector2 = (points[1] - points[0]).normalized()
	var first_n: Vector2 = Vector2(-first_dir.y, first_dir.x)
	# For "top": first normal should point upward (y < 0)
	var flip_all: bool = false
	if side == "top" and first_n.y > 0:
		flip_all = true
	elif side == "bottom" and first_n.y < 0:
		flip_all = true
	for si in range(seg_count):
		var seg_dir: Vector2 = (points[si + 1] - points[si]).normalized()
		var seg_n: Vector2 = Vector2(-seg_dir.y, seg_dir.x)
		if flip_all:
			seg_n = -seg_n
		seg_normals.append(seg_n)
	# First vertex: use first segment normal
	vert_normals.append(seg_normals[0])
	# Interior vertices: average of adjacent segment normals
	for vi in range(1, points.size() - 1):
		var avg_n: Vector2 = (seg_normals[vi - 1] + seg_normals[vi]).normalized()
		if avg_n.length() < 0.01:
			avg_n = seg_normals[vi]
		vert_normals.append(avg_n)
	# Last vertex: use last segment normal
	vert_normals.append(seg_normals[seg_count - 1])
	# Compute bounding box with padding
	var bb_min: Vector2 = points[0]
	var bb_max: Vector2 = points[0]
	for pi in range(1, points.size()):
		bb_min.x = minf(bb_min.x, points[pi].x)
		bb_min.y = minf(bb_min.y, points[pi].y)
		bb_max.x = maxf(bb_max.x, points[pi].x)
		bb_max.y = maxf(bb_max.y, points[pi].y)
	var pad: float = 24.0  # Padding for player half-size + some margin
	bb_min -= Vector2(pad, pad)
	bb_max += Vector2(pad, pad)
	# Pre-compute render data
	var render_top: PackedVector2Array = PackedVector2Array()
	var render_bot: PackedVector2Array = PackedVector2Array()
	var render_dists: Array = [0.0]
	for ri in range(points.size()):
		render_top.append(points[ri] + vert_normals[ri] * 8.35)
		render_bot.append(points[ri] - vert_normals[ri] * 8.35)
		if ri > 0:
			render_dists.append(render_dists[ri - 1] + points[ri].distance_to(points[ri - 1]))
	# Pre-build mesh for instant rendering (zero per-frame cost)
	var mesh: ArrayMesh = null
	if points.size() >= 2:
		mesh = ArrayMesh.new()
		var verts: PackedVector2Array = PackedVector2Array()
		var uvs: PackedVector2Array = PackedVector2Array()
		# Get atlas UV coords for the block sprite
		var binfo: Dictionary = GameState.get_block_info(block_id) if block_id > 0 else {}
		var b_atlas: String = binfo.get("atlas", "blocks")
		var b_artoff: int = binfo.get("artoffset", 0)
		var b_chunk: int = 0
		var b_local: int = b_artoff
		# Estimate atlas size (will be corrected by renderer if needed)
		var atlas_w: float = 2512.0  # Default atlas width
		var atlas_h: float = 16.0
		var b_cols: int = int(atlas_w) / 16
		var b_sx: float = float((b_local % b_cols) * 16) / atlas_w
		var b_sy: float = float((b_local / b_cols) * 16) / atlas_h
		var b_sw: float = 16.0 / atlas_w
		var b_sh: float = 16.0 / atlas_h
		# Build quads
		var last_qi_d: float = 0.0
		for qi in range(1, points.size()):
			if render_dists[qi] - last_qi_d < 1.0 and qi < points.size() - 1:
				continue
			var t0: Vector2 = render_top[qi - 1]
			var t1: Vector2 = render_top[qi]
			var b0: Vector2 = render_bot[qi - 1]
			var b1: Vector2 = render_bot[qi]
			verts.append(t0); verts.append(t1); verts.append(b1)
			verts.append(t0); verts.append(b1); verts.append(b0)
			# UV mapped to correct sprite region in atlas
			uvs.append(Vector2(b_sx, b_sy)); uvs.append(Vector2(b_sx + b_sw, b_sy)); uvs.append(Vector2(b_sx + b_sw, b_sy + b_sh))
			uvs.append(Vector2(b_sx, b_sy)); uvs.append(Vector2(b_sx + b_sw, b_sy + b_sh)); uvs.append(Vector2(b_sx, b_sy + b_sh))
			last_qi_d = render_dists[qi]
		if verts.size() >= 3:
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			var v3: PackedVector3Array = PackedVector3Array()
			for v in verts:
				v3.append(Vector3(v.x, v.y, 0))
			arrays[Mesh.ARRAY_VERTEX] = v3
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	polylines.append({
		"points": points,
		"normals": vert_normals,
		"side": side,
		"block_id": block_id,
		"bbox_min": bb_min,
		"bbox_max": bb_max,
		"render_top": render_top,
		"render_bot": render_bot,
		"render_dists": render_dists,
		"mesh": mesh,
		"spatial_hash": _build_spatial_hash(points, 32)
	})
	polylines_changed.emit()

func _build_spatial_hash(pts: PackedVector2Array, cell_size: int) -> Dictionary:
	## Bucket segment indices into grid cells for O(1) lookup
	var hash: Dictionary = {}
	for si in range(pts.size() - 1):
		var ax: int = int(floor(pts[si].x / cell_size))
		var ay: int = int(floor(pts[si].y / cell_size))
		var bx: int = int(floor(pts[si + 1].x / cell_size))
		var by: int = int(floor(pts[si + 1].y / cell_size))
		for gx in range(mini(ax, bx), maxi(ax, bx) + 1):
			for gy in range(mini(ay, by), maxi(ay, by) + 1):
				var key: int = gx * 10000 + gy
				if not hash.has(key):
					hash[key] = []
				hash[key].append(si)
	hash["cell_size"] = cell_size
	return hash

func check_polyline_collision(px: float, py: float, pw: float, ph: float, prefer_normal: Vector2 = Vector2.ZERO, stick_poly: int = -1, exclude_poly: int = -1) -> Dictionary:
	## Check if axis-aligned box (px,py,pw,ph) collides with any polyline.
	## Returns {hit, push, normal, tangent, poly_idx} with interpolated normal at closest point.
	## stick_poly: when >= 0 and sandwiched, only collide with this polyline index.
	var result: Dictionary = {"hit": false, "push": Vector2.ZERO, "normal": Vector2(0, -1), "tangent": Vector2(1, 0), "poly_idx": -1, "seg": -1}
	var pcx: float = px + pw * 0.5
	var pcy: float = py + ph * 0.5
	var best_pen: float = -999.0  # Most positive = deepest penetration
	var _dbg_hits: Array = []  # DEBUG: track all polyline hits
	var _dbg_poly_idx: int = -1
	for poly in polylines:
		_dbg_poly_idx += 1
		if _dbg_poly_idx == exclude_poly:
			continue  # Skip excluded polyline (pass 2 excludes stick poly)
		# AABB broad phase
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		if px + pw < bb_min.x or px > bb_max.x or py + ph < bb_min.y or py > bb_max.y:
			continue
		var pts: PackedVector2Array = poly.points
		var norms: Array = poly.normals
		# Find nearest segment + detect self-intersection branches (brute force within bbox)
		var closest_seg: int = -1
		var closest_t: float = 0.0
		var closest_dist: float = 999999.0
		var second_seg: int = -1
		var second_t: float = 0.0
		var second_dist: float = 999999.0
		var eff_radius: float = 8.0
		var block_half: float = 8.5  # Match step_position threshold (8 + 8.5 = 16.5)
		for si in range(pts.size() - 1):
			var sa: Vector2 = pts[si]
			var sb: Vector2 = pts[si + 1]
			var ab: Vector2 = sb - sa
			var ap: Vector2 = Vector2(pcx, pcy) - sa
			var ab_dot: float = ab.dot(ab)
			var seg_t: float = clampf(ap.dot(ab) / maxf(ab_dot, 0.001), 0.0, 1.0)
			var on_pt: Vector2 = sa + ab * seg_t
			var dist: float = Vector2(pcx, pcy).distance_to(on_pt)
			if dist < closest_dist:
				if closest_seg >= 0 and abs(si - closest_seg) > 20:
					second_seg = closest_seg
					second_t = closest_t
					second_dist = closest_dist
				closest_dist = dist
				closest_seg = si
				closest_t = seg_t
			elif dist < second_dist and closest_seg >= 0 and abs(si - closest_seg) > 20:
				second_dist = dist
				second_seg = si
				second_t = seg_t
		if closest_seg < 0:
			continue
		# Self-intersection guard: if nearest segment push opposes prefer_normal
		# and there's a second branch nearby, use the second branch instead
		if second_seg >= 0 and prefer_normal.length() > 0.1:
			var seg_a1: Vector2 = pts[closest_seg]
			var seg_b1: Vector2 = pts[closest_seg + 1]
			var on1: Vector2 = seg_a1 + (seg_b1 - seg_a1) * closest_t
			var dir1: Vector2 = (Vector2(pcx, pcy) - on1).normalized()
			var seg_a2: Vector2 = pts[second_seg]
			var seg_b2: Vector2 = pts[second_seg + 1]
			var on2: Vector2 = seg_a2 + (seg_b2 - seg_a2) * second_t
			var dir2: Vector2 = (Vector2(pcx, pcy) - on2).normalized()
			# If nearest opposes our previous surface but second matches, use second
			if dir1.dot(prefer_normal) < 0.0 and dir2.dot(prefer_normal) > 0.0:
				closest_seg = second_seg
				closest_t = second_t
				closest_dist = second_dist
		# Interpolate normal at closest point on segment
		var interp_normal: Vector2 = (norms[closest_seg] * (1.0 - closest_t) + norms[closest_seg + 1] * closest_t).normalized()
		if interp_normal.length() < 0.01:
			interp_normal = norms[closest_seg]
		# Compute closest point on segment
		var seg_a: Vector2 = pts[closest_seg]
		var seg_b: Vector2 = pts[closest_seg + 1]
		var on_seg: Vector2 = seg_a + (seg_b - seg_a) * closest_t
		# Distance from player center to surface
		var to_player: Vector2 = Vector2(pcx, pcy) - on_seg
		var dist_to_line: float = to_player.length()
		# Push direction: use to_player normally, but when player has tunneled through
		# (center crossed the curve line), use the interpolated normal to push back correctly
		var push_dir: Vector2
		if dist_to_line < 0.01:
			push_dir = interp_normal
		elif dist_to_line < eff_radius:
			# Deep inside — player center past the curve surface. Use normal direction
			# matching the side the player SHOULD be on (prefer_normal or interp_normal)
			var to_norm: Vector2 = to_player.normalized()
			if prefer_normal.length() > 0.1 and to_norm.dot(prefer_normal) < 0.0:
				# Player is on wrong side relative to previous surface — flip push
				push_dir = -to_norm
			else:
				push_dir = to_norm
		else:
			push_dir = to_player.normalized()
		var penetration: float = minf((eff_radius + block_half) - dist_to_line, 8.0)
		if penetration > 0 and dist_to_line < eff_radius + block_half + 2.0:
			var seg_tangent: Vector2 = (seg_b - seg_a).normalized()
			_dbg_hits.append({"poly": _dbg_poly_idx, "seg": closest_seg, "pen": penetration, "dist": dist_to_line, "push_dir": push_dir, "on_seg": on_seg, "tangent": seg_tangent})
	# Select best hit: handle opposing curves (sandwich)
	if _dbg_hits.size() == 1:
		var h: Dictionary = _dbg_hits[0]
		result = {"hit": true, "push": h.push_dir * h.pen, "normal": h.push_dir, "tangent": h.tangent, "poly_idx": h.poly, "seg": h.seg}
	elif _dbg_hits.size() >= 2:
		# Detect sandwich: opposing normals OR deep penetration from different polylines
		# (deep pen = player center crossed curve line, push_dir may have flipped)
		var has_opposing: bool = false
		for i in range(_dbg_hits.size()):
			for j in range(i + 1, _dbg_hits.size()):
				if _dbg_hits[i].poly != _dbg_hits[j].poly:
					if _dbg_hits[i].push_dir.dot(_dbg_hits[j].push_dir) < -0.3:
						has_opposing = true
					# Deep pen from one + any hit from another = sandwich (push_dir flipped)
					elif _dbg_hits[i].pen > 12.0 or _dbg_hits[j].pen > 12.0:
						has_opposing = true
				if has_opposing:
					break
			if has_opposing:
				break
		if has_opposing and stick_poly >= 0:
			# Sandwich with known surface: ONLY collide with the stuck polyline
			var best_h: Dictionary = {}
			for h in _dbg_hits:
				if h.poly == stick_poly:
					best_h = h
					break
			if best_h.is_empty():
				# Stuck poly not in hits - use deepest as fallback
				best_h = _dbg_hits[0]
				for h in _dbg_hits:
					if h.pen > best_h.pen:
						best_h = h
			result = {"hit": true, "push": best_h.push_dir * best_h.pen, "normal": best_h.push_dir, "tangent": best_h.tangent, "poly_idx": best_h.poly, "seg": best_h.seg}
		elif has_opposing:
			# Sandwich but no stick: pick deepest (the surface player is closest to)
			var best_h: Dictionary = _dbg_hits[0]
			for h in _dbg_hits:
				if h.pen > best_h.pen:
					best_h = h
			result = {"hit": true, "push": best_h.push_dir * best_h.pen, "normal": best_h.push_dir, "tangent": best_h.tangent, "poly_idx": best_h.poly, "seg": best_h.seg}
		else:
			# Same-side hits: use deepest penetration (standard behavior)
			var best_h: Dictionary = _dbg_hits[0]
			for h in _dbg_hits:
				if h.pen > best_h.pen:
					best_h = h
			result = {"hit": true, "push": best_h.push_dir * best_h.pen, "normal": best_h.push_dir, "tangent": best_h.tangent, "poly_idx": best_h.poly, "seg": best_h.seg}
	return result

func enforce_polyline_hard_constraint(px: float, py: float, prev_px: float, prev_py: float, exclude_poly: int = -1) -> Dictionary:
	## Hard constraint: player center must be >= 16.35px from every polyline centerline.
	## Uses prev position to determine correct push side. No exceptions.
	## Returns {pushed: bool, x: float, y: float, normal: Vector2, tangent: Vector2}
	var cx: float = px + 8.0
	var cy: float = py + 8.0
	var prev_cx: float = prev_px + 8.0
	var prev_cy: float = prev_py + 8.0
	var min_dist: float = 16.5  # 8 player half + 8.35 curve visual half + 0.15 margin
	var total_push: Vector2 = Vector2.ZERO
	var best_normal: Vector2 = Vector2.ZERO
	var best_tangent: Vector2 = Vector2(1, 0)
	var pushed: bool = false
	var touching_polys: Dictionary = {}  # Track which polylines are within range
	# Run multiple iterations to handle multiple curves
	for _iter in range(4):
		var iter_push: Vector2 = Vector2.ZERO
		var iter_pen: float = 0.0
		var _pidx: int = -1
		for poly in polylines:
			_pidx += 1
			if _pidx == exclude_poly:
				continue
			var bb_min: Vector2 = poly.bbox_min
			var bb_max: Vector2 = poly.bbox_max
			if cx + 8 < bb_min.x - 20 or cx - 8 > bb_max.x + 20 or cy + 8 < bb_min.y - 20 or cy - 8 > bb_max.y + 20:
				continue
			var pts: PackedVector2Array = poly.points
			var norms: Array = poly.normals
			var closest_seg: int = -1
			var closest_t: float = 0.0
			var closest_dist: float = 999999.0
			for si in range(pts.size() - 1):
				var sa: Vector2 = pts[si]
				var sb: Vector2 = pts[si + 1]
				var ab: Vector2 = sb - sa
				var ap: Vector2 = Vector2(cx, cy) - sa
				var ab_dot: float = ab.dot(ab)
				var seg_t: float = clampf(ap.dot(ab) / maxf(ab_dot, 0.001), 0.0, 1.0)
				var on_pt: Vector2 = sa + ab * seg_t
				var dist: float = Vector2(cx, cy).distance_to(on_pt)
				if dist < closest_dist:
					closest_dist = dist
					closest_seg = si
					closest_t = seg_t
			if closest_seg < 0 or closest_dist >= min_dist:
				continue
			touching_polys[_pidx] = true
			# Penetration found — compute push direction from PREVIOUS position
			var seg_a: Vector2 = pts[closest_seg]
			var seg_b: Vector2 = pts[closest_seg + 1]
			var on_seg: Vector2 = seg_a + (seg_b - seg_a) * closest_t
			var to_player: Vector2 = Vector2(cx, cy) - on_seg
			var to_prev: Vector2 = Vector2(prev_cx, prev_cy) - on_seg
			# Push direction: use interpolated normal, sign from previous position
			var interp_n: Vector2 = (norms[closest_seg] * (1.0 - closest_t) + norms[closest_seg + 1] * closest_t).normalized()
			if interp_n.length() < 0.01:
				interp_n = norms[closest_seg]
			var push_dir: Vector2
			if to_prev.length() > 0.5:
				# Use normal direction that matches the side the player came from
				push_dir = interp_n if to_prev.dot(interp_n) > 0 else -interp_n
			elif to_player.length() > 0.01:
				push_dir = interp_n if to_player.dot(interp_n) > 0 else -interp_n
			else:
				push_dir = interp_n
			var pen: float = min_dist - closest_dist
			if pen > iter_pen:
				iter_pen = pen
				iter_push = push_dir * pen
				var seg_tangent: Vector2 = (seg_b - seg_a).normalized()
				best_normal = push_dir
				best_tangent = seg_tangent
		if iter_pen < 0.01:
			break
		cx += iter_push.x
		cy += iter_push.y
		total_push += iter_push
		pushed = true
	return {"pushed": pushed, "x": cx - 8.0, "y": cy - 8.0, "push": total_push, "normal": best_normal, "tangent": best_tangent, "poly_count": touching_polys.size()}

func check_curve_wall(cx: float, cy: float, stick_poly: int, stick_arc: float, arc_exclude: float = 40.0) -> Dictionary:
	## Check if player center (cx,cy) is within 16.5px of any "wall" polyline segment.
	## Uses arc-length distance to exclude the riding zone on the stick poly.
	## stick_poly=-1 means no exclusion (everything is a wall).
	## Returns {blocked: bool, push: Vector2}
	var min_dist: float = 16.5
	var best_pen: float = 0.0
	var best_push: Vector2 = Vector2.ZERO
	var _pidx: int = -1
	for poly in polylines:
		_pidx += 1
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		if cx < bb_min.x - 20 or cx > bb_max.x + 20 or cy < bb_min.y - 20 or cy > bb_max.y + 20:
			continue
		var pts: PackedVector2Array = poly.points
		var rd: Array = poly.render_dists
		var shash: Dictionary = poly.get("spatial_hash", {})
		var cs: int = shash.get("cell_size", 32)
		var gx: int = int(floor(cx / cs))
		var gy: int = int(floor(cy / cs))
		var checked: Dictionary = {}
		for dx2 in range(-2, 3):
			for dy2 in range(-2, 3):
				var key: int = (gx + dx2) * 10000 + (gy + dy2)
				if not shash.has(key):
					continue
				for si in shash[key]:
					if checked.has(si):
						continue
					checked[si] = true
					# Arc-length exclusion: skip segments in riding zone on stick poly
					if _pidx == stick_poly and stick_arc >= 0 and si < rd.size():
						if absf(rd[si] - stick_arc) < arc_exclude:
							continue
					var sa: Vector2 = pts[si]
					var sb: Vector2 = pts[si + 1]
					var ab: Vector2 = sb - sa
					var ap: Vector2 = Vector2(cx, cy) - sa
					var ab_dot: float = ab.dot(ab)
					var seg_t: float = clampf(ap.dot(ab) / maxf(ab_dot, 0.001), 0.0, 1.0)
					var on_pt: Vector2 = sa + ab * seg_t
					var dist: float = Vector2(cx, cy).distance_to(on_pt)
					if dist < min_dist:
						var pen: float = min_dist - dist
						if pen > best_pen:
							best_pen = pen
							var to_p: Vector2 = Vector2(cx, cy) - on_pt
							best_push = to_p.normalized() * pen if to_p.length() > 0.01 else Vector2(0, -1) * pen
	return {"blocked": best_pen > 0.01, "push": best_push}

func dist_to_wall_segments(cx: float, cy: float, stick_poly: int, stick_seg: int) -> float:
	## Distance to nearest "wall" segment — excludes ±20 segments around stick_seg on stick_poly.
	var best: float = 99999.0
	var _pidx: int = -1
	for poly in polylines:
		_pidx += 1
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		if cx < bb_min.x - 20 or cx > bb_max.x + 20 or cy < bb_min.y - 20 or cy > bb_max.y + 20:
			continue
		var pts: PackedVector2Array = poly.points
		for si in range(pts.size() - 1):
			if _pidx == stick_poly and stick_seg >= 0 and abs(si - stick_seg) <= 20:
				continue
			var sa: Vector2 = pts[si]
			var sb: Vector2 = pts[si + 1]
			var ab: Vector2 = sb - sa
			var ap: Vector2 = Vector2(cx, cy) - sa
			var ab_dot: float = ab.dot(ab)
			var seg_t: float = clampf(ap.dot(ab) / maxf(ab_dot, 0.001), 0.0, 1.0)
			var on_pt: Vector2 = sa + ab * seg_t
			var dist: float = Vector2(cx, cy).distance_to(on_pt)
			if dist < best:
				best = dist
	return best

func find_nearest_polyline_segment(cx: float, cy: float, exclude_poly: int = -1) -> Dictionary:
	## Returns {dist, point, seg_a, seg_b, poly_idx} of nearest segment.
	var best: Dictionary = {"dist": 99999.0, "point": Vector2.ZERO, "seg_a": Vector2.ZERO, "seg_b": Vector2.ZERO, "poly_idx": -1}
	var _pidx: int = -1
	for poly in polylines:
		_pidx += 1
		if _pidx == exclude_poly:
			continue
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		if cx < bb_min.x - 20 or cx > bb_max.x + 20 or cy < bb_min.y - 20 or cy > bb_max.y + 20:
			continue
		var pts: PackedVector2Array = poly.points
		for si in range(pts.size() - 1):
			var sa: Vector2 = pts[si]
			var sb: Vector2 = pts[si + 1]
			var ab: Vector2 = sb - sa
			var ap: Vector2 = Vector2(cx, cy) - sa
			var ab_dot: float = ab.dot(ab)
			var seg_t: float = clampf(ap.dot(ab) / maxf(ab_dot, 0.001), 0.0, 1.0)
			var on_pt: Vector2 = sa + ab * seg_t
			var dist: float = Vector2(cx, cy).distance_to(on_pt)
			if dist < best.dist:
				best = {"dist": dist, "point": on_pt, "seg_a": sa, "seg_b": sb, "poly_idx": _pidx}
	return best

func dist_to_nearest_polyline(cx: float, cy: float, exclude_poly: int = -1) -> float:
	## Returns the distance from point (cx,cy) to the nearest polyline segment, excluding one.
	## Uses brute force within bbox for reliability (spatial hash can miss edge cases).
	var best_dist: float = 99999.0
	var _pidx: int = -1
	for poly in polylines:
		_pidx += 1
		if _pidx == exclude_poly:
			continue
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		if cx < bb_min.x - 20 or cx > bb_max.x + 20 or cy < bb_min.y - 20 or cy > bb_max.y + 20:
			continue
		var pts: PackedVector2Array = poly.points
		for si in range(pts.size() - 1):
			var sa: Vector2 = pts[si]
			var sb: Vector2 = pts[si + 1]
			# Quick AABB check per segment
			if cx < minf(sa.x, sb.x) - 20 and cx > maxf(sa.x, sb.x) + 20:
				continue
			if cy < minf(sa.y, sb.y) - 20 and cy > maxf(sa.y, sb.y) + 20:
				continue
			var ab: Vector2 = sb - sa
			var ap: Vector2 = Vector2(cx, cy) - sa
			var ab_dot: float = ab.dot(ab)
			var seg_t: float = clampf(ap.dot(ab) / maxf(ab_dot, 0.001), 0.0, 1.0)
			var on_pt: Vector2 = sa + ab * seg_t
			var dist: float = Vector2(cx, cy).distance_to(on_pt)
			if dist < best_dist:
				best_dist = dist
	return best_dist

func is_near_polyline(cx: float, cy: float, threshold: float, exclude_poly: int = -1) -> bool:
	## Check if point (cx,cy) is within threshold of any polyline segment.
	## exclude_poly: skip this polyline index (for stick poly).
	var _pidx: int = -1
	for poly in polylines:
		_pidx += 1
		if _pidx == exclude_poly:
			continue
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		if cx < bb_min.x - threshold or cx > bb_max.x + threshold or cy < bb_min.y - threshold or cy > bb_max.y + threshold:
			continue
		var shash: Dictionary = poly.get("spatial_hash", {})
		var cs: int = shash.get("cell_size", 32)
		var gx: int = int(floor(cx / cs))
		var gy: int = int(floor(cy / cs))
		var checked: Dictionary = {}
		for dx2 in range(-1, 2):
			for dy2 in range(-1, 2):
				var key: int = (gx + dx2) * 10000 + (gy + dy2)
				if not shash.has(key):
					continue
				for si in shash[key]:
					if checked.has(si):
						continue
					checked[si] = true
					var sa: Vector2 = poly.points[si]
					var sb: Vector2 = poly.points[si + 1]
					var ab: Vector2 = sb - sa
					var ap: Vector2 = Vector2(cx, cy) - sa
					var ab_dot: float = ab.dot(ab)
					var seg_t: float = clampf(ap.dot(ab) / maxf(ab_dot, 0.001), 0.0, 1.0)
					var on_pt: Vector2 = sa + ab * seg_t
					var dist: float = Vector2(cx, cy).distance_to(on_pt)
					if dist < threshold:
						return true
	return false

func does_step_cross_polyline(x1: float, y1: float, x2: float, y2: float) -> bool:
	## Fast check: does a small step from (x1,y1) to (x2,y2) cross any polyline segment?
	## Coordinates are player CENTER positions.
	if polylines.is_empty():
		return false
	for poly in polylines:
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		if maxf(x1, x2) < bb_min.x - 10 or minf(x1, x2) > bb_max.x + 10:
			continue
		if maxf(y1, y2) < bb_min.y - 10 or minf(y1, y2) > bb_max.y + 10:
			continue
		var shash: Dictionary = poly.get("spatial_hash", {})
		var cs: int = shash.get("cell_size", 32)
		var mid_x: float = (x1 + x2) * 0.5
		var mid_y: float = (y1 + y2) * 0.5
		var gx: int = int(floor(mid_x / cs))
		var gy: int = int(floor(mid_y / cs))
		var checked: Dictionary = {}
		for dx2 in range(-1, 2):
			for dy2 in range(-1, 2):
				var key: int = (gx + dx2) * 10000 + (gy + dy2)
				if not shash.has(key):
					continue
				for si in shash[key]:
					if checked.has(si):
						continue
					checked[si] = true
					var sa: Vector2 = poly.points[si]
					var sb: Vector2 = poly.points[si + 1]
					# 2D line segment intersection test
					var d1x: float = x2 - x1
					var d1y: float = y2 - y1
					var d2x: float = sb.x - sa.x
					var d2y: float = sb.y - sa.y
					var denom: float = d1x * d2y - d1y * d2x
					if absf(denom) < 0.0001:
						continue
					var d3x: float = sa.x - x1
					var d3y: float = sa.y - y1
					var t: float = (d3x * d2y - d3y * d2x) / denom
					var u: float = (d3x * d1y - d3y * d1x) / denom
					if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
						return true
	return false

func check_polyline_crossing(x1: float, y1: float, x2: float, y2: float, player_half: float = 8.0) -> Dictionary:
	## Check if the player movement path from (x1,y1) to (x2,y2) crosses any polyline.
	## Uses player center path. Returns {crossed, point, normal, tangent, poly_idx}
	## Tests against "thick" polyline (offset by player_half + curve_half on both sides).
	var result: Dictionary = {"crossed": false, "point": Vector2.ZERO, "normal": Vector2.ZERO, "tangent": Vector2.ZERO, "poly_idx": -1}
	var p1: Vector2 = Vector2(x1 + player_half, y1 + player_half)  # Player center start
	var p2: Vector2 = Vector2(x2 + player_half, y2 + player_half)  # Player center end
	var move_dir: Vector2 = p2 - p1
	var move_len: float = move_dir.length()
	if move_len < 0.1:
		return result
	var best_t: float = 2.0  # Earliest crossing (parametric t along movement)
	var _poly_idx: int = -1
	for poly in polylines:
		_poly_idx += 1
		var bb: Vector2 = poly.bbox_min
		var bx: Vector2 = poly.bbox_max
		# Broad phase: movement AABB vs polyline AABB (with margin)
		var m: float = 20.0
		if maxf(p1.x, p2.x) < bb.x - m or minf(p1.x, p2.x) > bx.x + m:
			continue
		if maxf(p1.y, p2.y) < bb.y - m or minf(p1.y, p2.y) > bx.y + m:
			continue
		var pts: PackedVector2Array = poly.points
		var norms: Array = poly.normals
		for si in range(pts.size() - 1):
			var sa: Vector2 = pts[si]
			var sb: Vector2 = pts[si + 1]
			# Line-segment intersection: does p1->p2 cross sa->sb?
			var d1: Vector2 = p2 - p1
			var d2: Vector2 = sb - sa
			var denom: float = d1.x * d2.y - d1.y * d2.x
			if absf(denom) < 0.001:
				continue  # Parallel
			var d3: Vector2 = sa - p1
			var t: float = (d3.x * d2.y - d3.y * d2.x) / denom  # Parameter along movement
			var u: float = (d3.x * d1.y - d3.y * d1.x) / denom  # Parameter along segment
			if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
				if t < best_t:
					best_t = t
					var seg_normal: Vector2 = (norms[si] * (1.0 - u) + norms[si + 1] * u).normalized()
					if seg_normal.length() < 0.01:
						seg_normal = norms[si]
					var seg_tangent: Vector2 = (sb - sa).normalized()
					result = {"crossed": true, "point": p1 + d1 * t, "normal": seg_normal, "tangent": seg_tangent, "poly_idx": _poly_idx, "t": t}
	return result

func remove_polyline_near(pos: Vector2, radius: float = 16.0) -> void:
	for i in range(polylines.size() - 1, -1, -1):
		var poly: Dictionary = polylines[i]
		var pts: PackedVector2Array = poly.points
		for pi in range(pts.size()):
			if pts[pi].distance_to(pos) < radius:
				polylines.remove_at(i)
				polylines_changed.emit()
				return

func _ready() -> void:
	pass

func init_empty_world(w: int = 50, h: int = 30) -> void:
	world_width = w
	world_height = h
	fg_tiles.clear()
	bg_tiles.clear()
	fg_rotations.clear()
	for y in range(world_height):
		var fg_row: Array = []
		fg_row.resize(world_width)
		fg_row.fill(0)
		fg_tiles.append(fg_row)
		var rot_row: Array = []
		rot_row.resize(world_width)
		rot_row.fill(0)
		fg_rotations.append(rot_row)
		var bg_row: Array = []
		bg_row.resize(world_width)
		bg_row.fill(0)
		bg_tiles.append(bg_row)
	# Place border walls as grid tiles (same collision as placed blocks)
	for x in range(world_width):
		fg_tiles[0][x] = 9
		fg_tiles[world_height - 1][x] = 9
	for y in range(1, world_height - 1):
		fg_tiles[y][0] = 9
		fg_tiles[y][world_width - 1] = 9
	spawn_points = [Vector2(3, 3)]

func get_tile(x: int, y: int) -> int:
	if x < 0 or x >= world_width or y < 0 or y >= world_height:
		return 9
	return fg_tiles[y][x]

func get_bg_tile(x: int, y: int) -> int:
	if x < 0 or x >= world_width or y < 0 or y >= world_height:
		return 0
	return bg_tiles[y][x]

func set_fg_tile(x: int, y: int, block_id: int) -> void:
	if x < 0 or x >= world_width or y < 0 or y >= world_height:
		return
	fg_tiles[y][x] = block_id
	tile_changed.emit(x, y, block_id)

func set_bg_tile(x: int, y: int, block_id: int) -> void:
	if x < 0 or x >= world_width or y < 0 or y >= world_height:
		return
	bg_tiles[y][x] = block_id
	bg_tile_changed.emit(x, y, block_id)

func set_tile(x: int, y: int, block_id: int) -> void:
	# In EE, action blocks (arrows, keys, doors, dots, etc.) go in foreground
	# even though items_map marks them as "decoration"
	var layer: String = GameState.get_block_layer(block_id)
	if layer == "background" and not GameState.is_action(block_id) and not GameState.is_key(block_id) and not GameState.is_door(block_id):
		set_bg_tile(x, y, block_id)
	else:
		set_fg_tile(x, y, block_id)

func get_rotation(x: int, y: int) -> int:
	if x < 0 or x >= world_width or y < 0 or y >= world_height:
		return 0
	return fg_rotations[y][x]

func set_rotation(x: int, y: int, degrees: int) -> void:
	if x < 0 or x >= world_width or y < 0 or y >= world_height:
		return
	fg_rotations[y][x] = degrees
	tile_changed.emit(x, y, fg_tiles[y][x])

func is_solid_at(tx: int, ty: int) -> bool:
	var bid: int = get_tile(tx, ty)
	if GameState.is_solid(bid):
		return true
	if GameState.is_door(bid):
		return _is_door_blocking(bid)
	return false

func _is_door_blocking(bid: int) -> bool:
	var now: int = Time.get_ticks_msec()
	match bid:
		23: return not _is_key_active("red")
		24: return not _is_key_active("green")
		25: return not _is_key_active("blue")
		26: return _is_key_active("red")
		27: return _is_key_active("green")
		28: return _is_key_active("blue")
	return false

func _is_key_active(color: String) -> bool:
	return key_timers.get(color, 0) > Time.get_ticks_msec()

func activate_key(color: String, duration_ms: int = 5000) -> void:
	key_timers[color] = Time.get_ticks_msec() + duration_ms

func get_spawn_point(index: int = 0) -> Vector2:
	if spawn_points.is_empty():
		return Vector2(3, 3)
	return spawn_points[index % spawn_points.size()]

func get_spawn_pixel(index: int = 0) -> Vector2:
	return get_spawn_point(index) * 16.0

func serialize_world() -> Dictionary:
	var fg_data: Array = []
	var bg_data: Array = []
	for y in range(world_height):
		for x in range(world_width):
			if fg_tiles[y][x] != 0:
				fg_data.append([x, y, fg_tiles[y][x]])
			if bg_tiles[y][x] != 0:
				bg_data.append([x, y, bg_tiles[y][x]])
	var rot_data: Array = []
	for y in range(world_height):
		for x in range(world_width):
			if fg_rotations[y][x] != 0:
				rot_data.append([x, y, fg_rotations[y][x]])
	var free_data: Array = []
	for fb in free_blocks:
		var fd: Dictionary = {"x": fb.pos.x, "y": fb.pos.y, "id": fb.id, "rot": fb.rotation}
		if fb.has("spin") and fb.spin != 0:
			fd["spin"] = fb.spin
			fd["px"] = fb.pivot.x
			fd["py"] = fb.pivot.y
		if fb.get("group", -1) >= 0:
			fd["group"] = fb.group
		free_data.append(fd)
	var line_data: Array = []
	for ln in lines:
		if not ln.has("_free"):
			line_data.append({"sx": ln.start.x, "sy": ln.start.y, "ex": ln.end.x, "ey": ln.end.y,
				"r": ln.color.r, "g": ln.color.g, "b": ln.color.b, "a": ln.color.a, "w": ln.width})
	var groups_data: Array = []
	for g in block_groups:
		groups_data.append({"id": g.id, "name": g.name})
	var poly_data: Array = []
	for poly in polylines:
		var pts_arr: Array = []
		for pt in poly.points:
			pts_arr.append([pt.x, pt.y])
		poly_data.append({"points": pts_arr, "side": poly.side})
	return {"width": world_width, "height": world_height, "fg": fg_data, "bg": bg_data,
		"rotations": rot_data, "free_blocks": free_data, "lines": line_data,
		"spawn_points": spawn_points.map(func(v): return [v.x, v.y]),
		"groups": groups_data, "polylines": poly_data,
		"gravity_zones": gravity_zones.serialize()}

func deserialize_world(data: Dictionary) -> void:
	world_width = data.get("width", 50)
	world_height = data.get("height", 30)
	init_empty_world(world_width, world_height)
	for entry in data.get("fg", []):
		if entry.size() >= 3:
			var x: int = int(entry[0]); var y: int = int(entry[1])
			if x >= 0 and x < world_width and y >= 0 and y < world_height:
				fg_tiles[y][x] = int(entry[2])
	for entry in data.get("bg", []):
		if entry.size() >= 3:
			var x: int = int(entry[0]); var y: int = int(entry[1])
			if x >= 0 and x < world_width and y >= 0 and y < world_height:
				bg_tiles[y][x] = int(entry[2])
	for entry in data.get("rotations", []):
		if entry.size() >= 3:
			var x: int = int(entry[0]); var y: int = int(entry[1])
			if x >= 0 and x < world_width and y >= 0 and y < world_height:
				fg_rotations[y][x] = int(entry[2])
	free_blocks.clear()
	for fb in data.get("free_blocks", []):
		var fbd: Dictionary = {"pos": Vector2(fb.x, fb.y), "id": int(fb.id), "rotation": float(fb.rot)}
		if fb.has("spin"):
			fbd["spin"] = float(fb.spin)
			fbd["pivot"] = Vector2(float(fb.get("px", fb.x + 8)), float(fb.get("py", fb.y + 8)))
		if fb.has("group"):
			fbd["group"] = int(fb.group)
		free_blocks.append(fbd)
	lines.clear()
	for ln in data.get("lines", []):
		lines.append({"start": Vector2(ln.sx, ln.sy), "end": Vector2(ln.ex, ln.ey),
			"color": Color(ln.r, ln.g, ln.b, ln.a), "width": float(ln.w)})
	spawn_points.clear()
	for sp in data.get("spawn_points", []):
		if sp.size() >= 2:
			spawn_points.append(Vector2(sp[0], sp[1]))
	if spawn_points.is_empty():
		spawn_points = [Vector2(3, 3)]
	block_groups.clear()
	_next_group_id = 1
	for g in data.get("groups", []):
		block_groups.append({"id": int(g.id), "name": str(g.name)})
		_next_group_id = maxi(_next_group_id, int(g.id) + 1)
	polylines.clear()
	for pd in data.get("polylines", []):
		var packed_pts: PackedVector2Array = PackedVector2Array()
		for pt in pd.get("points", []):
			if pt.size() >= 2:
				packed_pts.append(Vector2(float(pt[0]), float(pt[1])))
		var poly_side: String = str(pd.get("side", "top"))
		add_polyline(packed_pts, poly_side)
	# Gravity zones
	gravity_zones.deserialize(data.get("gravity_zones", []))
	world_loaded.emit()

func add_line(start: Vector2, end: Vector2, color: Color, width: float = 3.0) -> void:
	lines.append({"start": start, "end": end, "color": color, "width": width})
	lines_changed.emit()

func remove_line_near(pos: Vector2, radius: float = 8.0) -> void:
	for i in range(lines.size() - 1, -1, -1):
		var line: Dictionary = lines[i]
		var dist: float = _point_to_segment_dist(pos, line.start, line.end)
		if dist < radius:
			lines.remove_at(i)
			lines_changed.emit()
			return

func _point_to_segment_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var ap: Vector2 = p - a
	var t: float = clampf(ap.dot(ab) / maxf(ab.dot(ab), 0.001), 0.0, 1.0)
	var closest: Vector2 = a + ab * t
	return p.distance_to(closest)

func check_line_collision(px: float, py: float, pw: float, ph: float) -> float:
	# Check if a box (px,py,pw,ph) intersects any line
	# Returns the Y position to push the player to, or -1 if no collision
	var best_y: float = -1.0
	var player_bottom: float = py + ph
	for line in lines:
		var a: Vector2 = line.start
		var b: Vector2 = line.end
		# Check if player's X range overlaps line's X range
		var min_x: float = minf(a.x, b.x)
		var max_x: float = maxf(a.x, b.x)
		if px + pw < min_x or px > max_x:
			continue
		# Get line Y at player center X
		var center_x: float = clampf(px + pw / 2.0, min_x, max_x)
		var t: float = 0.0
		if absf(b.x - a.x) > 0.01:
			t = (center_x - a.x) / (b.x - a.x)
		var line_y: float = a.y + (b.y - a.y) * t
		# If player bottom is below line surface, push up
		if player_bottom > line_y and py < line_y:
			var new_y: float = line_y - ph
			if best_y < 0 or new_y < best_y:
				best_y = new_y
	return best_y

func get_line_slide_force(px: float, py: float, pw: float, ph: float) -> float:
	# Returns horizontal slide force based on line angle
	var player_bottom: float = py + ph
	for line in lines:
		var a: Vector2 = line.start
		var b: Vector2 = line.end
		var min_x: float = minf(a.x, b.x)
		var max_x: float = maxf(a.x, b.x)
		if px + pw < min_x or px > max_x:
			continue
		var center_x: float = clampf(px + pw / 2.0, min_x, max_x)
		var t: float = 0.0
		if absf(b.x - a.x) > 0.01:
			t = (center_x - a.x) / (b.x - a.x)
		var line_y: float = a.y + (b.y - a.y) * t
		if absf(player_bottom - line_y) < 3.0:
			# On this line - calculate slope angle
			var dx: float = b.x - a.x
			var dy: float = b.y - a.y
			if absf(dx) < 0.01:
				continue
			var slope: float = dy / dx  # positive = going down-right
			return slope * 0.15
	return 0.0

func save_to_file(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(serialize_world(), "\t"))
	file.close()
	return OK

func load_from_file(path: String) -> Error:
	if not FileAccess.file_exists(path): return ERR_FILE_NOT_FOUND
	var file := FileAccess.open(path, FileAccess.READ)
	if not file: return FileAccess.get_open_error()
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary: return ERR_PARSE_ERROR
	deserialize_world(data)
	return OK

@rpc("any_peer", "reliable")
func request_tile_edit(x: int, y: int, block_id: int, layer: String) -> void:
	pass

@rpc("authority", "reliable")
func sync_tile(x: int, y: int, block_id: int, layer: String) -> void:
	pass

@rpc("authority", "reliable")
func receive_world_snapshot(data_json: String) -> void:
	pass

@rpc("authority", "reliable")
func sync_state_channel(channel_id: int, value: int) -> void:
	pass

func send_world_to_peer(peer_id: int) -> void:
	pass

func build_sample_room() -> void:
	init_empty_world(400, 200)
	# Border
	for x in range(world_width):
		set_fg_tile(x, 0, 9)
		set_fg_tile(x, world_height - 1, 9)
	for y in range(world_height):
		set_fg_tile(0, y, 9)
		set_fg_tile(world_width - 1, y, 9)
	# Floor
	for x in range(1, world_width - 1):
		set_fg_tile(x, world_height - 2, 10)
	# Platforms
	for x in range(8, 12):
		set_fg_tile(x, world_height - 5, 12)
	for x in range(15, 19):
		set_fg_tile(x, world_height - 8, 14)
	for x in range(22, 30):
		set_fg_tile(x, world_height - 11, 15)
	# Hazard
	for x in range(35, 40):
		set_fg_tile(x, world_height - 2, 0)
		set_fg_tile(x, world_height - 2, 361)
	# Keys and doors
	set_fg_tile(32, world_height - 3, 6)
	for y in range(world_height - 6, world_height - 2):
		set_fg_tile(42, y, 23)
	# Spawn
	spawn_points = [Vector2(3, world_height - 4), Vector2(5, world_height - 4)]
	world_loaded.emit()
