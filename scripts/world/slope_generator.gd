extends RefCounted

const BASE_BLOCKS: Array = [
	{"id": 1088, "artoffset": 260, "color": Color(0.95, 0.95, 0.95)},
	{"id": 9,    "artoffset": 9,   "color": Color(0.45, 0.45, 0.45)},
	{"id": 182,  "artoffset": 156, "color": Color(0.15, 0.15, 0.15)},
	{"id": 12,   "artoffset": 12,  "color": Color(0.85, 0.2, 0.2)},
	{"id": 1018, "artoffset": 205, "color": Color(0.9, 0.55, 0.1)},
	{"id": 13,   "artoffset": 13,  "color": Color(0.9, 0.85, 0.1)},
	{"id": 14,   "artoffset": 14,  "color": Color(0.2, 0.75, 0.2)},
	{"id": 15,   "artoffset": 15,  "color": Color(0.1, 0.7, 0.7)},
	{"id": 10,   "artoffset": 10,  "color": Color(0.2, 0.3, 0.85)},
	{"id": 11,   "artoffset": 11,  "color": Color(0.6, 0.2, 0.8)},
]

const SLOPE_ID_BASE: int = 2000
const TILE: int = 16
const CHUNK_TILES: int = 256

static func generate() -> Dictionary:
	var result: Dictionary = {}

	var atlas_images: Dictionary = {}
	for ci in range(2):
		var p: String = "res://assets/sprites/blocks_%d.png" % ci
		var tex = load(p)
		if tex:
			var img: Image = tex.get_image()
			if img:
				atlas_images[ci] = img

	for i in range(BASE_BLOCKS.size()):
		var entry: Dictionary = BASE_BLOCKS[i]
		var artoffset: int = entry.artoffset
		var fallback_color: Color = entry.color
		var chunk_idx: int = artoffset / CHUNK_TILES
		var local_off: int = artoffset % CHUNK_TILES

		var block_img: Image = null
		if atlas_images.has(chunk_idx):
			var atlas_img: Image = atlas_images[chunk_idx]
			var cols: int = atlas_img.get_width() / TILE
			var sx: int = (local_off % cols) * TILE
			var sy: int = (local_off / cols) * TILE
			if sx + TILE <= atlas_img.get_width() and sy + TILE <= atlas_img.get_height():
				block_img = atlas_img.get_region(Rect2i(sx, sy, TILE, TILE))

		if not block_img or block_img.get_width() == 0:
			block_img = Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
			block_img.fill(fallback_color)
			var border: Color = fallback_color.darkened(0.3)
			for p in range(TILE):
				block_img.set_pixel(p, 0, border)
				block_img.set_pixel(p, 15, border)
				block_img.set_pixel(0, p, border)
				block_img.set_pixel(15, p, border)

		# 1x1 slopes (IDs 2000-2039): 4 per block
		for orient in range(4):
			var sid: int = SLOPE_ID_BASE + i * 4 + orient
			result[sid] = ImageTexture.create_from_image(_make_slope(block_img, orient))

		# 1x2 slopes (IDs 2040-2119): 8 per block (4 orientations × left/right halves)
		# / ramp up-right: left tile = bottom half, right tile = top half
		# \ ramp up-left: left tile = top half, right tile = bottom half
		for orient in range(4):
			var left_id: int = 2040 + i * 8 + orient * 2
			var right_id: int = 2040 + i * 8 + orient * 2 + 1
			result[left_id] = ImageTexture.create_from_image(_make_half_slope(block_img, orient, 0))
			result[right_id] = ImageTexture.create_from_image(_make_half_slope(block_img, orient, 1))

	return result

static func _make_slope(source: Image, orientation: int) -> Image:
	var img: Image = source.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var border_color: Color = source.get_pixel(8, 15) if orientation < 2 else source.get_pixel(8, 0)
	border_color.a = 1.0

	for py in range(TILE):
		for px in range(TILE):
			var keep: bool = false
			match orientation:
				0: keep = py >= (15 - px)
				1: keep = py >= px
				2: keep = py <= (15 - px)
				3: keep = py <= px
			if not keep:
				img.set_pixel(px, py, Color(0, 0, 0, 0))

	var border_dark: Color = border_color.darkened(0.2)
	for k in range(TILE):
		var bx: int = k
		var by: int = 15 - k if (orientation == 0 or orientation == 2) else k
		img.set_pixel(bx, by, border_color)
		var by2: int = by + 1 if (orientation < 2) else by - 1
		if by2 >= 0 and by2 < TILE:
			img.set_pixel(bx, by2, border_dark)

	return img

static func _make_half_slope(source: Image, orientation: int, half: int) -> Image:
	# half=0: left tile, half=1: right tile
	# Together they span 2 tiles for a gentle slope
	var img: Image = source.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var border_color: Color = source.get_pixel(8, 15) if orientation < 2 else source.get_pixel(8, 0)
	border_color.a = 1.0

	for py in range(TILE):
		for px in range(TILE):
			var keep: bool = false
			# Each tile covers half the total rise (8px per tile)
			# Total ramp: 16px rise over 32px (2 tiles)
			var surface: float = 0.0
			match orientation:
				0:  # / up-right
					if half == 0:  # Left tile: y goes from 15 to 8
						surface = 15.0 - float(px) * 0.5
					else:  # Right tile: y goes from 7 to 0
						surface = 7.0 - float(px) * 0.5
					keep = float(py) >= surface
				1:  # \ up-left
					if half == 0:  # Left tile: y goes from 0 to 7
						surface = float(px) * 0.5
					else:  # Right tile: y goes from 8 to 15
						surface = 8.0 + float(px) * 0.5
					keep = float(py) >= surface
				2:  # / inv ceiling up-right
					if half == 0:
						surface = 15.0 - float(px) * 0.5
					else:
						surface = 7.0 - float(px) * 0.5
					keep = float(py) <= surface
				3:  # \ inv ceiling up-left
					if half == 0:
						surface = float(px) * 0.5
					else:
						surface = 8.0 + float(px) * 0.5
					keep = float(py) <= surface
			if not keep:
				img.set_pixel(px, py, Color(0, 0, 0, 0))

	# Draw border along the diagonal
	var border_dark: Color = border_color.darkened(0.2)
	for k in range(TILE):
		var bx: int = k
		var by: int = 0
		match orientation:
			0:
				by = int(15.0 - float(k) * 0.5) if half == 0 else int(7.0 - float(k) * 0.5)
			1:
				by = int(float(k) * 0.5) if half == 0 else int(8.0 + float(k) * 0.5)
			2:
				by = int(15.0 - float(k) * 0.5) if half == 0 else int(7.0 - float(k) * 0.5)
			3:
				by = int(float(k) * 0.5) if half == 0 else int(8.0 + float(k) * 0.5)
		if by >= 0 and by < TILE:
			img.set_pixel(bx, by, border_color)
			var by2: int = by + 1 if (orientation < 2) else by - 1
			if by2 >= 0 and by2 < TILE:
				img.set_pixel(bx, by2, border_dark)

	return img
