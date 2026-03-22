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
	polylines.append({
		"points": points,
		"normals": vert_normals,
		"side": side,
		"block_id": block_id,
		"bbox_min": bb_min,
		"bbox_max": bb_max
	})
	polylines_changed.emit()

func check_polyline_collision(px: float, py: float, pw: float, ph: float) -> Dictionary:
	## Check if axis-aligned box (px,py,pw,ph) collides with any polyline.
	## Returns {hit, push, normal, tangent} with interpolated normal at closest point.
	var result: Dictionary = {"hit": false, "push": Vector2.ZERO, "normal": Vector2(0, -1), "tangent": Vector2(1, 0)}
	var pcx: float = px + pw * 0.5
	var pcy: float = py + ph * 0.5
	var best_pen: float = -999.0  # Most positive = deepest penetration
	for poly in polylines:
		# AABB broad phase
		var bb_min: Vector2 = poly.bbox_min
		var bb_max: Vector2 = poly.bbox_max
		if px + pw < bb_min.x or px > bb_max.x or py + ph < bb_min.y or py > bb_max.y:
			continue
		var pts: PackedVector2Array = poly.points
		var norms: Array = poly.normals
		# Find nearest segment to player center
		var closest_dist: float = 999999.0
		var closest_seg: int = -1
		var closest_t: float = 0.0
		for si in range(pts.size() - 1):
			var sa: Vector2 = pts[si]
			var sb: Vector2 = pts[si + 1]
			var ab: Vector2 = sb - sa
			var ap: Vector2 = Vector2(pcx, pcy) - sa
			var ab_dot: float = ab.dot(ab)
			var seg_t: float = clampf(ap.dot(ab) / maxf(ab_dot, 0.001), 0.0, 1.0)
			var closest_pt: Vector2 = sa + ab * seg_t
			var dist: float = Vector2(pcx, pcy).distance_to(closest_pt)
			if dist < closest_dist:
				closest_dist = dist
				closest_seg = si
				closest_t = seg_t
		if closest_seg < 0:
			continue
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
		# Push direction and fixed half-size (player stands upright on curves)
		var push_dir: Vector2 = to_player.normalized() if dist_to_line > 0.01 else interp_normal
		var eff_radius: float = 8.0  # Fixed: player half-height, not box projection
		# Penetration: player overlaps the curve (block half-width = 8px)
		var block_half: float = 8.0
		var penetration: float = (eff_radius + block_half) - dist_to_line
		if penetration > 0 and dist_to_line < eff_radius + block_half + 2.0:
			if penetration > best_pen:
				best_pen = penetration
				var push_vec: Vector2 = push_dir * penetration
				# Use the push direction as normal for grounding/speed
				var seg_tangent: Vector2 = (seg_b - seg_a).normalized()
				result = {"hit": true, "push": push_vec, "normal": push_dir, "tangent": seg_tangent}
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
	# Place border walls
	for x in range(world_width):
		fg_tiles[0][x] = 9
		fg_tiles[world_height - 1][x] = 9
	for y in range(world_height):
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
		"groups": groups_data, "polylines": poly_data}

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
