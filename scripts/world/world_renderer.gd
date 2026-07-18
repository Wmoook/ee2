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

## Redraw governor: the world layer is STATIC almost every frame — rebuilding
## the whole canvas item 60+ times a second made dense builds lag. We only
## redraw when something that can change pixels changes: world content, the
## camera view, key-door state, the group filter, or edit mode. Spinning free
## blocks keep continuous redraws while they exist (they animate every frame).
var _content_dirty: bool = true
var _fb_anim: bool = false
var _last_ct: Transform2D = Transform2D(1.0, Vector2(1e9, 1e9))
var _last_vp: Vector2 = Vector2.ZERO
var _last_keys: int = -1
var _last_filter: int = -1
var _last_edit: bool = false

func _mark_dirty() -> void:
	_content_dirty = true

# ---- TileMap grid pipeline ----
# Grid tiles live in engine TileMapLayers (chunked + retained natively): pans
# and zoom-outs rebuild NOTHING, and an edit touches one cell. Every block id
# is GPU-baked ONCE into a strip atlas using the very same draw routine the
# old immediate path used — the pixels are identical by construction. The old
# immediate grid loops remain as the pre-bake fallback (and for --headless).
const BAKE_COLS: int = 64
var _grid_ready: bool = false
var _ts: TileSet = null
var _id_coords: Dictionary = {}    # block_id -> Vector2i strip coords
var _bg_layer: TileMapLayer = null
var _fg_layer: TileMapLayer = null
var _ov_layer: TileMapLayer = null  # solid-on-top overlay (z=2, fg_overlay's job)
var _door_cells: Dictionary = {}    # Vector2i -> door/gate fg id (23..28)
var _grid_keys: int = 0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -2  # BG behind player
	_load_textures()
	WorldManager.tile_changed.connect(_on_tile_changed)
	WorldManager.bg_tile_changed.connect(_on_bg_tile_changed)
	WorldManager.world_loaded.connect(_on_world_loaded_grid)
	WorldManager.free_blocks_changed.connect(_mark_dirty)
	WorldManager.polylines_changed.connect(_mark_dirty)
	WorldManager.lines_changed.connect(_mark_dirty)
	GameState.edit_mode_changed.connect(func(_e: bool): _mark_dirty())
	if DisplayServer.get_name() != "headless":
		_start_grid_bake.call_deferred()

func _on_tile_changed(x: int, y: int, _id: int) -> void:
	_mark_dirty()
	if _grid_ready:
		if x == 0 and y == 0:
			_full_grid_sync()  # bulk ops signal with (0,0,0)
		else:
			_sync_fg_cell(x, y)

func _on_bg_tile_changed(x: int, y: int, _id: int) -> void:
	_mark_dirty()
	if _grid_ready:
		if x == 0 and y == 0:
			_full_grid_sync()
		else:
			_sync_bg_cell(x, y)

func _on_world_loaded_grid() -> void:
	_mark_dirty()
	if _grid_ready:
		_full_grid_sync()

func _start_grid_bake() -> void:
	# Every id that can appear in a cell: the ENTIRE block database (the world
	# BORDER is id 9 and the classic EE bricks aren't in the palette at all),
	# plus custom textures (maps place BG ids directly) and slopes.
	var ids: Dictionary = {}
	for dbid in GameState._block_db:
		if dbid is int and dbid > 0:
			ids[dbid] = true
	for pid in GameState.BLOCK_PALETTE:
		if pid > 0:
			ids[pid] = true
	for cid in GameState._custom_block_textures:
		if cid is int and cid > 0:
			ids[cid] = true
	for sid in GameState._slope_textures:
		if sid > 0:
			ids[sid] = true
	var id_list: Array = ids.keys()
	id_list.sort()
	var rows: int = int(ceil(float(id_list.size()) / float(BAKE_COLS)))
	for i in range(id_list.size()):
		_id_coords[id_list[i]] = Vector2i(i % BAKE_COLS, i / BAKE_COLS)
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(BAKE_COLS * TILE_SIZE, rows * TILE_SIZE)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(vp)
	var canvas: Node2D = Node2D.new()
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vp.add_child(canvas)
	canvas.draw.connect(func() -> void:
		for bid in _id_coords:
			var c: Vector2i = _id_coords[bid]
			draw_block_at(canvas, Rect2(c.x * TILE_SIZE, c.y * TILE_SIZE, TILE_SIZE, TILE_SIZE), bid))
	canvas.queue_redraw()
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	if img == null:
		return  # no render target (safety) — fallback path keeps drawing
	var strip: ImageTexture = ImageTexture.create_from_image(img)
	_ts = TileSet.new()
	_ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var src: TileSetAtlasSource = TileSetAtlasSource.new()
	src.texture = strip
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for bid in _id_coords:
		var c: Vector2i = _id_coords[bid]
		src.create_tile(c)
		# Alternatives 1/2/3 = 90/180/270 degree grid rotations
		src.create_alternative_tile(c, 1)
		src.get_tile_data(c, 1).transpose = true
		src.get_tile_data(c, 1).flip_h = true
		src.create_alternative_tile(c, 2)
		src.get_tile_data(c, 2).flip_h = true
		src.get_tile_data(c, 2).flip_v = true
		src.create_alternative_tile(c, 3)
		src.get_tile_data(c, 3).transpose = true
		src.get_tile_data(c, 3).flip_v = true
	_ts.add_source(src, 0)
	_bg_layer = TileMapLayer.new()
	_bg_layer.tile_set = _ts
	_bg_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bg_layer.modulate = Color(0.36, 0.37, 0.5)
	_bg_layer.z_as_relative = false
	_bg_layer.z_index = -2
	add_child(_bg_layer)
	_fg_layer = TileMapLayer.new()
	_fg_layer.tile_set = _ts
	_fg_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fg_layer.z_as_relative = false
	_fg_layer.z_index = -2
	add_child(_fg_layer)
	_ov_layer = TileMapLayer.new()
	_ov_layer.tile_set = _ts
	_ov_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ov_layer.z_as_relative = false
	_ov_layer.z_index = 2  # ABOVE the player, like fg_overlay always was
	add_child(_ov_layer)
	_grid_ready = true
	_full_grid_sync()
	_mark_dirty()  # immediate-path grid loops stop; repaint the rest

func _rot_alt(x: int, y: int) -> int:
	var deg: int = WorldManager.get_rotation(x, y)
	var q: int = int(round(float(deg) / 90.0)) % 4
	if q < 0:
		q += 4
	return q

func _sync_fg_cell(x: int, y: int) -> void:
	var cell: Vector2i = Vector2i(x, y)
	var fg: int = WorldManager.get_tile(x, y)
	if fg >= 23 and fg <= 28:
		_door_cells[cell] = fg
	else:
		_door_cells.erase(cell)
	if fg == 0 or not _id_coords.has(_get_visual_id(fg)):
		_fg_layer.erase_cell(cell)
		_ov_layer.erase_cell(cell)
		return
	var vid: int = _get_visual_id(fg)
	var alt: int = _rot_alt(x, y)
	_fg_layer.set_cell(cell, 0, _id_coords[vid], alt)
	if GameState.is_solid(fg):
		_ov_layer.set_cell(cell, 0, _id_coords[vid], alt)
	else:
		_ov_layer.erase_cell(cell)

func _sync_bg_cell(x: int, y: int) -> void:
	var cell: Vector2i = Vector2i(x, y)
	var bg: int = WorldManager.get_bg_tile(x, y)
	if bg == 0 or not _id_coords.has(bg):
		_bg_layer.erase_cell(cell)
		return
	_bg_layer.set_cell(cell, 0, _id_coords[bg], 0)

func _full_grid_sync() -> void:
	_bg_layer.clear()
	_fg_layer.clear()
	_ov_layer.clear()
	_door_cells.clear()
	for y in range(WorldManager.world_height):
		for x in range(WorldManager.world_width):
			if WorldManager.get_tile(x, y) != 0:
				_sync_fg_cell(x, y)
			if WorldManager.get_bg_tile(x, y) != 0:
				_sync_bg_cell(x, y)

func _refresh_door_cells() -> void:
	for cell in _door_cells:
		_sync_fg_cell(cell.x, cell.y)

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
	var ct: Transform2D = get_viewport().get_canvas_transform()
	var vp: Vector2 = get_viewport_rect().size
	var now: int = Time.get_ticks_msec()
	var keys: int = 0
	if WorldManager.key_timers.get("red", 0) > now:
		keys |= 1
	if WorldManager.key_timers.get("green", 0) > now:
		keys |= 2
	if WorldManager.key_timers.get("blue", 0) > now:
		keys |= 4
	# View "changed" = zoom/basis change, or ≥0.2px of accumulated camera
	# travel since the last draw (the follow-lerp drifts by sub-pixel amounts
	# forever — exact compares forced a full redraw every single frame)
	var view_moved: bool = ct.x != _last_ct.x or ct.y != _last_ct.y \
			or ct.origin.distance_squared_to(_last_ct.origin) > 0.04
	if _grid_ready and keys != _grid_keys:
		_grid_keys = keys
		_refresh_door_cells()  # door<->gate visuals flip on key transitions
	if _content_dirty or _fb_anim or view_moved or vp != _last_vp \
			or keys != _last_keys or WorldManager.active_group_filter != _last_filter \
			or GameState.is_edit_mode != _last_edit:
		_last_ct = ct
		_last_vp = vp
		_last_keys = keys
		_last_filter = WorldManager.active_group_filter
		_last_edit = GameState.is_edit_mode
		_content_dirty = false
		queue_redraw()

func _view_world_rect() -> Rect2:
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var tl: Vector2 = inv * Vector2.ZERO
	var br: Vector2 = inv * get_viewport_rect().size
	return Rect2(tl, br - tl)

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

var perf_redraws: int = 0  # perf introspection (stress test reads this)

func _draw() -> void:
	perf_redraws += 1
	var r: Array = get_visible_range()
	var vr: Rect2 = _view_world_rect().grow(32.0)  # cull margin: rotation/warp/caps
	_fb_anim = false
	# Grid tiles live in TileMapLayers once the bake lands; this immediate
	# path only covers the first pre-bake frames (and headless runs).
	if not _grid_ready:
		# BG tiles: drawn OPAQUE but heavily darkened and cooled so the back
		# layer is unmistakable at a glance
		for y in range(r[1], r[3]):
			for x in range(r[0], r[2]):
				var bg_id: int = WorldManager.get_bg_tile(x, y)
				if bg_id != 0:
					draw_block(x, y, bg_id, 1.0, Color(0.36, 0.37, 0.5))
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
		if poly.get("collision_only", false):
			continue  # Skip collision-only polylines (no visual)
		# Off-screen curves cost nothing (bbox vs camera view)
		if poly.has("bbox_min"):
			var pbmin: Vector2 = poly.bbox_min
			var pbmax: Vector2 = poly.bbox_max
			if not vr.intersects(Rect2(pbmin, pbmax - pbmin).grow(14.0)):
				continue
		var poly_pts: PackedVector2Array = poly.points
		var poly_norms: Array = poly.normals
		if poly_pts.size() >= 2:
			var half_w: float = 8.0  # Curve tiles are EXACTLY block-sized (16px)
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
					# The editor truncates splines to a 16px tile boundary, so
					# round() lands exactly on total_d — the ribbon is always
					# whole tiles and the end-cap block continues the pattern
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
						# Merge dense points — but ONLY when the edges barely moved:
						# round-join arc steps advance ~0 arc distance yet sweep
						# real pixels and must be emitted
						if md - prev_md < 0.5 and md < max_d \
								and r_top[mi].distance_squared_to(prev_mt) < 0.25 \
								and r_bot[mi].distance_squared_to(prev_mb) < 0.25:
							continue
						# Tiling UV: repeat every 16px, mirror every other tile.
						# WALK every 16px boundary inside this chord — a chord can
						# cross SEVERAL (old coarse-decimated curves have ~30px
						# chords), and any un-cut boundary smeared the texture's
						# edge pixels across the whole tile (dark streak glitch).
						var seg_d: float = prev_md
						var seg_top: Vector2 = prev_mt
						var seg_bot: Vector2 = prev_mb
						var chord: float = maxf(md - prev_md, 0.001)
						while true:
							var tile_n: int = int(seg_d / 16.0)
							var tile_end: float = float(tile_n + 1) * 16.0
							var piece_end: float = minf(md, tile_end)
							var pt_t: float = clampf((piece_end - prev_md) / chord, 0.0, 1.0)
							var piece_top: Vector2 = prev_mt.lerp(r_top[mi], pt_t)
							var piece_bot: Vector2 = prev_mb.lerp(r_bot[mi], pt_t)
							var raw_l: float = (seg_d - float(tile_n) * 16.0) / 16.0
							var raw_r: float = (piece_end - float(tile_n) * 16.0) / 16.0
							var uv_l: float
							var uv_r: float
							if (tile_n % 2) == 1:
								uv_l = u0 + raw_l * (u1 - u0)
								uv_r = u0 + raw_r * (u1 - u0)
							else:
								uv_l = u1 - raw_l * (u1 - u0)
								uv_r = u1 - raw_r * (u1 - u0)
							mverts.append(seg_top); mverts.append(piece_top); mverts.append(piece_bot)
							mverts.append(seg_top); mverts.append(piece_bot); mverts.append(seg_bot)
							muvs.append(Vector2(uv_l, v1)); muvs.append(Vector2(uv_r, v1)); muvs.append(Vector2(uv_r, v0))
							muvs.append(Vector2(uv_l, v1)); muvs.append(Vector2(uv_r, v0)); muvs.append(Vector2(uv_l, v0))
							if piece_end >= md - 0.0001:
								break
							seg_d = piece_end
							seg_top = piece_top
							seg_bot = piece_bot
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
						poly["_actual_tile_count"] = int(round(max_d / 16.0))
			# Render: ONE draw_mesh call (zero per-frame computation)
			if poly.has("_cached_mesh"):
				draw_mesh(poly["_cached_mesh"], poly["_cached_tex"], Transform2D.IDENTITY)
			else:
				# Fallback
				draw_polyline(poly_pts, Color(0.5, 0.5, 0.52, 1.0), 16.0, true)
			# End caps are real blocks (placed in block_editor on confirm)
			if GameState.is_edit_mode:
				draw_polyline(poly_pts, Color(0.2, 0.8, 1.0, 0.4), 1.0, true)

	# Draw free blocks: BG layer first (behind), then FG layer on top.
	# Off-screen free blocks are skipped; spinning ones keep redraws alive.
	for fb in WorldManager.free_blocks:
		if fb.get("curve_visual", false) or fb.get("curve_collision", false):
			continue
		if fb.get("spin", 0.0) != 0.0:
			_fb_anim = true
		if not vr.has_point(fb.pos):
			continue
		if fb.get("bg", false):
			_draw_free_block(fb, 0.55)  # BG at reduced opacity
	for fb in WorldManager.free_blocks:
		if fb.get("curve_visual", false) or fb.get("curve_collision", false):
			continue
		if not vr.has_point(fb.pos):
			continue
		if not fb.get("bg", false):
			_draw_free_block(fb)

	# Draw freeform lines (only the ones crossing the view)
	for line in WorldManager.lines:
		var lmin: Vector2 = Vector2(minf(line.start.x, line.end.x), minf(line.start.y, line.end.y))
		var lmax: Vector2 = Vector2(maxf(line.start.x, line.end.x), maxf(line.start.y, line.end.y))
		if not vr.intersects(Rect2(lmin, lmax - lmin).grow(line.width)):
			continue
		draw_line(line.start, line.end, line.color, line.width, true)

func draw_block_at(ci: CanvasItem, dest: Rect2, block_id: int) -> void:
	## EXACT single-tile visual (same routine as the immediate grid path) at
	## an arbitrary dest rect — the strip bake uses this so TileMap cells are
	## pixel-identical to what draw_block produced.
	if GameState.is_custom_block(block_id):
		var ctex: Texture2D = GameState.get_custom_block_texture(block_id)
		if ctex:
			ci.draw_texture_rect(ctex, dest, false)
		return
	if GameState.is_slope(block_id):
		var slope_tex = GameState.get_slope_texture(block_id)
		if slope_tex:
			ci.draw_texture_rect(slope_tex, dest, false)
		return
	var info: Dictionary = GameState.get_block_info(block_id)
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
	var src: Rect2 = Rect2((local_off % cols) * TILE_SIZE, (local_off / cols) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	ci.draw_texture_rect_region(tex, dest, src)

func _curve_uv(dist: float, cap_frac: float, uv0: float, uv1: float) -> float:
	## Tiling UV: repeat the block texture every 16px along the curve
	var uv_range: float = uv1 - uv0
	# dist is in pixels along the curve — tile every 16px
	var tile_t: float = fmod(dist / 16.0, 1.0)
	if tile_t < 0:
		tile_t += 1.0
	return uv0 + tile_t * uv_range

func draw_block(x: int, y: int, block_id: int, alpha: float, tint: Color = Color(1, 1, 1)) -> void:
	var dest: Rect2 = Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	# Door/gate visual swap when key is active
	var render_id: int = _get_visual_id(block_id)
	var mod: Color = Color(tint.r, tint.g, tint.b, alpha)
	# Custom blocks (with optional warp for visual scale tuning)
	if GameState.is_custom_block(render_id):
		var ctex: Texture2D = GameState.get_custom_block_texture(render_id)
		if ctex:
			# Check for per-block warp (visual expansion, hitbox unchanged)
			var warp: Vector2 = GameState.get_custom_block_warp(render_id)
			var wdest: Rect2 = Rect2(dest.position.x - warp.x, dest.position.y - warp.y, dest.size.x + warp.x * 2, dest.size.y + warp.y * 2)
			draw_texture_rect(ctex, wdest, false, mod)
		return
	# Slope blocks use generated ImageTextures instead of atlas lookup
	if GameState.is_slope(render_id):
		var slope_tex = GameState.get_slope_texture(render_id)
		if slope_tex:
			draw_texture_rect(slope_tex, dest, false, mod)
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
	draw_texture_rect_region(tex, dest, src, mod)

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

func _draw_free_block(fb: Dictionary, alpha: float = 1.0) -> void:
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
			var is_flipped: bool = fb.get("flip_h", false)
			# 4 corners of 16x16 block + warp, rotated around center
			var warp: Vector2 = GameState.get_custom_block_warp(render_id)
			var hw: float = 8.0 + warp.x
			var hh: float = 8.0 + warp.y
			var corners: PackedVector2Array = PackedVector2Array()
			var uvs: PackedVector2Array = PackedVector2Array()
			# Corners stay the same (geometry unchanged), only UV flips
			for c in [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]:
				var rx: float = c.x * cos_r - c.y * sin_r
				var ry: float = c.x * sin_r + c.y * cos_r
				corners.append(center + Vector2(rx, ry))
			if is_flipped:
				uvs.append(Vector2(1, 0)); uvs.append(Vector2(0, 0)); uvs.append(Vector2(0, 1)); uvs.append(Vector2(1, 1))
			else:
				uvs.append(Vector2(0, 0)); uvs.append(Vector2(1, 0)); uvs.append(Vector2(1, 1)); uvs.append(Vector2(0, 1))
			draw_colored_polygon(corners, Color(1, 1, 1, alpha), uvs, ctex)
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
