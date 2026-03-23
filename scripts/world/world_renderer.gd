extends Node2D
## Renders EE world. BG layer draws behind player, FG layer draws in front.

const TILE_SIZE := 16
const CHUNK_PX := 4096
const TILES_PER_CHUNK: int = CHUNK_PX / TILE_SIZE

var textures: Dictionary = {}
var split_info: Dictionary = {
	"blocks": 2, "special": 4, "deco": 2, "bg": 2,
}
var single_info: Dictionary = {
	"door": "res://assets/sprites/blocks_door.png",
	"effect": "res://assets/sprites/blocks_effect.png",
	"shadow": "res://assets/sprites/blocks_shadow.png",
	"mud": "res://assets/sprites/blocks_mud.png",
	"npc": "res://assets/sprites/blocks_npc.png",
	"team": "res://assets/sprites/blocks_team.png",
}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -2  # BG behind player
	_load_textures()
	WorldManager.tile_changed.connect(func(_a, _b, _c): queue_redraw())
	WorldManager.bg_tile_changed.connect(func(_a, _b, _c): queue_redraw())
	WorldManager.world_loaded.connect(func(): queue_redraw())

func _load_textures() -> void:
	for atlas_name in split_info:
		var chunks: int = split_info[atlas_name]
		for i in range(chunks):
			var prefix: String = "blocks" if atlas_name == "blocks" else ("blocks_" + atlas_name)
			var path: String = "res://assets/sprites/%s_%d.png" % [prefix, i]
			var tex: Texture2D = load(path) as Texture2D
			if tex:
				textures["%s_%d" % [atlas_name, i]] = tex
	for atlas_name in single_info:
		var tex: Texture2D = load(single_info[atlas_name]) as Texture2D
		if tex:
			textures["%s_0" % atlas_name] = tex

func _process(_delta: float) -> void:
	queue_redraw()

func get_visible_range() -> Array:
	# Use canvas transform to get the ACTUAL rendered viewport area
	# (respects camera limits, unlike camera.global_position)
	var ct: Transform2D = get_viewport().get_canvas_transform()
	var vp_size: Vector2 = get_viewport_rect().size
	# Canvas transform maps world -> screen. Inverse maps screen -> world.
	var inv: Transform2D = ct.affine_inverse()
	var top_left: Vector2 = inv * Vector2.ZERO
	var bot_right: Vector2 = inv * vp_size
	return [
		maxi(0, int(floor(top_left.x / TILE_SIZE)) - 1),
		maxi(0, int(floor(top_left.y / TILE_SIZE)) - 1),
		mini(WorldManager.world_width, int(ceil(bot_right.x / TILE_SIZE)) + 1),
		mini(WorldManager.world_height, int(ceil(bot_right.y / TILE_SIZE)) + 1),
	]

func _draw() -> void:
	var r: Array = get_visible_range()
	# BG tiles
	for y in range(r[1], r[3]):
		for x in range(r[0], r[2]):
			var bg_id: int = WorldManager.get_bg_tile(x, y)
			if bg_id != 0:
				draw_block(x, y, bg_id, 0.55)
	# FG tiles also drawn here (behind player) for the base layer
	for y in range(r[1], r[3]):
		for x in range(r[0], r[2]):
			var fg_id: int = WorldManager.get_tile(x, y)
			if fg_id != 0:
				var rot: int = WorldManager.get_rotation(x, y)
				if rot != 0:
					_draw_block_rotated(x, y, fg_id, 1.0, rot)
				else:
					draw_block(x, y, fg_id, 1.0)

	# Draw polyline curves FIRST (so end cap blocks render on top)
	# Draw polyline curves: textured quads every 16px (no triangulation artifacts)
	for poly in WorldManager.polylines:
		var poly_pts: PackedVector2Array = poly.points
		var poly_norms: Array = poly.normals
		if poly_pts.size() >= 2:
			var half_w: float = 8.0
			# Look up block texture (custom or atlas)
			var curve_bid: int = poly.get("block_id", 9)
			var curve_tex: Texture2D = null
			var u0: float = 0.0
			var v0: float = 0.0
			var u1: float = 1.0
			var v1: float = 1.0
			if GameState.is_custom_block(curve_bid):
				curve_tex = GameState.get_custom_block_texture(curve_bid)
				# Full texture UV (0-1)
			else:
				var curve_info: Dictionary = GameState.get_block_info(curve_bid)
				var curve_atlas: String = curve_info.get("atlas", "blocks")
				var curve_artoff: int = curve_info.get("artoffset", 0)
				var curve_chunk: int = 0
				var curve_local: int = curve_artoff
				if split_info.has(curve_atlas):
					curve_chunk = curve_local / TILES_PER_CHUNK
					curve_local = curve_local % TILES_PER_CHUNK
				var ctex_key: String = "%s_%d" % [curve_atlas, curve_chunk]
				if textures.has(ctex_key):
					curve_tex = textures[ctex_key]
				var aw: float = curve_tex.get_width() if curve_tex else 256.0
				var ah: float = curve_tex.get_height() if curve_tex else 256.0
				var curve_cols: int = int(aw) / TILE_SIZE
				var csx: int = (curve_local % curve_cols) * TILE_SIZE
				var csy: int = (curve_local / curve_cols) * TILE_SIZE
				u0 = float(csx) / aw
				v0 = float(csy) / ah
				u1 = float(csx + TILE_SIZE) / aw
				v1 = float(csy + TILE_SIZE) / ah
			# Build + cache mesh: smooth edges from render_top/bot, tiling UV every 16px
			if not poly.has("_cached_mesh") and curve_tex:
				var r_top: PackedVector2Array = poly.get("render_top", PackedVector2Array())
				var r_bot: PackedVector2Array = poly.get("render_bot", PackedVector2Array())
				var r_dists: Array = poly.get("render_dists", [])
				if r_top.size() >= 2:
					var cmesh: ArrayMesh = ArrayMesh.new()
					var mverts: PackedVector2Array = PackedVector2Array()
					var muvs: PackedVector2Array = PackedVector2Array()
					# Truncate at last full 16px tile boundary
					var total_d: float = r_dists[-1] if r_dists.size() > 0 else 0.0
					var max_d: float = round(total_d / 16.0) * 16.0
					if max_d < 16.0:
						max_d = total_d  # Too short, show everything
					var prev_mt: Vector2 = r_top[0]
					var prev_mb: Vector2 = r_bot[0]
					var prev_md: float = 0.0
					for mi in range(1, r_top.size()):
						var md: float = r_dists[mi] if mi < r_dists.size() else prev_md + 1.0
						if md > max_d:
							# Interpolate to exact cutoff point
							var cut_t: float = (max_d - prev_md) / maxf(md - prev_md, 0.001)
							var cut_top: Vector2 = prev_mt.lerp(r_top[mi], cut_t)
							var cut_bot: Vector2 = prev_mb.lerp(r_bot[mi], cut_t)
							md = max_d
							# Use these as the final points (will be processed below)
							r_top[mi] = cut_top
							r_bot[mi] = cut_bot
						if md - prev_md < 0.5 and md < max_d:
							continue
						# Tiling UV: repeat every 16px, mirror every other tile for seamless pattern
						var tile_num_l: int = int(prev_md / 16.0)
						var tile_num_r: int = int(md / 16.0)
						var mirror: bool = (tile_num_l % 2) == 1
						var raw_uv_l: float = fmod(prev_md / 16.0, 1.0)
						var raw_uv_r: float = fmod(md / 16.0, 1.0)
						var uv_l: float
						var uv_r: float
						if mirror:
							uv_l = u0 + raw_uv_l * (u1 - u0)
							uv_r = u0 + raw_uv_r * (u1 - u0)
						else:
							uv_l = u1 - raw_uv_l * (u1 - u0)
							uv_r = u1 - raw_uv_r * (u1 - u0)
						# Handle UV wrap-around (tile boundary crossed when tile_num changes)
						if tile_num_r != tile_num_l:
							var wrap_t: float = (1.0 - fmod(prev_md / 16.0, 1.0)) / maxf((md - prev_md) / 16.0, 0.001)
							wrap_t = clampf(wrap_t, 0.0, 1.0)
							var mid_top: Vector2 = prev_mt.lerp(r_top[mi], wrap_t)
							var mid_bot: Vector2 = prev_mb.lerp(r_bot[mi], wrap_t)
							# First half: current tile direction
							var uv_end1: float = u0 if not mirror else u1  # End of current tile
							mverts.append(prev_mt); mverts.append(mid_top); mverts.append(mid_bot)
							mverts.append(prev_mt); mverts.append(mid_bot); mverts.append(prev_mb)
							muvs.append(Vector2(uv_l, v1)); muvs.append(Vector2(uv_end1, v1)); muvs.append(Vector2(uv_end1, v0))
							muvs.append(Vector2(uv_l, v1)); muvs.append(Vector2(uv_end1, v0)); muvs.append(Vector2(uv_l, v0))
							# Second half: next tile (opposite mirror)
							var mirror2: bool = not mirror
							var uv_start2: float = u0 if not mirror2 else u1
							mverts.append(mid_top); mverts.append(r_top[mi]); mverts.append(r_bot[mi])
							mverts.append(mid_top); mverts.append(r_bot[mi]); mverts.append(mid_bot)
							muvs.append(Vector2(uv_start2, v1)); muvs.append(Vector2(uv_r, v1)); muvs.append(Vector2(uv_r, v0))
							muvs.append(Vector2(uv_start2, v1)); muvs.append(Vector2(uv_r, v0)); muvs.append(Vector2(uv_start2, v0))
						else:
							# Normal quad (flipped V: top=v1, bot=v0)
							mverts.append(prev_mt); mverts.append(r_top[mi]); mverts.append(r_bot[mi])
							mverts.append(prev_mt); mverts.append(r_bot[mi]); mverts.append(prev_mb)
							muvs.append(Vector2(uv_l, v1)); muvs.append(Vector2(uv_r, v1)); muvs.append(Vector2(uv_r, v0))
							muvs.append(Vector2(uv_l, v1)); muvs.append(Vector2(uv_r, v0)); muvs.append(Vector2(uv_l, v0))
						prev_mt = r_top[mi]
						prev_mb = r_bot[mi]
						prev_md = md
						if md >= max_d:
							break
					if mverts.size() >= 3:
						var arrays: Array = []
						arrays.resize(Mesh.ARRAY_MAX)
						var v3: PackedVector3Array = PackedVector3Array()
						for mv in mverts:
							v3.append(Vector3(mv.x, mv.y, 0))
						arrays[Mesh.ARRAY_VERTEX] = v3
						arrays[Mesh.ARRAY_TEX_UV] = muvs
						cmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
						poly["_cached_mesh"] = cmesh
						poly["_cached_tex"] = curve_tex
			# Render: ONE draw_mesh call (zero per-frame computation)
			if poly.has("_cached_mesh"):
				draw_mesh(poly["_cached_mesh"], poly["_cached_tex"], Transform2D.IDENTITY)
			else:
				# Fallback
				draw_polyline(poly_pts, Color(0.5, 0.5, 0.52, 1.0), 16.0, true)
			# End caps are real blocks (placed in block_editor on confirm)
			if GameState.is_edit_mode:
				draw_polyline(poly_pts, Color(0.2, 0.8, 1.0, 0.4), 1.0, true)

	# Draw free (rotated/off-grid) blocks AFTER curves (end caps render on top)
	for fb in WorldManager.free_blocks:
		if fb.get("curve_visual", false):
			continue
		_draw_free_block(fb)

	# Draw freeform lines
	for line in WorldManager.lines:
		draw_line(line.start, line.end, line.color, line.width, true)

func _curve_uv(dist: float, cap_frac: float, uv0: float, uv1: float) -> float:
	## Tiling UV: repeat the block texture every 16px along the curve
	var uv_range: float = uv1 - uv0
	# dist is in pixels along the curve — tile every 16px
	var tile_t: float = fmod(dist / 16.0, 1.0)
	if tile_t < 0:
		tile_t += 1.0
	return uv0 + tile_t * uv_range

func draw_block(x: int, y: int, block_id: int, alpha: float) -> void:
	var dest: Rect2 = Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	# Door/gate visual swap when key is active
	var render_id: int = _get_visual_id(block_id)
	# Custom blocks (with optional warp for visual scale tuning)
	if GameState.is_custom_block(render_id):
		var ctex: Texture2D = GameState.get_custom_block_texture(render_id)
		if ctex:
			# Check for per-block warp (visual expansion, hitbox unchanged)
			var warp: Vector2 = GameState.get_custom_block_warp(render_id)
			var wdest: Rect2 = Rect2(dest.position.x - warp.x, dest.position.y - warp.y, dest.size.x + warp.x * 2, dest.size.y + warp.y * 2)
			draw_texture_rect(ctex, wdest, false, Color(1, 1, 1, alpha))
		return
	# Slope blocks use generated ImageTextures instead of atlas lookup
	if GameState.is_slope(render_id):
		var slope_tex = GameState.get_slope_texture(render_id)
		if slope_tex:
			draw_texture_rect(slope_tex, dest, false, Color(1, 1, 1, alpha))
		else:
			draw_rect(dest, Color(0.5, 0.5, 0.5, alpha))
		return
	var info: Dictionary = GameState.get_block_info(render_id)
	if info.is_empty():
		draw_rect(dest, Color(0.5, 0.5, 0.5, alpha))
		return
	var atlas_name: String = info.get("atlas", "blocks")
	var artoffset: int = info.get("artoffset", 0)
	var chunk: int = 0
	var local_off: int = artoffset
	if split_info.has(atlas_name):
		chunk = local_off / TILES_PER_CHUNK
		local_off = local_off % TILES_PER_CHUNK
	var tex_key: String = "%s_%d" % [atlas_name, chunk]
	if not textures.has(tex_key):
		draw_rect(dest, Color(0.4, 0.2, 0.4, alpha))
		return
	var tex: Texture2D = textures[tex_key]
	var cols: int = tex.get_width() / TILE_SIZE
	var src: Rect2 = Rect2((local_off % cols) * TILE_SIZE, (local_off / cols) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	draw_texture_rect_region(tex, dest, src, Color(1, 1, 1, alpha))

func draw_block_to(target: CanvasItem, x: int, y: int, block_id: int, alpha: float) -> void:
	var dest: Rect2 = Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	# Slope blocks use generated ImageTextures
	if GameState.is_slope(block_id):
		var slope_tex = GameState.get_slope_texture(block_id)
		if slope_tex:
			target.draw_texture_rect(slope_tex, dest, false, Color(1, 1, 1, alpha))
		else:
			target.draw_rect(dest, Color(0.5, 0.5, 0.5, alpha))
		return
	var info: Dictionary = GameState.get_block_info(block_id)
	if info.is_empty():
		target.draw_rect(dest, Color(0.5, 0.5, 0.5, alpha))
		return
	var atlas_name: String = info.get("atlas", "blocks")
	var artoffset: int = info.get("artoffset", 0)
	var chunk: int = 0
	var local_off: int = artoffset
	if split_info.has(atlas_name):
		chunk = local_off / TILES_PER_CHUNK
		local_off = local_off % TILES_PER_CHUNK
	var tex_key: String = "%s_%d" % [atlas_name, chunk]
	if not textures.has(tex_key):
		target.draw_rect(dest, Color(0.4, 0.2, 0.4, alpha))
		return
	var tex: Texture2D = textures[tex_key]
	var cols: int = tex.get_width() / TILE_SIZE
	var src: Rect2 = Rect2((local_off % cols) * TILE_SIZE, (local_off / cols) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	target.draw_texture_rect_region(tex, dest, src, Color(1, 1, 1, alpha))

func _draw_block_rotated(x: int, y: int, block_id: int, alpha: float, degrees: int) -> void:
	var render_id: int = _get_visual_id(block_id)
	var info: Dictionary = GameState.get_block_info(render_id)
	if info.is_empty():
		return
	var atlas_name: String = info.get("atlas", "blocks")
	var artoffset: int = info.get("artoffset", 0)
	var chunk: int = 0
	var local_off: int = artoffset
	if split_info.has(atlas_name):
		chunk = local_off / TILES_PER_CHUNK
		local_off = local_off % TILES_PER_CHUNK
	var tex_key: String = "%s_%d" % [atlas_name, chunk]
	if not textures.has(tex_key):
		return
	var tex: Texture2D = textures[tex_key]
	var cols: int = tex.get_width() / TILE_SIZE
	var sx: int = (local_off % cols) * TILE_SIZE
	var sy: int = (local_off / cols) * TILE_SIZE

	# Draw rotated: save transform, rotate around tile center, draw, restore
	var center: Vector2 = Vector2(x * TILE_SIZE + 8, y * TILE_SIZE + 8)
	draw_set_transform(center, deg_to_rad(degrees), Vector2.ONE)
	var src: Rect2 = Rect2(sx, sy, TILE_SIZE, TILE_SIZE)
	var dest: Rect2 = Rect2(-8, -8, TILE_SIZE, TILE_SIZE)
	draw_texture_rect_region(tex, dest, src, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)  # Reset

func _draw_free_block(fb: Dictionary) -> void:
	var pos: Vector2 = fb.pos
	var bid: int = fb.id
	var rot: float = fb.rotation
	var render_id: int = _get_visual_id(bid)
	# Custom blocks: same draw method as grid blocks but with rotation + optional mirror
	if GameState.is_custom_block(render_id):
		var ctex: Texture2D = GameState.get_custom_block_texture(render_id)
		if ctex:
			# Draw rotated block using polygon with UV (exact hitbox alignment)
			var center: Vector2 = pos + Vector2(8, 8)
			var rot_rad: float = deg_to_rad(rot)
			var cos_r: float = cos(rot_rad)
			var sin_r: float = sin(rot_rad)
			var flip: float = -1.0 if fb.get("flip_h", false) else 1.0
			# 4 corners of 16x16 block, rotated around center
			var corners: PackedVector2Array = PackedVector2Array()
			var uvs: PackedVector2Array = PackedVector2Array()
			for c in [Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]:
				var rx: float = c.x * flip * cos_r - c.y * sin_r
				var ry: float = c.x * flip * sin_r + c.y * cos_r
				corners.append(center + Vector2(rx, ry))
			# UV corners (full texture)
			if flip < 0:
				uvs.append(Vector2(1, 0)); uvs.append(Vector2(0, 0)); uvs.append(Vector2(0, 1)); uvs.append(Vector2(1, 1))
			else:
				uvs.append(Vector2(0, 0)); uvs.append(Vector2(1, 0)); uvs.append(Vector2(1, 1)); uvs.append(Vector2(0, 1))
			draw_colored_polygon(corners, Color.WHITE, uvs, ctex)
		return
	var info: Dictionary = GameState.get_block_info(render_id)
	if info.is_empty():
		return
	var atlas_name: String = info.get("atlas", "blocks")
	var artoffset: int = info.get("artoffset", 0)
	var chunk: int = 0
	var local_off: int = artoffset
	if split_info.has(atlas_name):
		chunk = local_off / TILES_PER_CHUNK
		local_off = local_off % TILES_PER_CHUNK
	var tex_key: String = "%s_%d" % [atlas_name, chunk]
	if not textures.has(tex_key):
		return
	var tex: Texture2D = textures[tex_key]
	var cols: int = tex.get_width() / TILE_SIZE
	var sx: int = (local_off % cols) * TILE_SIZE
	var sy: int = (local_off / cols) * TILE_SIZE
	var center: Vector2 = pos + Vector2(8, 8)
	var scale: Vector2 = Vector2.ONE
	if fb.get("curve_visual", false) or fb.get("curve", false):
		scale.x = 1.4  # Stretch along tangent to fill gaps between curve blocks
	draw_set_transform(center, deg_to_rad(rot), scale)
	# Dim blocks not in active group filter (edit mode only)
	var filter: int = WorldManager.active_group_filter
	if filter > 0 and GameState.is_edit_mode:
		var block_group: int = fb.get("group", -1)
		if block_group != filter:
			draw_texture_rect_region(tex, Rect2(-8, -8, TILE_SIZE, TILE_SIZE), Rect2(sx, sy, TILE_SIZE, TILE_SIZE), Color(1, 1, 1, 0.25))
		else:
			draw_texture_rect_region(tex, Rect2(-8, -8, TILE_SIZE, TILE_SIZE), Rect2(sx, sy, TILE_SIZE, TILE_SIZE))
	else:
		draw_texture_rect_region(tex, Rect2(-8, -8, TILE_SIZE, TILE_SIZE), Rect2(sx, sy, TILE_SIZE, TILE_SIZE))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _get_visual_id(block_id: int) -> int:
	# When key active: doors show as gates, gates show as doors
	var now: int = Time.get_ticks_msec()
	match block_id:
		23:  # Red door → red gate when red key active
			if WorldManager.key_timers.get("red", 0) > now: return 26
		24:  # Green door → green gate
			if WorldManager.key_timers.get("green", 0) > now: return 27
		25:  # Blue door → blue gate
			if WorldManager.key_timers.get("blue", 0) > now: return 28
		26:  # Red gate → red door when red key active
			if WorldManager.key_timers.get("red", 0) > now: return 23
		27:  # Green gate → green door
			if WorldManager.key_timers.get("green", 0) > now: return 24
		28:  # Blue gate → blue door
			if WorldManager.key_timers.get("blue", 0) > now: return 25
	return block_id

func set_hover_tile(_t: Vector2i) -> void:
	pass

func set_selected_block(_id: int) -> void:
	pass
