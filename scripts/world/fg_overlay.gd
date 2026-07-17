extends Node2D
## Draws foreground blocks ON TOP of the player smiley

var _renderer: Node2D = null

func set_renderer(r: Node2D) -> void:
	_renderer = r

## Redraw governor (mirrors world_renderer): the overlay is static — only
## content changes, camera view changes, or key-door flips repaint it.
var _content_dirty: bool = true
var _last_ct: Transform2D = Transform2D(1.0, Vector2(1e9, 1e9))
var _last_vp: Vector2 = Vector2.ZERO
var _last_keys: int = -1

func _ready() -> void:
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	WorldManager.tile_changed.connect(func(_a, _b, _c): _content_dirty = true)
	WorldManager.world_loaded.connect(func(): _content_dirty = true)

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
	var view_moved: bool = ct.x != _last_ct.x or ct.y != _last_ct.y \
			or ct.origin.distance_squared_to(_last_ct.origin) > 0.04
	if _content_dirty or view_moved or vp != _last_vp or keys != _last_keys:
		_last_ct = ct
		_last_vp = vp
		_last_keys = keys
		_content_dirty = false
		queue_redraw()

func _draw() -> void:
	if not _renderer:
		return
	if _renderer._grid_ready:
		return  # the renderer's overlay TileMapLayer (z=2) owns this now
	var r: Array = _renderer.get_visible_range()
	for y in range(r[1], r[3]):
		for x in range(r[0], r[2]):
			var fg_id: int = WorldManager.get_tile(x, y)
			if fg_id != 0 and GameState.is_solid(fg_id):
				var vid: int = _renderer._get_visual_id(fg_id)
				_draw_block(x, y, vid)

func _draw_block(x: int, y: int, block_id: int) -> void:
	var ts: int = 16
	var dest: Rect2 = Rect2(x * ts, y * ts, ts, ts)
	# Custom blocks (with warp)
	if GameState.is_custom_block(block_id):
		var ctex: Texture2D = GameState.get_custom_block_texture(block_id)
		if ctex:
			var warp: Vector2 = GameState.get_custom_block_warp(block_id)
			var wdest: Rect2 = Rect2(dest.position.x - warp.x, dest.position.y - warp.y, dest.size.x + warp.x * 2, dest.size.y + warp.y * 2)
			draw_texture_rect(ctex, wdest, false)
		return
	# Slope blocks use generated ImageTextures
	if GameState.is_slope(block_id):
		var slope_tex = GameState.get_slope_texture(block_id)
		if slope_tex:
			draw_texture_rect(slope_tex, dest, false)
		else:
			draw_rect(dest, Color(0.5, 0.5, 0.5))
		return
	var info: Dictionary = GameState.get_block_info(block_id)
	if info.is_empty():
		draw_rect(dest, Color(0.5, 0.5, 0.5))
		return
	var atlas_name: String = info.get("atlas", "blocks")
	var artoffset: int = info.get("artoffset", 0)
	var chunk: int = 0
	var local_off: int = artoffset
	if _renderer.split_info.has(atlas_name):
		chunk = local_off / _renderer.TILES_PER_CHUNK
		local_off = local_off % _renderer.TILES_PER_CHUNK
	var tex_key: String = "%s_%d" % [atlas_name, chunk]
	if not _renderer.textures.has(tex_key):
		draw_rect(dest, Color(0.4, 0.2, 0.4))
		return
	var tex: Texture2D = _renderer.textures[tex_key]
	var cols: int = tex.get_width() / ts
	var src: Rect2 = Rect2((local_off % cols) * ts, (local_off / cols) * ts, ts, ts)
	draw_texture_rect_region(tex, dest, src)
