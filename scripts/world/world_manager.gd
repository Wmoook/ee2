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
var _pending_net_tiles: Array = []  # Queued tile edits to send with next position broadcast
var _pending_net_freeblocks: Array = []  # Queued free block adds
var _pending_net_fb_replace: Dictionary = {}  # Queued free block bulk replace {remove_count, blocks}
var _pending_net_polylines: Array = []  # Queued polyline adds
var _pending_net_deletions: Array = []  # Queued deletions {type, pos_x, pos_y}
var _pending_net_gz: Array = []  # Queued gravity zone changes
var wedge_pairs: Array = []  # Pre-computed [{a: poly_dict, b: poly_dict}]
# Global spatial hash: all render edges from all polylines in one hash
# Key: cell_key -> Array of {edge: PackedVector2Array, si: int, poly_idx: int, rd: Array}
var _global_render_hash: Dictionary = {}
var _global_render_cell: int = 32
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

func _find_pinch_point(pts: PackedVector2Array) -> Dictionary:
	## Find where a polyline self-narrows (two non-adjacent parts within 17px).
	## Returns the midpoint split index, or -1 if no pinch found.
	const PINCH_DIST: float = 50.0  # Aggressively split U/V curves
	const MIN_SEG_GAP: int = 8  # Allow tighter U bottoms to split
	if pts.size() < MIN_SEG_GAP * 2 + 1:
		return {"idx": -1}  # Too short to self-intersect
	# Spatial hash for efficiency
	var cell_size: int = 32  # Must be >= PINCH_DIST for reliable neighbor search
	var buckets: Dictionary = {}
	for i in range(pts.size()):
		var key: int = int(floor(pts[i].x / cell_size)) * 10000 + int(floor(pts[i].y / cell_size))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(i)
	# Find pinch pairs and pick the one that splits most evenly
	var _min_pts: int = int(pts.size() * 0.15)  # Each half must be at least 15% of total
	var best_mid: int = -1
	var best_balance: float = 999999.0  # Lower = more balanced
	for i in range(pts.size()):
		var gx: int = int(floor(pts[i].x / cell_size))
		var gy: int = int(floor(pts[i].y / cell_size))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var key: int = (gx + dx) * 10000 + (gy + dy)
				if not buckets.has(key):
					continue
				for j in buckets[key]:
					if abs(j - i) <= MIN_SEG_GAP:
						continue
					var d: float = pts[i].distance_to(pts[j])
					if d < PINCH_DIST:
						var lo: int = mini(i, j)
						var hi: int = maxi(i, j)
						var mid: int = int((lo + hi) / 2)
						# Reject splits too close to edges
						if mid <= _min_pts or mid >= pts.size() - _min_pts:
							continue
						# Prefer most balanced split (mid closest to center)
						var balance: float = absf(float(mid) - float(pts.size()) / 2.0)
						if balance < best_balance:
							best_balance = balance
							best_mid = mid
	if best_mid < 0:
		return {"idx": -1}
	return {"idx": best_mid}

func add_polyline(points: PackedVector2Array, side: String = "top", block_id: int = 9, uv_offset: float = 0.0, _no_split: bool = false) -> void:
	if points.size() < 2:
		return
	# Auto-split: detect self-intersecting (V/U) curves
	# Visual: keep ONE full curve mesh. Collision: split into two polys for sandwich detection.
	if not _no_split:
		var _pinch: Dictionary = _find_pinch_point(points)
		var _split_at: int = _pinch.get("idx", -1)
		if _split_at > 1 and _split_at < points.size() - 2:
			push_warning("PINCH_SPLIT at idx=%d of %d pts" % [_split_at, points.size()])
			# Add the FULL curve for rendering (collision_only=false, render_only=true)
			add_polyline(points, side, block_id, 0.0, true)
			polylines[-1]["render_only"] = true  # Skip in collision
			# Add split halves for collision only (no mesh needed)
			var pts_a: PackedVector2Array = points.slice(0, _split_at + 1)
			var pts_b: PackedVector2Array = points.slice(_split_at)
			add_polyline(pts_a, side, block_id, 0.0, true)
			polylines[-1]["collision_only"] = true
			add_polyline(pts_b, side, block_id, 0.0, true)
			polylines[-1]["collision_only"] = true
			# Tag pairs so physics can find them
			var _arm_a_idx: int = polylines.size() - 2
			var _arm_b_idx: int = polylines.size() - 1
			polylines[_arm_a_idx]["split_pair"] = _arm_b_idx
			polylines[_arm_b_idx]["split_pair"] = _arm_a_idx
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
		"spatial_hash": _build_spatial_hash(points, 32),
		"render_top_hash": _build_spatial_hash(render_top, 32),
		"render_bot_hash": _build_spatial_hash(render_bot, 32),
		"uv_offset": uv_offset,
		"from_split": uv_offset != 0.0  # Part of a split — skip mesh truncation
	})
	_rebuild_wedge_pairs()
	_rebuild_global_render_hash()
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

func _rebuild_wedge_pairs() -> void:
	wedge_pairs.clear()
	var seen: Dictionary = {}
	for i in range(polylines.size()):
		var pa: Dictionary = polylines[i]
		if not pa.get("collision_only", false):
			continue
		var pair_idx: int = pa.get("split_pair", -1)
		if pair_idx < 0 or pair_idx >= polylines.size():
			continue
		var lo: int = mini(i, pair_idx)
		var hi: int = maxi(i, pair_idx)
		var key: int = lo * 10000 + hi
		if seen.has(key):
			continue
		seen[key] = true
		wedge_pairs.append({"a": polylines[lo], "b": polylines[hi]})

func _rebuild_global_render_hash() -> void:
	_global_render_hash.clear()
	var cs: int = _global_render_cell
	for pi in range(polylines.size()):
		var poly: Dictionary = polylines[pi]
		if poly.get("render_only", false):
			continue
		var rd: Array = poly.get("render_dists", [])
		for edge in [poly.render_top, poly.render_bot]:
			for si in range(edge.size() - 1):
				var sa: Vector2 = edge[si]
				var sb: Vector2 = edge[si + 1]
				var ax: int = int(floor(sa.x / cs))
				var ay: int = int(floor(sa.y / cs))
				var bx: int = int(floor(sb.x / cs))
				var by: int = int(floor(sb.y / cs))
				for gx in range(mini(ax, bx), maxi(ax, bx) + 1):
					for gy in range(mini(ay, by), maxi(ay, by) + 1):
						var key: int = gx * 10000 + gy
						if not _global_render_hash.has(key):
							_global_render_hash[key] = []
						_global_render_hash[key].append([edge, si, pi, rd])

func check_polyline_collision(px: float, py: float, pw: float, ph: float, prefer_normal: Vector2 = Vector2.ZERO, stick_poly: int = -1, exclude_poly: int = -1, only_poly: int = -1) -> Dictionary:
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
			continue
		if only_poly >= 0 and _dbg_poly_idx != only_poly:
			continue
		if poly.get("render_only", false):
			continue  # Skip render-only polylines (no collision)
		# AABB broad phase
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		if px + pw < bb_min.x or px > bb_max.x or py + ph < bb_min.y or py > bb_max.y:
			continue
		var pts: PackedVector2Array = poly.points
		var norms: Array = poly.normals
		# Find nearest segment via spatial hash (O(1) instead of O(N))
		var closest_seg: int = -1
		var closest_t: float = 0.0
		var closest_dist: float = 999999.0
		var second_seg: int = -1
		var second_t: float = 0.0
		var second_dist: float = 999999.0
		var eff_radius: float = 8.0
		var block_half: float = 8.35
		var _shash: Dictionary = poly.get("spatial_hash", {})
		var _cs: int = _shash.get("cell_size", 32)
		var _sgx: int = int(floor(pcx / _cs))
		var _sgy: int = int(floor(pcy / _cs))
		var _checked: Dictionary = {}
		var _pvec: Vector2 = Vector2(pcx, pcy)
		for _sdx in range(-2, 3):
			for _sdy in range(-2, 3):
				var _skey: int = (_sgx + _sdx) * 10000 + (_sgy + _sdy)
				if not _shash.has(_skey):
					continue
				for si in _shash[_skey]:
					if _checked.has(si):
						continue
					_checked[si] = true
					var sa: Vector2 = pts[si]
					var sb: Vector2 = pts[si + 1]
					var ab: Vector2 = sb - sa
					var ap: Vector2 = _pvec - sa
					var ab_dot: float = ab.dot(ab)
					var seg_t: float = clampf(ap.dot(ab) / maxf(ab_dot, 0.001), 0.0, 1.0)
					var on_pt: Vector2 = sa + ab * seg_t
					var dist: float = _pvec.distance_to(on_pt)
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
		# Self-intersection guard (SAME polyline only): if nearest segment push
		# opposes prefer_normal and there's a second branch nearby, use second
		if second_seg >= 0 and prefer_normal.length() > 0.1:
			var seg_a1: Vector2 = pts[closest_seg]
			var seg_b1: Vector2 = pts[closest_seg + 1]
			var on1: Vector2 = seg_a1 + (seg_b1 - seg_a1) * closest_t
			var n1: Vector2 = (norms[closest_seg] * (1.0 - closest_t) + norms[closest_seg + 1] * closest_t).normalized()
			if n1.length() < 0.01: n1 = norms[closest_seg]
			var dir1: Vector2 = n1 if (Vector2(pcx, pcy) - on1).dot(n1) >= 0 else -n1
			var seg_a2: Vector2 = pts[second_seg]
			var seg_b2: Vector2 = pts[second_seg + 1]
			var on2: Vector2 = seg_a2 + (seg_b2 - seg_a2) * second_t
			var n2s: Vector2 = (norms[second_seg] * (1.0 - second_t) + norms[second_seg + 1] * second_t).normalized()
			if n2s.length() < 0.01: n2s = norms[second_seg]
			var dir2: Vector2 = n2s if (Vector2(pcx, pcy) - on2).dot(n2s) >= 0 else -n2s
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
		# Use curve's stored normal for consistent push direction
		# Flip if player is on the opposite side of the centerline
		var push_dir: Vector2 = interp_normal
		if dist_to_line > 0.01 and to_player.dot(interp_normal) < 0:
			push_dir = -interp_normal
		var penetration: float = minf((eff_radius + block_half) - dist_to_line, 4.0)
		if penetration > 0 and dist_to_line < eff_radius + block_half + 2.0:
			var seg_tangent: Vector2 = (seg_b - seg_a).normalized()
			_dbg_hits.append({"poly": _dbg_poly_idx, "seg": closest_seg, "pen": penetration, "dist": dist_to_line, "push_dir": push_dir, "on_seg": on_seg, "tangent": seg_tangent})
			# Same-poly sandwich: if second branch also in collision range with opposing push,
			# add it as a virtual "other poly" so sandwich detection triggers
			if second_seg >= 0 and second_dist < eff_radius + block_half + 2.0:
				var seg_a2: Vector2 = pts[second_seg]
				var seg_b2: Vector2 = pts[second_seg + 1]
				var on2: Vector2 = seg_a2 + (seg_b2 - seg_a2) * second_t
				var to_p2: Vector2 = Vector2(pcx, pcy) - on2
				var d2: float = to_p2.length()
				var n2: Vector2 = (norms[second_seg] * (1.0 - second_t) + norms[second_seg + 1] * second_t).normalized()
				if n2.length() < 0.01: n2 = norms[second_seg]
				var pd2: Vector2 = n2 if d2 <= 0.01 or to_p2.dot(n2) >= 0 else -n2
				var pen2: float = minf((eff_radius + block_half) - d2, 4.0)
				if pen2 > 0 and pd2.dot(push_dir) < 0.3:
					# Opposing push = same-poly U sandwich. Use virtual poly ID.
					var tan2: Vector2 = (seg_b2 - seg_a2).normalized()
					_dbg_hits.append({"poly": -900 - _dbg_poly_idx, "seg": second_seg, "pen": pen2, "dist": d2, "push_dir": pd2, "on_seg": on2, "tangent": tan2})
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
			# Also match virtual poly IDs (negative = same-poly sandwich: -900 - real_idx)
			var best_h: Dictionary = {}
			for h in _dbg_hits:
				var real_poly: int = h.poly if h.poly >= 0 else (-900 - h.poly)
				if real_poly == stick_poly:
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
	var min_dist: float = 16.1  # 8 player half + 8.35 curve visual half + 0.15 margin
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
			if poly.get("render_only", false):
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

func check_curve_wall(cx: float, cy: float, stick_poly: int, stick_arc: float, arc_exclude: float = 40.0, only_poly: int = -1) -> Dictionary:
	## Check if player center (cx,cy) is within 16.5px of any "wall" polyline segment.
	## Uses arc-length distance to exclude the riding zone on the stick poly.
	## stick_poly=-1 means no exclusion (everything is a wall).
	## Returns {blocked: bool, push: Vector2}
	var min_dist: float = 16.1
	var best_pen: float = 0.0
	var best_push: Vector2 = Vector2.ZERO
	var _best_wall_arc: float = -1.0
	var _best_wall_poly: int = -1
	var _best_wall_pos: Vector2 = Vector2.ZERO
	var _pidx: int = -1
	for poly in polylines:
		_pidx += 1
		if poly.get("render_only", false):
			continue
		if only_poly >= 0 and _pidx != only_poly:
			continue  # Only check specific poly
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
							_best_wall_arc = rd[si] if si < rd.size() else -1.0
							_best_wall_poly = _pidx
							_best_wall_pos = on_pt
	return {"blocked": best_pen > 0.01, "push": best_push, "wall_arc": _best_wall_arc, "wall_poly": _best_wall_poly, "wall_dist": min_dist - best_pen if best_pen > 0 else 99999.0, "wall_pos": _best_wall_pos}

func dist_to_wall_segments(cx: float, cy: float, stick_poly: int, stick_seg: int) -> float:
	## Distance to nearest "wall" segment — excludes ±20 segments around stick_seg on stick_poly.
	var best: float = 99999.0
	var _pidx: int = -1
	for poly in polylines:
		_pidx += 1
		if poly.get("render_only", false):
			continue
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
		if poly.get("render_only", false):
			continue
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

func dist_to_polyline_idx(poly_idx: int, cx: float, cy: float) -> float:
	## Distance from (cx,cy) to a SPECIFIC polyline's centerline, using spatial hash.
	if poly_idx < 0 or poly_idx >= polylines.size():
		return 99999.0
	var poly: Dictionary = polylines[poly_idx]
	var bb_min: Vector2 = poly.bbox_min
	var bb_max: Vector2 = poly.bbox_max
	if cx < bb_min.x - 20 or cx > bb_max.x + 20 or cy < bb_min.y - 20 or cy > bb_max.y + 20:
		return 99999.0
	var best_dist: float = 99999.0
	var shash: Dictionary = poly.get("spatial_hash", {})
	var cs: int = shash.get("cell_size", 32)
	var gx: int = int(floor(cx / cs))
	var gy: int = int(floor(cy / cs))
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
				var pts: PackedVector2Array = poly.points
				var sa: Vector2 = pts[si]
				var sb: Vector2 = pts[si + 1]
				var ab: Vector2 = sb - sa
				var ap: Vector2 = Vector2(cx, cy) - sa
				var ab_dot: float = ab.dot(ab)
				var seg_t: float = clampf(ap.dot(ab) / maxf(ab_dot, 0.001), 0.0, 1.0)
				var on_pt: Vector2 = sa + ab * seg_t
				var dist: float = Vector2(cx, cy).distance_to(on_pt)
				if dist < best_dist:
					best_dist = dist
	return best_dist

func get_purple_line_push(cx: float, cy: float) -> Vector2:
	## Uses GLOBAL render hash — one lookup covers ALL polylines.
	var thresh: float = 7.0
	var push_to: float = 9.0
	var best_dist: float = 99999.0
	var best_push: Vector2 = Vector2.ZERO
	var cs: int = _global_render_cell
	var gx: int = int(floor(cx / cs))
	var gy: int = int(floor(cy / cs))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key: int = (gx + dx) * 10000 + (gy + dy)
			if not _global_render_hash.has(key):
				continue
			for entry in _global_render_hash[key]:
				var edge: PackedVector2Array = entry[0]
				var si: int = entry[1]
				var sa: Vector2 = edge[si]
				var sb: Vector2 = edge[si + 1]
				var ab: Vector2 = sb - sa
				var ap: Vector2 = Vector2(cx, cy) - sa
				var t: float = clampf(ap.dot(ab) / maxf(ab.dot(ab), 0.001), 0.0, 1.0)
				var on_pt: Vector2 = sa + ab * t
				var to_player: Vector2 = Vector2(cx, cy) - on_pt
				var dist: float = to_player.length()
				if dist < thresh and dist < best_dist and dist > 0.01:
					best_dist = dist
					best_push = to_player.normalized() * (push_to - dist)
	return best_push

func dist_to_nearest_polyline(cx: float, cy: float, exclude_poly: int = -1) -> float:
	## Returns the distance from point (cx,cy) to the nearest polyline segment, excluding one.
	## Uses brute force within bbox for reliability (spatial hash can miss edge cases).
	var best_dist: float = 99999.0
	var _pidx: int = -1
	for poly in polylines:
		_pidx += 1
		if poly.get("render_only", false):
			continue
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
		if poly.get("render_only", false):
			continue
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

func intercept_polyline_tunneling(pre_cx: float, pre_cy: float, post_cx: float, post_cy: float, stick_poly: int = -1) -> Dictionary:
	## Anti-tunnel: sample movement path, detect if any point enters within 16px of a collision_only poly.
	## Places player at 15.5px from nearest segment on the approach side.
	var result: Dictionary = {"intercepted": false, "x": 0.0, "y": 0.0, "normal": Vector2.ZERO, "tangent": Vector2.ZERO, "poly_idx": -1}
	var dx: float = post_cx - pre_cx
	var dy: float = post_cy - pre_cy
	var move_len: float = sqrt(dx * dx + dy * dy)
	if move_len < 0.1:
		return result
	var sample_count: int = int(ceil(move_len / 2.0))  # Sample every 2px
	for poly in polylines:
		if poly.get("render_only", false):
			continue
		if not poly.get("collision_only", false):
			continue  # Only check split halves
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		var mx0: float = minf(pre_cx, post_cx)
		var mx1: float = maxf(pre_cx, post_cx)
		var my0: float = minf(pre_cy, post_cy)
		var my1: float = maxf(pre_cy, post_cy)
		if mx1 < bb_min.x - 20 or mx0 > bb_max.x + 20 or my1 < bb_min.y - 20 or my0 > bb_max.y + 20:
			continue
		var pts: PackedVector2Array = poly.points
		var norms: Array = poly.normals
		# Check pre-step distance — skip if already close (riding this arm)
		var _pre_best_d: float = 99999.0
		var shash: Dictionary = poly.get("spatial_hash", {})
		var cs2: int = shash.get("cell_size", 32)
		var pgx: int = int(floor(pre_cx / cs2))
		var pgy: int = int(floor(pre_cy / cs2))
		var pchecked: Dictionary = {}
		for pdx in range(-2, 3):
			for pdy in range(-2, 3):
				var pkey: int = (pgx + pdx) * 10000 + (pgy + pdy)
				if not shash.has(pkey):
					continue
				for psi in shash[pkey]:
					if pchecked.has(psi):
						continue
					pchecked[psi] = true
					var psa: Vector2 = pts[psi]
					var psb: Vector2 = pts[psi + 1]
					var pab: Vector2 = psb - psa
					var pap: Vector2 = Vector2(pre_cx, pre_cy) - psa
					var pt2: float = clampf(pap.dot(pab) / maxf(pab.dot(pab), 0.001), 0.0, 1.0)
					var pon: Vector2 = psa + pab * pt2
					var pd: float = Vector2(pre_cx, pre_cy).distance_to(pon)
					if pd < _pre_best_d:
						_pre_best_d = pd
		# Check if player is moving TOWARD this arm (post closer than pre)
		var _post_best_d: float = 99999.0
		var pchecked2: Dictionary = {}
		var pgx2: int = int(floor(post_cx / cs2))
		var pgy2: int = int(floor(post_cy / cs2))
		for pdx2 in range(-2, 3):
			for pdy2 in range(-2, 3):
				var pkey2: int = (pgx2 + pdx2) * 10000 + (pgy2 + pdy2)
				if not shash.has(pkey2):
					continue
				for psi2 in shash[pkey2]:
					if pchecked2.has(psi2):
						continue
					pchecked2[psi2] = true
					var psa2: Vector2 = pts[psi2]
					var psb2: Vector2 = pts[psi2 + 1]
					var pab2: Vector2 = psb2 - psa2
					var pap2: Vector2 = Vector2(post_cx, post_cy) - psa2
					var pt22: float = clampf(pap2.dot(pab2) / maxf(pab2.dot(pab2), 0.001), 0.0, 1.0)
					var pon2: Vector2 = psa2 + pab2 * pt22
					var pd2: float = Vector2(post_cx, post_cy).distance_to(pon2)
					if pd2 < _post_best_d:
						_post_best_d = pd2
		if _post_best_d >= _pre_best_d:
			continue  # Moving away or parallel — skip
		# Sample along the path
		for si in range(1, sample_count + 1):
			var frac: float = float(si) / float(sample_count)
			var sx: float = pre_cx + dx * frac
			var sy: float = pre_cy + dy * frac
			# Find nearest segment at this sample point
			var sgx: int = int(floor(sx / cs2))
			var sgy: int = int(floor(sy / cs2))
			var schecked: Dictionary = {}
			for sdx in range(-2, 3):
				for sdy in range(-2, 3):
					var skey: int = (sgx + sdx) * 10000 + (sgy + sdy)
					if not shash.has(skey):
						continue
					for ssi in shash[skey]:
						if schecked.has(ssi):
							continue
						schecked[ssi] = true
						var ssa: Vector2 = pts[ssi]
						var ssb: Vector2 = pts[ssi + 1]
						var sab: Vector2 = ssb - ssa
						var sap: Vector2 = Vector2(sx, sy) - ssa
						var st: float = clampf(sap.dot(sab) / maxf(sab.dot(sab), 0.001), 0.0, 1.0)
						var son: Vector2 = ssa + sab * st
						var sd: float = Vector2(sx, sy).distance_to(son)
						if sd < 16.0:
							# Found entry point — place player 15.5px from segment
							var prev_frac: float = maxf(0.0, float(si - 1) / float(sample_count))
							var interp_n: Vector2 = (norms[ssi] * (1.0 - st) + norms[ssi + 1] * st).normalized()
							if interp_n.length() < 0.01:
								interp_n = norms[ssi]
							# Orient toward pre-step side
							if (Vector2(pre_cx, pre_cy) - son).dot(interp_n) < 0:
								interp_n = -interp_n
							return {
								"intercepted": true,
								"x": son.x + interp_n.x * 15.5,
								"y": son.y + interp_n.y * 15.5,
								"normal": interp_n,
								"tangent": (ssb - ssa).normalized(),
								"poly_idx": -1
							}
	return result

func does_step_cross_render_edge(x1: float, y1: float, x2: float, y2: float, stick_poly: int = -1, stick_arc: float = -1.0) -> bool:
	## Uses GLOBAL render hash — one lookup covers ALL polylines. No per-poly iteration.
	## Skip edges from polylines whose centerline is near the player (surface transition, not tunneling).
	var mid_x: float = (x1 + x2) * 0.5
	var mid_y: float = (y1 + y2) * 0.5
	# Pre-compute which polylines are "nearby" (within collision range) — skip their edges
	var _nearby_polys: Dictionary = {}
	for pi2 in range(polylines.size()):
		var poly2: Dictionary = polylines[pi2]
		if poly2.get("render_only", false):
			continue
		if mid_x < poly2.bbox_min.x - 24 or mid_x > poly2.bbox_max.x + 24 or mid_y < poly2.bbox_min.y - 24 or mid_y > poly2.bbox_max.y + 24:
			continue
		# Check if player center is within 20px of this poly's centerline
		var pts2: PackedVector2Array = poly2.points
		for si2 in range(pts2.size() - 1):
			var sa2: Vector2 = pts2[si2]
			var sb2: Vector2 = pts2[si2 + 1]
			var ab2: Vector2 = sb2 - sa2
			var ap2: Vector2 = Vector2(mid_x, mid_y) - sa2
			var t2: float = clampf(ap2.dot(ab2) / maxf(ab2.dot(ab2), 0.001), 0.0, 1.0)
			var on2: Vector2 = sa2 + ab2 * t2
			if Vector2(mid_x, mid_y).distance_to(on2) < 20.0:
				_nearby_polys[pi2] = true
				break
	var d1x: float = x2 - x1
	var d1y: float = y2 - y1
	var cs: int = _global_render_cell
	var gx: int = int(floor(mid_x / cs))
	var gy: int = int(floor(mid_y / cs))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var key: int = (gx + dx) * 10000 + (gy + dy)
			if not _global_render_hash.has(key):
				continue
			for entry in _global_render_hash[key]:
				var edge: PackedVector2Array = entry[0]
				var si: int = entry[1]
				var pi: int = entry[2]
				var rd: Array = entry[3]
				# Skip edges from stick poly near current arc position
				if pi == stick_poly and stick_arc >= 0 and si < rd.size() and absf(rd[si] - stick_arc) < 40.0:
					continue
				# Skip edges from nearby polylines (player already in collision range)
				if _nearby_polys.has(pi):
					continue
				var sa: Vector2 = edge[si]
				var sb: Vector2 = edge[si + 1]
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

func does_step_cross_collision_only(x1: float, y1: float, x2: float, y2: float, exclude_poly: int = -1) -> Dictionary:
	## Check if step crosses any COLLISION_ONLY polyline centerline (excluding one).
	## Returns {crossed, point, normal} or {crossed: false}
	var _pidx: int = -1
	for poly in polylines:
		_pidx += 1
		if _pidx == exclude_poly:
			continue
		if not poly.get("collision_only", false):
			continue
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		if maxf(x1, x2) < bb_min.x - 2 or minf(x1, x2) > bb_max.x + 2:
			continue
		if maxf(y1, y2) < bb_min.y - 2 or minf(y1, y2) > bb_max.y + 2:
			continue
		var pts: PackedVector2Array = poly.points
		var shash: Dictionary = poly.get("spatial_hash", {})
		var cs2: int = shash.get("cell_size", 32)
		var gx: int = int(floor((x1 + x2) * 0.5 / cs2))
		var gy: int = int(floor((y1 + y2) * 0.5 / cs2))
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
					var sa: Vector2 = pts[si]
					var sb: Vector2 = pts[si + 1]
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
						var norms: Array = poly.normals
						var interp_n: Vector2 = (norms[si] * (1.0 - u) + norms[si + 1] * u).normalized()
						if interp_n.length() < 0.01:
							interp_n = norms[si]
						var on_seg: Vector2 = sa + (sb - sa) * u
						if (Vector2(x1, y1) - on_seg).dot(interp_n) < 0:
							interp_n = -interp_n
						return {"crossed": true, "point": on_seg, "normal": interp_n}
	return {"crossed": false}

func does_step_enter_polyline(cx: float, cy: float, ocx: float, ocy: float, threshold: float = 16.0) -> bool:
	## Check if moving from (ocx,ocy) to (cx,cy) enters within threshold of any collision_only polyline.
	## Only blocks when getting closer (entering the zone, not already inside).
	for poly in polylines:
		if poly.get("render_only", false):
			continue
		if not poly.get("collision_only", false):
			continue  # Only check split halves
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		if cx < bb_min.x - threshold or cx > bb_max.x + threshold or cy < bb_min.y - threshold or cy > bb_max.y + threshold:
			continue
		var pts: PackedVector2Array = poly.points
		var shash: Dictionary = poly.get("spatial_hash", {})
		var cs2: int = shash.get("cell_size", 32)
		var gx2: int = int(floor(cx / cs2))
		var gy2: int = int(floor(cy / cs2))
		var checked: Dictionary = {}
		for dx2 in range(-2, 3):
			for dy2 in range(-2, 3):
				var key: int = (gx2 + dx2) * 10000 + (gy2 + dy2)
				if not shash.has(key):
					continue
				for si in shash[key]:
					if checked.has(si):
						continue
					checked[si] = true
					var sa: Vector2 = pts[si]
					var sb: Vector2 = pts[si + 1]
					var ab: Vector2 = sb - sa
					# Distance from NEW position to segment
					var ap_new: Vector2 = Vector2(cx, cy) - sa
					var t_new: float = clampf(ap_new.dot(ab) / maxf(ab.dot(ab), 0.001), 0.0, 1.0)
					var on_new: Vector2 = sa + ab * t_new
					var d_new: float = Vector2(cx, cy).distance_to(on_new)
					if d_new < threshold:
						# Distance from OLD position
						var ap_old: Vector2 = Vector2(ocx, ocy) - sa
						var t_old: float = clampf(ap_old.dot(ab) / maxf(ab.dot(ab), 0.001), 0.0, 1.0)
						var on_old: Vector2 = sa + ab * t_old
						var d_old: float = Vector2(ocx, ocy).distance_to(on_old)
						if d_new < d_old:  # Getting closer = entering
							return true
	return false

func does_step_cross_polyline(x1: float, y1: float, x2: float, y2: float) -> bool:
	## Fast check: does a small step from (x1,y1) to (x2,y2) cross any polyline segment?
	## Coordinates are player CENTER positions.
	if polylines.is_empty():
		return false
	for poly in polylines:
		if poly.get("render_only", false):
			continue
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
		if poly.get("render_only", false):
			continue
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
	# Find the first matching polyline
	var hit_idx: int = -1
	for i in range(polylines.size() - 1, -1, -1):
		var poly: Dictionary = polylines[i]
		var pts: PackedVector2Array = poly.points
		for pi in range(pts.size()):
			if pts[pi].distance_to(pos) < radius:
				hit_idx = i
				break
		if hit_idx >= 0:
			break
	if hit_idx < 0:
		return
	# Collect all related indices (render_only parent + collision_only split pairs)
	var to_remove: Array = [hit_idx]
	var hit_poly: Dictionary = polylines[hit_idx]
	# If this is a split pair half, find the other half and the render_only parent
	if hit_poly.get("collision_only", false):
		var pair: int = hit_poly.get("split_pair", -1)
		if pair >= 0 and pair < polylines.size() and not to_remove.has(pair):
			to_remove.append(pair)
		# Find the render_only parent (usually right before the collision halves)
		for j in range(polylines.size()):
			if j != hit_idx and polylines[j].get("render_only", false):
				# Check if it's the same curve by comparing points overlap
				var rpts: PackedVector2Array = polylines[j].points
				var hpts: PackedVector2Array = hit_poly.points
				if rpts.size() > 0 and hpts.size() > 0:
					if rpts[0].distance_to(hpts[0]) < 2.0 or rpts[-1].distance_to(hpts[-1]) < 2.0 or rpts[0].distance_to(hpts[-1]) < 2.0 or rpts[-1].distance_to(hpts[0]) < 2.0:
						if not to_remove.has(j):
							to_remove.append(j)
	elif hit_poly.get("render_only", false):
		# Clicked on the render parent — find its collision halves
		var rpts: PackedVector2Array = hit_poly.points
		for j in range(polylines.size()):
			if j == hit_idx:
				continue
			if polylines[j].get("collision_only", false):
				var cpts: PackedVector2Array = polylines[j].points
				if cpts.size() > 0 and rpts.size() > 0:
					if rpts[0].distance_to(cpts[0]) < 2.0 or rpts[-1].distance_to(cpts[-1]) < 2.0 or rpts[0].distance_to(cpts[-1]) < 2.0 or rpts[-1].distance_to(cpts[0]) < 2.0:
						if not to_remove.has(j):
							to_remove.append(j)
	# Remove in reverse order so indices stay valid
	to_remove.sort()
	for k in range(to_remove.size() - 1, -1, -1):
		polylines.remove_at(to_remove[k])
	# Rebuild spatial hashes and wedge pairs after removal
	_rebuild_wedge_pairs()
	_rebuild_global_render_hash()
	# Invalidate cached mesh on remaining polylines (indices shifted)
	for p in polylines:
		p.erase("_cached_mesh")
		p.erase("_cached_tex")
	_pending_net_poly_fullsync = true
	polylines_changed.emit()

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
	spawn_points = [Vector2(3, h - 3) if h > 6 else Vector2(3, 3)]

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
		if poly.get("collision_only", false):
			continue  # Don't save split halves — they're recreated on load
		if poly.get("render_only", false):
			# Save the original full curve (not the render_only version)
			pass  # Fall through to save it
		var pts_arr: Array = []
		for pt in poly.points:
			pts_arr.append([pt.x, pt.y])
		poly_data.append({"points": pts_arr, "side": poly.side, "block_id": poly.get("block_id", 9)})
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
		spawn_points = [Vector2(3, world_height - 3)]
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
		var poly_bid: int = int(pd.get("block_id", 9))
		add_polyline(packed_pts, poly_side, poly_bid)
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
	# Server receives edit request from client — validate and broadcast
	if not multiplayer.is_server():
		return
	if x < 0 or x >= world_width or y < 0 or y >= world_height:
		return
	if layer == "fg":
		set_fg_tile(x, y, block_id)
	elif layer == "bg":
		set_bg_tile(x, y, block_id)
	sync_tile.rpc(x, y, block_id, layer)

@rpc("authority", "reliable")
func sync_tile(x: int, y: int, block_id: int, layer: String) -> void:
	# All clients receive tile update from server
	if layer == "fg":
		set_fg_tile(x, y, block_id)
	elif layer == "bg":
		set_bg_tile(x, y, block_id)

@rpc("authority", "reliable")
func receive_world_snapshot(data_json: String) -> void:
	# Client receives full world state from server
	var data: Variant = JSON.parse_string(data_json)
	if data is Dictionary:
		deserialize_world(data)

@rpc("authority", "reliable")
func sync_state_channel(channel_id: int, value: int) -> void:
	pass

func send_world_to_peer(peer_id: int) -> void:
	# Server sends full world state to a specific client
	var data: Dictionary = serialize_world()
	var json: String = JSON.stringify(data)
	receive_world_snapshot.rpc_id(peer_id, json)

## Network-aware polyline add
func net_add_polyline(pts: PackedVector2Array, side: String, block_id: int) -> void:
	add_polyline(pts, side, block_id)
	# Serialize points for network
	var pts_arr: Array = []
	for p in pts:
		pts_arr.append({"x": p.x, "y": p.y})
	_pending_net_polylines.append({"pts": pts_arr, "side": side, "bid": block_id})

## Network-aware free block remove by index (syncs by position)
func net_remove_free_block(idx: int) -> void:
	if idx >= 0 and idx < free_blocks.size():
		var fb: Dictionary = free_blocks[idx]
		_pending_net_deletions.append({"type": "fb", "x": fb.pos.x, "y": fb.pos.y, "id": fb.id})
		free_blocks.remove_at(idx)
		tile_changed.emit(0, 0, 0)

## Network-aware polyline remove near position
func net_remove_polyline_near(pos: Vector2, radius: float) -> void:
	_pending_net_deletions.append({"type": "poly", "x": pos.x, "y": pos.y, "r": radius})
	remove_polyline_near(pos, radius)

## Network-aware bg tile edit
func net_set_bg_tile(x: int, y: int, block_id: int) -> void:
	net_set_tile(x, y, block_id, "bg")

## Network-aware free block add
func net_add_free_block(fb: Dictionary) -> void:
	free_blocks.append(fb)
	_pending_net_freeblocks.append({"pos_x": fb.pos.x, "pos_y": fb.pos.y, "id": fb.id, "rot": fb.get("rotation", 0.0)})
	tile_changed.emit(0, 0, 0)  # Trigger renderer redraw

## Network-aware tile edit — use instead of direct set_fg_tile/set_bg_tile
func net_set_tile(x: int, y: int, block_id: int, layer: String = "fg") -> void:
	if layer == "fg":
		set_fg_tile(x, y, block_id)
	elif layer == "bg":
		set_bg_tile(x, y, block_id)
	_pending_net_tiles.append({"x": x, "y": y, "id": block_id, "l": layer})
	# Debug log next to exe
	var _log_name: String = "host_log.txt" if NetworkManager.is_host else "receiver_log.txt"
	var _log_path: String = OS.get_executable_path().get_base_dir() + "/" + _log_name
	var f: FileAccess = FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(_log_path, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("NET_SET_TILE x=%d y=%d id=%d layer=%s queue=%d peer=%s" % [x, y, block_id, layer, _pending_net_tiles.size(), str(NetworkManager._peer)])
		f.close()

var _pending_net_clear_world: bool = false  # Queued full world clear
var _pending_net_poly_fullsync: bool = false  # Send full polyline state

## Network-aware full world clear (keeps border)
func net_clear_world() -> void:
	free_blocks.clear()
	block_groups.clear()
	polylines.clear()
	lines.clear()
	gravity_zones.clear()
	for y in range(1, world_height - 1):
		for x in range(1, world_width - 1):
			set_fg_tile(x, y, 0)
			set_bg_tile(x, y, 0)
			set_rotation(x, y, 0)
	spawn_points = [Vector2(3, world_height - 3), Vector2(5, world_height - 3)]
	_rebuild_wedge_pairs()
	_rebuild_global_render_hash()
	tile_changed.emit(0, 0, 0)
	polylines_changed.emit()
	_pending_net_clear_world = true

## Network-aware free block bulk replace (remove last N, add new ones)
func net_replace_free_blocks(remove_count: int, new_blocks: Array) -> void:
	# Locally: already done by caller (resize + append)
	# Queue for network: tell remote to do the same
	var serialized: Array = []
	for fb in new_blocks:
		serialized.append({"pos_x": fb.pos.x, "pos_y": fb.pos.y, "id": fb.id, "rot": fb.get("rotation", 0.0)})
	_pending_net_fb_replace = {"remove": remove_count, "blocks": serialized}

## Network-aware gravity zone add
func net_add_gravity_zone(center: Vector2, radius: float, strength: float = 2.0, center_radius: float = 8.0) -> void:
	gravity_zones.add_zone(center, radius, strength, center_radius)
	_pending_net_gz.append({"action": "add", "cx": center.x, "cy": center.y, "r": radius, "s": strength, "cr": center_radius})

## Network-aware gravity zone remove
func net_remove_gravity_zone_near(pos: Vector2, threshold: float = 24.0) -> void:
	gravity_zones.remove_zone_near(pos, threshold)
	_pending_net_gz.append({"action": "remove", "cx": pos.x, "cy": pos.y, "t": threshold})

## Network-aware gravity zone clear
func net_clear_gravity_zones() -> void:
	gravity_zones.clear()
	_pending_net_gz.append({"action": "clear"})

func build_sample_room() -> void:
	init_empty_world(400, 200)
	# Completely empty world — just a border so players don't fall into void
	for x in range(world_width):
		set_fg_tile(x, 0, 9)
		set_fg_tile(x, world_height - 1, 9)
	for y in range(world_height):
		set_fg_tile(0, y, 9)
		set_fg_tile(world_width - 1, y, 9)
	# Spawn at top-left corner (on the border floor)
	spawn_points = [Vector2(2, world_height - 2), Vector2(4, world_height - 2)]
	world_loaded.emit()
