extends Node2D
## Renders gravity zone visual effects — all pixel art style
## OPTIMIZED: Pre-renders animation frames to cached textures.
## Instead of 11,000+ draw_rect calls per frame, draws 1 texture per zone.

# Animation: 8s loop at 20fps = 160 frames, all speeds are multiples of TAU/8
const CACHE_FRAMES: int = 800
const CACHE_FPS: float = 100.0
const FRAMES_PER_TICK: int = 20
# Shipped with game files — generated once during dev, read-only at runtime
const DISK_CACHE_DIR: String = "res://assets/gz_cache"
# Two caches: center (black hole) and boundary (zone effects), both at max size
const STD_CENTER_RADIUS: float = 100.0
const STD_ZONE_RADIUS: float = 512.0
const CENTER_MARGIN: int = 100
const ZONE_MARGIN: int = 2

var _loading_overlay: CanvasLayer = null
var _loading_label: Label = null
var _loading_bg: ColorRect = null
var is_loading: bool = false
var _center_textures: Array = []
var _boundary_textures: Array = []
var _build_phase: int = 0  # 0=center, 1=boundary, 2=done
var _build_idx: int = -1
var _loaded: bool = false

func _ready() -> void:
	z_index = -1
	WorldManager.gravity_zones.zones_changed.connect(_on_zones_changed)
	# Loading screen overlay
	_loading_overlay = CanvasLayer.new()
	_loading_overlay.layer = 50
	add_child(_loading_overlay)
	_loading_bg = ColorRect.new()
	_loading_bg.color = Color(0.03, 0.03, 0.08, 0.95)
	_loading_bg.anchors_preset = Control.PRESET_FULL_RECT
	_loading_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.add_child(_loading_bg)
	_loading_label = Label.new()
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_label.add_theme_font_size_override("font_size", 24)
	_loading_label.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	_loading_overlay.add_child(_loading_label)
	_loading_overlay.visible = false
	# Load shipped cache immediately
	if _try_load_from_disk():
		_loaded = true
		_build_phase = 2

func _on_zones_changed() -> void:
	queue_redraw()

func _try_load_from_disk() -> bool:
	if not FileAccess.file_exists(DISK_CACHE_DIR + "/center/f0.png"):
		return false
	if not FileAccess.file_exists(DISK_CACHE_DIR + "/boundary/f0.png"):
		return false
	for i in range(CACHE_FRAMES):
		var c_img: Image = Image.load_from_file(DISK_CACHE_DIR + "/center/f%d.png" % i)
		var b_img: Image = Image.load_from_file(DISK_CACHE_DIR + "/boundary/f%d.png" % i)
		if c_img == null or b_img == null:
			return false
		_center_textures.append(ImageTexture.create_from_image(c_img))
		_boundary_textures.append(ImageTexture.create_from_image(b_img))
	return true

func _save_to_disk() -> void:
	DirAccess.make_dir_recursive_absolute(DISK_CACHE_DIR + "/center")
	DirAccess.make_dir_recursive_absolute(DISK_CACHE_DIR + "/boundary")
	for i in range(_center_textures.size()):
		var img: Image = _center_textures[i].get_image()
		if img:
			img.save_png(DISK_CACHE_DIR + "/center/f%d.png" % i)
	for i in range(_boundary_textures.size()):
		var img: Image = _boundary_textures[i].get_image()
		if img:
			img.save_png(DISK_CACHE_DIR + "/boundary/f%d.png" % i)

func _process(_delta: float) -> void:
	if WorldManager.gravity_zones.zones.size() > 0:
		queue_redraw()

func _get_center_image_size() -> int:
	return int(ceil(STD_CENTER_RADIUS + CENTER_MARGIN)) * 2

func _blend_pixel(img: Image, x: int, y: int, col: Color) -> void:
	## Alpha-composite col on top of existing pixel at (x, y).
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if col.a <= 0.0:
		return
	var dst: Color = img.get_pixel(x, y)
	var sa: float = col.a
	var da: float = dst.a
	var out_a: float = sa + da * (1.0 - sa)
	if out_a < 0.001:
		return
	var out_r: float = (col.r * sa + dst.r * da * (1.0 - sa)) / out_a
	var out_g: float = (col.g * sa + dst.g * da * (1.0 - sa)) / out_a
	var out_b: float = (col.b * sa + dst.b * da * (1.0 - sa)) / out_a
	img.set_pixel(x, y, Color(out_r, out_g, out_b, minf(out_a, 1.0)))

func _render_center_frame(time: float) -> ImageTexture:
	## Render ONLY the black hole center (void + accretion disk + lensed ring + glow).
	## Boundary effects (border, pulsing rings, spirals, flow lines) draw live in _draw().
	const W: float = TAU / 8.0
	var void_r: int = int(round(STD_CENTER_RADIUS))
	var bright: float = 0.7

	var img_sz: int = _get_center_image_size()
	var img: Image = Image.create(img_sz, img_sz, false, Image.FORMAT_RGBA8)

	var center: Vector2 = Vector2(float(img_sz) / 2.0, float(img_sz) / 2.0)
	var ox: float = 0.0
	var oy: float = 0.0

	# --- Black hole center (3-pass: back ring, void+glow, front ring) ---
	for pass_idx in range(3):
		if pass_idx == 0 or pass_idx == 2:
			var ring_thick: float = maxf(8.0, float(void_r) * 0.35)
			var num_layers: int = maxi(10, int(ring_thick / 1.5))
			var total_budget: int = 8000
			var per_layer: int = total_budget / maxi(num_layers, 1)
			for layer in range(num_layers):
				var layer_t: float = float(layer) / float(maxi(num_layers - 1, 1))
				var layer_r: float = float(void_r) + 1.0 + layer_t * ring_thick
				var layer_count: int = mini(per_layer, int(layer_r * 4.0))
				var speed: float = lerpf(3.0 * W, 2.0 * W, layer_t)  # 3-2 rotations per loop
				for ai in range(layer_count):
					var a_angle: float = TAU * float(ai) / float(layer_count) + time * speed + float(layer) * 0.5
					var wobble: float = sin(a_angle * 3.0 + time * 3.0 * W + float(layer)) * (1.0 + layer_t)
					var a_r: float = layer_r + wobble
					var squash: float = lerpf(0.5, 0.25, layer_t)
					var stretch_x: float = lerpf(1.15, 1.3, layer_t)
					var hash_v: float = fmod(sin(float(ai) * 127.1 + float(layer) * 311.7) * 43758.5, 1.0)
					var scatter_r2: float = (hash_v - 0.5) * 2.5
					var scatter_a2: float = fmod(sin(float(ai) * 78.2 + float(layer) * 12.9) * 9381.3, 1.0) * 0.04
					var a_pos: Vector2 = center + Vector2(cos(a_angle + scatter_a2) * (a_r + scatter_r2) * stretch_x, sin(a_angle + scatter_a2) * (a_r + scatter_r2) * squash)
					if pass_idx == 0 and a_pos.y > center.y:
						continue
					if pass_idx == 2 and a_pos.y <= center.y:
						continue
					if pass_idx == 0 and a_pos.distance_to(center) < float(void_r):
						continue
					var a_bright: float = 0.5 + 0.5 * maxf(0, sin(a_angle * 1.5 + time * 4.0 * W + float(layer) * 0.7))
					var front_boost: float = 1.3 if pass_idx == 2 else 1.0
					# How close to the void edge (0=far, 1=touching)
					var void_prox: float = clampf(1.0 - (a_r - float(void_r)) / 10.0, 0.0, 1.0)
					# Base disk color
					var r_c: float = 1.0
					var g_c: float = lerpf(0.95, 0.4, layer_t) * a_bright
					var b_c: float = lerpf(0.7, 0.1, layer_t) * a_bright * a_bright
					# Near void: lerp toward ring's hot white-orange
					r_c = lerpf(r_c, 1.0, void_prox)
					g_c = lerpf(g_c, 0.75 * a_bright, void_prox)
					b_c = lerpf(b_c, 0.35 * a_bright, void_prox)
					var a_alpha: float = lerpf(1.0, 0.7, layer_t) * a_bright * bright * front_boost * (1.0 + void_prox * 0.5)
					_blend_pixel(img, int(floor(a_pos.x) - ox), int(floor(a_pos.y) - oy), Color(r_c, g_c, b_c, minf(a_alpha, 1.0)))

		elif pass_idx == 1:
			# Void core — solid black circle
			for v_py in range(-void_r, void_r + 1):
				var row_w: int = int(sqrt(float(void_r * void_r - v_py * v_py)))
				for v_px in range(-row_w, row_w + 1):
					var px: int = int(round(center.x) + v_px - int(ox))
					var py: int = int(round(center.y) + v_py - int(oy))
					if px >= 0 and px < img_sz and py >= 0 and py < img_sz:
						img.set_pixel(px, py, Color(0, 0, 0, 1))

			# Event horizon glow ring
			var eh_count: int = int(float(void_r) * TAU)
			for ei in range(eh_count):
				var e_angle: float = TAU * float(ei) / float(eh_count)
				var e_r: float = float(void_r) + 1.0 + sin(e_angle * 4.0 + time * 3.0 * W) * 0.5
				var e_pos: Vector2 = center + Vector2(cos(e_angle), sin(e_angle)) * e_r
				var e_pulse: float = 0.6 + 0.4 * sin(e_angle * 2.0 + time * 4.0 * W)
				var efx: int = int(floor(e_pos.x) - ox)
				var efy: int = int(floor(e_pos.y) - oy)
				var ec: Color = Color(1.0, 0.6 * e_pulse, 0.2 * e_pulse, e_pulse * bright)
				var ed: Color = Color(1.0, 0.6 * e_pulse, 0.2 * e_pulse, e_pulse * bright * 0.4)
				_blend_pixel(img, efx, efy, ec)
				_blend_pixel(img, efx - 1, efy, ed)
				_blend_pixel(img, efx + 1, efy, ed)
				_blend_pixel(img, efx, efy - 1, ed)
				_blend_pixel(img, efx, efy + 1, ed)


	# --- 3b. Full circumference lensed ring (drawn AFTER front disk so it's on top) ---
	var ring_layers: int = 16
	var ring_base_r: float = float(void_r) + 0.5
	var ring_thickness: float = maxf(3.0, float(void_r) * 0.2)
	for lr in range(ring_layers):
		var lr_t: float = float(lr) / float(ring_layers - 1)
		var layer_r: float = ring_base_r + lr_t * ring_thickness
		var layer_speed: float = lerpf(5.0 * W, 2.0 * W, lr_t)
		var pts_count: int = int(layer_r * TAU * 1.5) + 40
		for pi in range(pts_count):
			var p_angle: float = TAU * float(pi) / float(pts_count) + time * layer_speed + float(lr) * 0.3
			var hash_val: float = fmod(sin(float(pi) * 127.1 + float(lr) * 311.7) * 43758.5, 1.0)
			var scatter_r: float = (hash_val - 0.5) * 2.0
			var scatter_a: float = fmod(sin(float(pi) * 78.2 + float(lr) * 12.9) * 9381.3, 1.0) * 0.03
			var pr: float = layer_r + scatter_r * 1.2
			var pa: float = p_angle + scatter_a
			var p_pos: Vector2 = center + Vector2(cos(pa), sin(pa)) * pr
			var cos_pa: float = absf(cos(pa))
			var side_bright: float = 0.3 + 0.7 * cos_pa
			var pulse: float = 0.6 + 0.4 * sin(pa * 3.0 + time * 4.0 * W + float(lr) * 0.7)
			var b: float = side_bright * pulse
			var horiz: float = clampf((cos_pa - 0.3) / 0.7, 0.0, 1.0)
			var col_r2: float = 1.0
			var col_g2: float = lerpf(0.95, 0.15, lr_t) * b
			var col_b2: float = lerpf(0.65, 0.0, lr_t) * b * b
			col_g2 = lerpf(col_g2, lerpf(0.95, 0.4, lr_t) * b, horiz)
			col_b2 = lerpf(col_b2, lerpf(0.7, 0.1, lr_t) * b * b, horiz)
			var col_a2: float = b * bright * lerpf(1.0, 0.5, lr_t) * (1.0 + horiz * 0.4)
			_blend_pixel(img, int(floor(p_pos.x) - ox), int(floor(p_pos.y) - oy), Color(col_r2, col_g2, col_b2, col_a2))

	return ImageTexture.create_from_image(img)

func _get_boundary_image_size() -> int:
	return int(ceil(STD_ZONE_RADIUS + ZONE_MARGIN)) * 2

func _render_boundary_frame(time: float) -> ImageTexture:
	const W: float = TAU / 8.0
	var radius: float = STD_ZONE_RADIUS
	var void_r: float = STD_CENTER_RADIUS
	var bright: float = 0.7

	var img_sz: int = _get_boundary_image_size()
	var img: Image = Image.create(img_sz, img_sz, false, Image.FORMAT_RGBA8)
	var center: Vector2 = Vector2(float(img_sz) / 2.0, float(img_sz) / 2.0)
	var ox: float = 0.0
	var oy: float = 0.0

	# Zone boundary — swirling pixel ring
	var border_pts: int = int(radius * 2.5) + 20
	for bi in range(border_pts):
		var b_angle: float = TAU * float(bi) / float(border_pts) + time * W
		var b_wobble: float = sin(b_angle * 6.0 + time * 3.0 * W) * 1.5
		var b_pos: Vector2 = center + Vector2(cos(b_angle), sin(b_angle)) * (radius + b_wobble)
		var b_bright: float = 0.3 + 0.7 * maxf(0, sin(b_angle * 3.0 - time * 2.0 * W))
		var b_alpha: float = b_bright * 0.35
		_blend_pixel(img, int(floor(b_pos.x) - ox), int(floor(b_pos.y) - oy), Color(0.6, 0.3, 1.0, b_alpha))

	# Pulsing inward rings
	for i in range(4):
		var phase: float = fmod(time * 0.5 + float(i) * 0.25, 1.0)
		var ring_r: float = radius * (1.0 - phase)
		var ring_alpha: float = phase * (1.0 - phase) * 2.0 * 0.2
		var ring_pts: int = int(ring_r * 2.0) + 12
		for ri in range(ring_pts):
			var r_angle: float = TAU * float(ri) / float(ring_pts)
			var r_pos: Vector2 = center + Vector2(cos(r_angle), sin(r_angle)) * ring_r
			_blend_pixel(img, int(floor(r_pos.x) - ox), int(floor(r_pos.y) - oy), Color(0.6, 0.3, 1.0, ring_alpha))

	return ImageTexture.create_from_image(img)

func _draw() -> void:
	if not _loaded:
		return
	const W: float = TAU / 8.0
	var time: float = Time.get_ticks_msec() * 0.001
	var bright: float = 1.0 if GameState.is_edit_mode else 0.7
	var frame_f: float = fmod(time * CACHE_FPS, float(CACHE_FRAMES))
	var idx0: int = int(frame_f) % CACHE_FRAMES
	var idx1: int = (idx0 + 1) % CACHE_FRAMES
	var blend: float = frame_f - floor(frame_f)

	for gz in WorldManager.gravity_zones.zones:
		var center: Vector2 = gz.center
		var radius: float = gz.radius
		var void_r: float = gz.get("center_radius", 8.0)

		# Boundary effects (scaled by zone radius)
		if _boundary_textures.size() > idx0:
			var b_img_sz: float = float(_get_boundary_image_size())
			var b_scale: float = (radius + ZONE_MARGIN) / (STD_ZONE_RADIUS + ZONE_MARGIN)
			var b_sz: float = b_img_sz * b_scale
			var b_pos: Vector2 = center - Vector2(b_sz, b_sz) * 0.5
			var b_dest: Rect2 = Rect2(b_pos, Vector2(b_sz, b_sz))
			draw_texture_rect(_boundary_textures[idx0], b_dest, false)
			if blend > 0.01:
				draw_texture_rect(_boundary_textures[idx1], b_dest, false, Color(1, 1, 1, blend))

		# LIVE: Spirals + flow lines (span both scales — can't be cached)
		var spiral_count: int = mini(60, 24 + int(void_r))
		for si in range(spiral_count):
			var s_angle: float = TAU * float(si) / float(spiral_count) + time * W
			var s_phase: float = fmod(time * 0.5 + float(si) / float(spiral_count), 1.0)
			var accel: float = 1.0 - s_phase * s_phase * s_phase
			var s_r: float = maxf(radius * 0.8 + 9.0, void_r + 5.0) * accel * accel
			var spiral_twist: float = s_phase * 6.0
			var s_pos: Vector2 = center + Vector2(cos(s_angle + spiral_twist), sin(s_angle + spiral_twist)) * s_r
			if s_pos.distance_to(center) < void_r + 1.0:
				continue
			var fade: float = clampf(s_r / (void_r + 5.0), 0.0, 1.0)
			var s_alpha: float = s_phase * fade * 2.5 * bright
			draw_rect(Rect2(floor(s_pos.x), floor(s_pos.y), 1, 1), Color(lerpf(0.4, 1.0, s_phase), lerpf(0.6, 0.2, s_phase), lerpf(1.0, 0.0, s_phase), s_alpha))
		for i in range(8):
			var line_angle: float = TAU * float(i) / 8.0 + time * W
			var flow_phase: float = fmod(time * 0.375 + float(i) * 0.125, 1.0)
			var accel_phase: float = flow_phase * flow_phase * flow_phase
			var head_r: float = lerpf(radius, void_r + 3.0, accel_phase)
			var line_len: int = int(radius * 0.08) + 3
			var b_b: float = 0.3 + 0.7 * maxf(0, sin(line_angle * 3.0 - time * 2.0 * W))
			var l_a: float = (1.0 - flow_phase * 0.5) * b_b * 0.8 * bright
			var dir: Vector2 = Vector2(cos(line_angle), sin(line_angle))
			for li in range(line_len):
				var lr2: float = head_r + float(li)
				if lr2 > radius:
					continue
				var l_pos: Vector2 = center + dir * lr2
				draw_rect(Rect2(floor(l_pos.x), floor(l_pos.y), 1, 1), Color(0.6, 0.3, 1.0, l_a * (1.0 - float(li) / float(line_len))))

		# Black hole center (scaled by center_radius)
		if _center_textures.size() > idx0:
			var c_img_sz: float = float(_get_center_image_size())
			var c_scale: float = void_r / STD_CENTER_RADIUS
			var c_sz: float = c_img_sz * c_scale
			var c_pos: Vector2 = center - Vector2(c_sz, c_sz) * 0.5
			var c_dest: Rect2 = Rect2(c_pos, Vector2(c_sz, c_sz))
			draw_texture_rect(_center_textures[idx0], c_dest, false)
			if blend > 0.01:
				draw_texture_rect(_center_textures[idx1], c_dest, false, Color(1, 1, 1, blend))
