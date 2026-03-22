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

	# Draw free (rotated/off-grid) blocks
	for fb in WorldManager.free_blocks:
		_draw_free_block(fb)

	# Draw freeform lines (always visible, not just edit mode)
	for line in WorldManager.lines:
		draw_line(line.start, line.end, line.color, line.width, true)

func draw_block(x: int, y: int, block_id: int, alpha: float) -> void:
	var dest: Rect2 = Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	# Door/gate visual swap when key is active
	var render_id: int = _get_visual_id(block_id)
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
		scale.x = 1.25  # Stretch along tangent to fill gaps between curve blocks
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
