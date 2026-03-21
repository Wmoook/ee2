extends Node2D
## Draws foreground blocks ON TOP of the player smiley

var _renderer: Node2D = null

func set_renderer(r: Node2D) -> void:
	_renderer = r

func _ready() -> void:
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	WorldManager.tile_changed.connect(func(_a, _b, _c): queue_redraw())
	WorldManager.world_loaded.connect(func(): queue_redraw())

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not _renderer:
		return
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
