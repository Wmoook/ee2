extends CanvasLayer

const TILE_SIZE: int = 16
const THUMB_SIZE: int = 32
const THUMB_PAD: int = 4
const CELL_SIZE: int = THUMB_SIZE + THUMB_PAD
const PALETTE_COLS: int = 16
const PALETTE_ROWS: int = 6
const TAB_HEIGHT: int = 28
const PANEL_MARGIN: int = 8
const TILES_PER_CHUNK: int = 256

var mode_label: Label
var help_label: Label

# Palette UI nodes
var palette_panel: Panel
var tab_container: HBoxContainer
var grid_container: Control
var info_label: Label
var _tab_buttons: Array = []
var _block_buttons: Array = []
var _scroll_offset: int = 0

# Atlas textures (loaded once for thumbnails)
var _atlas_textures: Dictionary = {}
var _split_info: Dictionary = {
	"blocks": 2, "special": 4, "deco": 2, "bg": 2,
}
var _single_info: Dictionary = {
	"door": "res://assets/sprites/blocks_door.png",
	"effect": "res://assets/sprites/blocks_effect.png",
	"shadow": "res://assets/sprites/blocks_shadow.png",
	"mud": "res://assets/sprites/blocks_mud.png",
	"npc": "res://assets/sprites/blocks_npc.png",
	"team": "res://assets/sprites/blocks_team.png",
}

var _cam_pad: Control
var _cam_knob: ColorRect
var _cam_dragging: bool = false
var _cam_pad_center: Vector2 = Vector2.ZERO
const CAM_PAD_SIZE: float = 120.0
const CAM_PAD_RANGE: float = 200.0  # Max offset in pixels

func _ready() -> void:
	layer = 10
	_load_atlas_textures()
	_build_mode_label()
	_build_palette()
	_build_help_label()
	_build_camera_pad()
	_build_layer_label()
	_build_save_button()

	GameState.edit_mode_changed.connect(_on_edit)
	GameState.block_selected.connect(_on_block)
	_update_visibility()
	_update_layer_label()

func _load_atlas_textures() -> void:
	for atlas_name in _split_info:
		var chunks: int = _split_info[atlas_name]
		for i in range(chunks):
			var prefix: String = "blocks" if atlas_name == "blocks" else ("blocks_" + atlas_name)
			var path: String = "res://assets/sprites/%s_%d.png" % [prefix, i]
			var tex: Texture2D = load(path) as Texture2D
			if tex:
				_atlas_textures["%s_%d" % [atlas_name, i]] = tex
	for atlas_name in _single_info:
		var tex: Texture2D = load(_single_info[atlas_name]) as Texture2D
		if tex:
			_atlas_textures["%s_0" % atlas_name] = tex

func _build_mode_label() -> void:
	mode_label = Label.new()
	mode_label.text = "PLAY MODE"
	mode_label.position = Vector2(12, 8)
	mode_label.add_theme_font_size_override("font_size", 16)
	mode_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	mode_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	mode_label.add_theme_constant_override("shadow_offset_x", 1)
	mode_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(mode_label)

var layer_label: Label

func _build_layer_label() -> void:
	layer_label = Label.new()
	layer_label.position = Vector2(12, 48)
	layer_label.add_theme_font_size_override("font_size", 11)
	layer_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	layer_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	layer_label.add_theme_constant_override("shadow_offset_x", 1)
	layer_label.add_theme_constant_override("shadow_offset_y", 1)
	layer_label.visible = false
	add_child(layer_label)

func _update_layer_label() -> void:
	if not layer_label:
		return
	if GameState.is_edit_mode:
		layer_label.visible = true
		var bid: int = GameState.selected_block_id
		var layer_name: String = "Blocks"
		var z: int = -1
		var info: Dictionary = GameState.get_block_info(bid)
		var layer_str: String = info.get("layer", "foreground")
		if layer_str == "background":
			layer_name = "Background"
			z = -2
		elif GameState.is_action(bid) or GameState.is_key(bid) or GameState.is_door(bid):
			layer_name = "Action"
			z = 0
		elif bid == 0:
			layer_name = "Eraser"
			z = 0
		layer_label.text = "Z: %d (%s) | Player: Z1" % [z, layer_name]
	else:
		layer_label.visible = false

func _build_help_label() -> void:
	help_label = Label.new()
	help_label.position = Vector2(12, 28)
	help_label.add_theme_font_size_override("font_size", 10)
	help_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	help_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	help_label.add_theme_constant_override("shadow_offset_x", 1)
	help_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(help_label)
	_update_help_text()

func _build_palette() -> void:
	# Main palette panel - anchored to bottom of screen
	palette_panel = Panel.new()
	palette_panel.visible = false

	# Dark semi-transparent background style
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	style.border_color = Color(0.3, 0.3, 0.4, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	palette_panel.add_theme_stylebox_override("panel", style)

	# No preset - we position manually in _process
	palette_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(palette_panel)

	# VBox layout inside palette
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = PANEL_MARGIN
	vbox.offset_top = PANEL_MARGIN
	vbox.offset_right = -PANEL_MARGIN
	vbox.offset_bottom = -PANEL_MARGIN
	vbox.add_theme_constant_override("separation", 4)
	palette_panel.add_child(vbox)

	# Tab bar
	var tab_scroll: ScrollContainer = ScrollContainer.new()
	tab_scroll.custom_minimum_size = Vector2(0, TAB_HEIGHT)
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(tab_scroll)

	tab_container = HBoxContainer.new()
	tab_container.add_theme_constant_override("separation", 2)
	tab_scroll.add_child(tab_container)

	for i in range(GameState.get_category_count()):
		var btn: Button = Button.new()
		btn.text = GameState.get_category_name(i)
		btn.custom_minimum_size = Vector2(60, TAB_HEIGHT - 4)
		btn.add_theme_font_size_override("font_size", 11)
		_style_tab_button(btn, i == 0)
		btn.pressed.connect(_on_tab_pressed.bind(i))
		tab_container.add_child(btn)
		_tab_buttons.append(btn)

	# Separator line
	var sep: HSeparator = HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 2)
	var sep_style: StyleBoxFlat = StyleBoxFlat.new()
	sep_style.bg_color = Color(0.3, 0.3, 0.45, 0.4)
	sep_style.content_margin_top = 1.0
	sep_style.content_margin_bottom = 1.0
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	# Grid area
	grid_container = Control.new()
	grid_container.custom_minimum_size = Vector2(PALETTE_COLS * CELL_SIZE, PALETTE_ROWS * CELL_SIZE)
	vbox.add_child(grid_container)

	# Info bar at bottom
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.75))
	info_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	info_label.add_theme_constant_override("shadow_offset_x", 1)
	info_label.add_theme_constant_override("shadow_offset_y", 1)
	info_label.text = "LMB: Place | RMB: Erase | Scroll: Cycle | 1-9: Quick Select"
	vbox.add_child(info_label)

	# Populate grid with first category
	_populate_grid(0)

func _style_tab_button(btn: Button, active: bool) -> void:
	if active:
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = Color(0.22, 0.22, 0.35, 0.95)
		s.border_color = Color(0.45, 0.45, 0.7, 0.8)
		s.set_border_width_all(1)
		s.set_corner_radius_all(4)
		s.content_margin_left = 8.0
		s.content_margin_right = 8.0
		s.content_margin_top = 2.0
		s.content_margin_bottom = 2.0
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_stylebox_override("hover", s)
		btn.add_theme_stylebox_override("pressed", s)
		btn.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	else:
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = Color(0.12, 0.12, 0.18, 0.8)
		s.border_color = Color(0.25, 0.25, 0.35, 0.4)
		s.set_border_width_all(1)
		s.set_corner_radius_all(4)
		s.content_margin_left = 8.0
		s.content_margin_right = 8.0
		s.content_margin_top = 2.0
		s.content_margin_bottom = 2.0
		btn.add_theme_stylebox_override("normal", s)
		var sh: StyleBoxFlat = s.duplicate()
		sh.bg_color = Color(0.17, 0.17, 0.25, 0.9)
		btn.add_theme_stylebox_override("hover", sh)
		btn.add_theme_stylebox_override("pressed", s)
		btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
		btn.add_theme_color_override("font_hover_color", Color(0.75, 0.75, 0.85))

func _populate_grid(cat_index: int) -> void:
	# Clear existing block buttons
	for btn in _block_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_block_buttons.clear()
	_scroll_offset = 0

	var ids: Array = GameState.get_category_ids(cat_index)
	for i in range(ids.size()):
		var bid: int = ids[i]
		var col: int = i % PALETTE_COLS
		var row: int = i / PALETTE_COLS
		if row >= PALETTE_ROWS:
			break  # Visible rows limit (scroll could extend this later)

		var btn: Button = Button.new()
		btn.custom_minimum_size = Vector2(THUMB_SIZE, THUMB_SIZE)
		btn.size = Vector2(THUMB_SIZE, THUMB_SIZE)
		btn.position = Vector2(col * CELL_SIZE, row * CELL_SIZE)
		btn.tooltip_text = _get_block_name(bid)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		# Style the button
		_style_block_button(btn, bid == GameState.selected_block_id)

		# Add block texture as icon
		var tex: Texture2D = _make_block_thumbnail(bid)
		if tex:
			btn.icon = tex
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.expand_icon = true

		btn.pressed.connect(_on_block_pressed.bind(bid, i))
		grid_container.add_child(btn)
		_block_buttons.append(btn)

func _style_block_button(btn: Button, selected: bool) -> void:
	if selected:
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = Color(0.15, 0.2, 0.35, 0.95)
		s.border_color = Color(0.4, 0.6, 1.0, 0.9)
		s.set_border_width_all(2)
		s.set_corner_radius_all(3)
		s.content_margin_left = 2.0
		s.content_margin_right = 2.0
		s.content_margin_top = 2.0
		s.content_margin_bottom = 2.0
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_stylebox_override("hover", s)
		btn.add_theme_stylebox_override("pressed", s)
	else:
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = Color(0.1, 0.1, 0.15, 0.7)
		s.border_color = Color(0.2, 0.2, 0.3, 0.5)
		s.set_border_width_all(1)
		s.set_corner_radius_all(3)
		s.content_margin_left = 2.0
		s.content_margin_right = 2.0
		s.content_margin_top = 2.0
		s.content_margin_bottom = 2.0
		btn.add_theme_stylebox_override("normal", s)
		var sh: StyleBoxFlat = s.duplicate()
		sh.bg_color = Color(0.15, 0.15, 0.22, 0.85)
		sh.border_color = Color(0.35, 0.35, 0.5, 0.7)
		btn.add_theme_stylebox_override("hover", sh)
		var sp: StyleBoxFlat = s.duplicate()
		sp.bg_color = Color(0.12, 0.15, 0.25, 0.9)
		btn.add_theme_stylebox_override("pressed", sp)

func _make_block_thumbnail(block_id: int) -> Texture2D:
	if block_id == 0:
		# Eraser - draw a red X on transparent background
		var img: Image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for p in range(TILE_SIZE):
			if p >= 2 and p < TILE_SIZE - 2:
				img.set_pixel(p, p, Color(1, 0.2, 0.2, 0.9))
				img.set_pixel(TILE_SIZE - 1 - p, p, Color(1, 0.2, 0.2, 0.9))
				if p > 2 and p < TILE_SIZE - 3:
					img.set_pixel(p - 1, p, Color(1, 0.2, 0.2, 0.5))
					img.set_pixel(p + 1, p, Color(1, 0.2, 0.2, 0.5))
					img.set_pixel(TILE_SIZE - p, p, Color(1, 0.2, 0.2, 0.5))
					img.set_pixel(TILE_SIZE - 2 - p, p, Color(1, 0.2, 0.2, 0.5))
		return ImageTexture.create_from_image(img)

	# Custom blocks - return their texture directly
	if GameState.is_custom_block(block_id):
		return GameState.get_custom_block_texture(block_id)
	# Slope blocks - return the pre-generated ImageTexture directly
	if GameState.is_slope(block_id):
		return GameState.get_slope_texture(block_id)

	var info: Dictionary = GameState.get_block_info(block_id)
	if info.is_empty():
		return null

	var atlas_name: String = info.get("atlas", "blocks")
	var artoffset: int = info.get("artoffset", 0)
	var chunk: int = 0
	var local_off: int = artoffset
	if _split_info.has(atlas_name):
		chunk = local_off / TILES_PER_CHUNK
		local_off = local_off % TILES_PER_CHUNK

	var tex_key: String = "%s_%d" % [atlas_name, chunk]
	if not _atlas_textures.has(tex_key):
		return null

	var src_tex: Texture2D = _atlas_textures[tex_key]
	var cols: int = src_tex.get_width() / TILE_SIZE
	var sx: int = (local_off % cols) * TILE_SIZE
	var sy: int = (local_off / cols) * TILE_SIZE

	var atlas_tex: AtlasTexture = AtlasTexture.new()
	atlas_tex.atlas = src_tex
	atlas_tex.region = Rect2(sx, sy, TILE_SIZE, TILE_SIZE)
	return atlas_tex

func _get_block_name(block_id: int) -> String:
	if block_id == 0:
		return "Eraser"
	# Slope blocks (IDs 2000-2039)
	if block_id >= 2000 and block_id <= 2039:
		var slope_idx: int = block_id - 2000
		var base_idx: int = slope_idx / 4
		var orient: int = slope_idx % 4
		var base_names: Array = [
			"Basic White", "Basic Gray", "Basic Blue", "Basic Red",
			"Basic Orange", "Basic Yellow", "Basic Green", "Basic Cyan",
			"Basic Purple", "Basic Magenta",
		]
		var orient_names: Array = ["Right /", "Left \\", "Right Inv /", "Left Inv \\"]
		var bname: String = "Block"
		if base_idx < base_names.size():
			bname = base_names[base_idx]
		return "Slope %s %s" % [bname, orient_names[orient]]
	# Action blocks
	match block_id:
		1: return "Arrow Left"
		2: return "Arrow Up"
		3: return "Arrow Right"
		4: return "Dot (Zero Gravity)"
		6: return "Key Red"
		7: return "Key Green"
		8: return "Key Blue"
		114: return "Boost Left"
		115: return "Boost Right"
		116: return "Boost Up"
		117: return "Boost Down"
		411: return "Arrow Left (Alt)"
		412: return "Arrow Up (Alt)"
		413: return "Arrow Right (Alt)"
		414: return "Dot (Alt)"
		459: return "Slow Dot"
		460: return "Slow Dot (Alt)"
		1518: return "Arrow Down"
		1519: return "Arrow Down (Alt)"
		361: return "Spikes"
		370: return "Fire"
	# Doors
	match block_id:
		23: return "Red Door"
		24: return "Green Door"
		25: return "Blue Door"
		26: return "Red Gate"
		27: return "Green Gate"
		28: return "Blue Gate"
	# Generic
	if GameState.is_solid(block_id):
		return "Brick %d" % block_id
	if GameState.is_hazard(block_id):
		return "Hazard %d" % block_id
	var info: Dictionary = GameState.get_block_info(block_id)
	var layer_name: String = info.get("layer", "")
	if layer_name == "background":
		return "Background %d" % block_id
	if layer_name == "decoration":
		return "Decoration %d" % block_id
	return "Block %d" % block_id

func _on_tab_pressed(cat_index: int) -> void:
	GameState.selected_category = cat_index
	# Update tab styles
	for i in range(_tab_buttons.size()):
		_style_tab_button(_tab_buttons[i], i == cat_index)
	_populate_grid(cat_index)
	# Select first block in category
	var ids: Array = GameState.get_category_ids(cat_index)
	if ids.size() > 0:
		GameState.selected_palette_index = 0
		GameState.select_block(ids[0])

func _on_block_pressed(block_id: int, index: int) -> void:
	GameState.selected_palette_index = index
	GameState.select_block(block_id)
	_refresh_grid_selection()

func _refresh_grid_selection() -> void:
	var ids: Array = GameState.get_category_ids(GameState.selected_category)
	for i in range(_block_buttons.size()):
		if i < ids.size():
			_style_block_button(_block_buttons[i], ids[i] == GameState.selected_block_id)

func _on_edit(enabled: bool) -> void:
	if enabled:
		mode_label.text = "EDIT MODE"
		mode_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	else:
		mode_label.text = "PLAY MODE"
		mode_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	_update_visibility()
	_update_help_text()
	_update_layer_label()

func _on_block(id: int) -> void:
	if GameState.is_edit_mode:
		_refresh_grid_selection()
		_update_info()
		_update_layer_label()

func _update_visibility() -> void:
	palette_panel.visible = GameState.is_edit_mode

func _update_help_text() -> void:
	if GameState.is_edit_mode:
		help_label.text = "E: Play | G: God Mode | Ctrl+S: Save | Tab/Shift+Tab: Category"
	else:
		help_label.text = "WASD/Arrows: Move | Space: Jump (hold!) | E: Edit | G: God | Esc: Quit"

func _update_info() -> void:
	if info_label:
		var name: String = _get_block_name(GameState.selected_block_id)
		info_label.text = "%s (ID: %d) | LMB: Place | RMB: Erase | Scroll: Cycle | 1-9: Quick" % [name, GameState.selected_block_id]

func _input(event: InputEvent) -> void:
	if not GameState.is_edit_mode:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# Number keys 1-9 for quick block select within category
		var key: int = event.keycode
		if key >= KEY_1 and key <= KEY_9:
			var idx: int = key - KEY_1
			var ids: Array = GameState.get_category_ids(GameState.selected_category)
			if idx < ids.size():
				GameState.selected_palette_index = idx
				GameState.select_block(ids[idx])
				_refresh_grid_selection()
				_update_info()

func _cycle_category(dir: int) -> void:
	var count: int = GameState.get_category_count()
	var new_cat: int = (GameState.selected_category + dir + count) % count
	_on_tab_pressed(new_cat)

func _build_camera_pad() -> void:
	# 2D draggable pad on the left for camera offset
	_cam_pad = Control.new()
	_cam_pad.custom_minimum_size = Vector2(CAM_PAD_SIZE, CAM_PAD_SIZE)
	_cam_pad.size = Vector2(CAM_PAD_SIZE, CAM_PAD_SIZE)
	_cam_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cam_pad)

	# Background circle
	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(CAM_PAD_SIZE, CAM_PAD_SIZE)
	bg.color = Color(0.15, 0.15, 0.2, 0.5)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_pad.add_child(bg)

	# Center crosshair
	var cross_h: ColorRect = ColorRect.new()
	cross_h.size = Vector2(CAM_PAD_SIZE, 1)
	cross_h.position = Vector2(0, CAM_PAD_SIZE / 2)
	cross_h.color = Color(0.4, 0.4, 0.5, 0.3)
	cross_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_pad.add_child(cross_h)

	var cross_v: ColorRect = ColorRect.new()
	cross_v.size = Vector2(1, CAM_PAD_SIZE)
	cross_v.position = Vector2(CAM_PAD_SIZE / 2, 0)
	cross_v.color = Color(0.4, 0.4, 0.5, 0.3)
	cross_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_pad.add_child(cross_v)

	# Draggable knob
	_cam_knob = ColorRect.new()
	_cam_knob.size = Vector2(14, 14)
	_cam_knob.position = Vector2(CAM_PAD_SIZE / 2 - 7, CAM_PAD_SIZE / 2 - 7)
	_cam_knob.color = Color(0.6, 0.7, 1.0, 0.8)
	_cam_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_pad.add_child(_cam_knob)

	_cam_pad.gui_input.connect(_on_cam_pad_input)

func _on_cam_pad_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_cam_dragging = event.pressed
			if event.pressed:
				_update_cam_offset(event.position)
			else:
				# Double-click to reset
				pass
	if event is InputEventMouseMotion and _cam_dragging:
		_update_cam_offset(event.position)

func _update_cam_offset(pos: Vector2) -> void:
	var center: Vector2 = Vector2(CAM_PAD_SIZE / 2, CAM_PAD_SIZE / 2)
	var diff: Vector2 = pos - center
	# Clamp to pad radius
	var max_r: float = CAM_PAD_SIZE / 2 - 7
	if diff.length() > max_r:
		diff = diff.normalized() * max_r
	# Map to camera offset range
	GameState.camera_offset = diff / max_r * CAM_PAD_RANGE
	# Update knob position
	_cam_knob.position = center + diff - Vector2(7, 7)

var _save_btn: Button
var _save_label: Label

func _build_save_button() -> void:
	# Save button moved to block editor UI
	pass

func _on_save_pressed() -> void:
	var err: Error = WorldManager.save_to_file("user://world_save.json")
	if err == OK:
		_save_label.text = "Saved!"
		get_tree().create_timer(2.0).timeout.connect(func(): _save_label.text = "")
	else:
		_save_label.text = "Error!"

func _process(_delta: float) -> void:
	if not palette_panel:
		return

	# Position cam pad on left, vertically centered
	if _cam_pad:
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		_cam_pad.position = Vector2(12, vp_size.y / 2 - CAM_PAD_SIZE / 2)

	# Position palette at top-right
	if palette_panel.visible:
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		var panel_w: float = PALETTE_COLS * CELL_SIZE + PANEL_MARGIN * 2 + 16
		var panel_h: float = TAB_HEIGHT + PALETTE_ROWS * CELL_SIZE + 50 + PANEL_MARGIN * 2
		palette_panel.position = Vector2(vp_size.x - panel_w - 8, 8)
		palette_panel.size = Vector2(panel_w, panel_h)
