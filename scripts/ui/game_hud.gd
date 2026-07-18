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

var _palette_collapsed: bool = false
var _palette_slide: float = 0.0  # 0 = visible, 1 = hidden
var _palette_toggle_btn: Button

func _ready() -> void:
	layer = 10
	_load_atlas_textures()
	_build_mode_label()
	_build_palette()
	_build_help_label()
	_build_camera_pad()
	_build_layer_label()
	_build_save_button()
	_build_zoom_buttons()

	_build_chat()

	# Register clickable HUD controls so the block editor's mouse-over check
	# tests their REAL rects (prevents painting blocks through the UI).
	for c in [palette_panel, _palette_toggle_btn, _cam_pad, _zoom_container, _chat_input]:
		if c:
			c.add_to_group("editor_ui_block")

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
	mode_label.text = ""
	mode_label.position = Vector2(12, 8)
	mode_label.add_theme_font_size_override("font_size", 16)
	mode_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	mode_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	mode_label.add_theme_constant_override("shadow_offset_x", 1)
	mode_label.add_theme_constant_override("shadow_offset_y", 1)
	mode_label.visible = false
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
	help_label.visible = false
	add_child(help_label)

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
		_style_tab_button(btn, i == 0, i)
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

	# Toggle button to collapse/expand palette
	_palette_toggle_btn = Button.new()
	_palette_toggle_btn.text = ">"
	_palette_toggle_btn.custom_minimum_size = Vector2(24, 40)
	_palette_toggle_btn.add_theme_font_size_override("font_size", 16)
	_palette_toggle_btn.focus_mode = Control.FOCUS_NONE
	_palette_toggle_btn.visible = false
	var tog_style: StyleBoxFlat = StyleBoxFlat.new()
	tog_style.bg_color = Color(0.12, 0.12, 0.2, 0.9)
	tog_style.border_color = Color(0.3, 0.3, 0.45, 0.6)
	tog_style.set_border_width_all(1)
	tog_style.set_corner_radius_all(4)
	_palette_toggle_btn.add_theme_stylebox_override("normal", tog_style)
	_palette_toggle_btn.pressed.connect(func():
		_palette_collapsed = not _palette_collapsed
		_palette_toggle_btn.text = "<" if _palette_collapsed else ">"
	)
	add_child(_palette_toggle_btn)

func _style_tab_button(btn: Button, active: bool, cat_index: int = -1) -> void:
	# Pack tabs carry their theme color — active tabs glow with it
	var accent: Color = GameState.get_category_color(cat_index) if cat_index >= 0 else Color(0.45, 0.45, 0.7)
	if active:
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.26, 0.95)
		s.border_color = accent
		s.set_border_width_all(1)
		s.border_width_bottom = 3
		s.set_corner_radius_all(4)
		s.content_margin_left = 8.0
		s.content_margin_right = 8.0
		s.content_margin_top = 2.0
		s.content_margin_bottom = 2.0
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_stylebox_override("hover", s)
		btn.add_theme_stylebox_override("pressed", s)
		btn.add_theme_color_override("font_color", Color(accent.r * 0.5 + 0.5, accent.g * 0.5 + 0.5, accent.b * 0.5 + 0.5))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	else:
		var s: StyleBoxFlat = StyleBoxFlat.new()
		s.bg_color = Color(0.12, 0.12, 0.18, 0.8)
		s.border_color = Color(accent.r * 0.4, accent.g * 0.4, accent.b * 0.4, 0.5)
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
		btn.add_theme_color_override("font_color", Color(0.62, 0.62, 0.7))
		btn.add_theme_color_override("font_hover_color", Color(0.85, 0.85, 0.92))

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
	# Custom pack blocks carry real names (with pack context)
	var cname: String = GameState.custom_block_name(block_id)
	if cname != "":
		return cname
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
		_style_tab_button(_tab_buttons[i], i == cat_index, i)
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
	if _palette_toggle_btn:
		_palette_toggle_btn.visible = GameState.is_edit_mode

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
	# Chat toggle with Enter
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if _chat_visible:
				# Submit is handled by text_submitted signal
				pass
			else:
				_open_chat()
				get_viewport().set_input_as_handled()
				return
		elif event.keycode == KEY_ESCAPE and _chat_visible:
			_close_chat()
			get_viewport().set_input_as_handled()
			return
	# Block all game input while chat is open
	if _chat_visible:
		return
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

var _chat_container: VBoxContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _chat_visible: bool = false
var _chat_messages: Array = []
const MAX_CHAT_MESSAGES: int = 50

var _zoom_container: HBoxContainer
var _rotate_btn: Button
var _gravity_btn: Button
var _gravity_node: Node = null
var _zoom_label: Label
var _trails_btn: Button

func _build_zoom_buttons() -> void:
	_zoom_container = HBoxContainer.new()
	_zoom_container.add_theme_constant_override("separation", 4)
	add_child(_zoom_container)

	var btn_style: StyleBoxFlat = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.12, 0.12, 0.18, 0.85)
	btn_style.border_color = Color(0.3, 0.3, 0.45, 0.6)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)

	var zoom_out_btn: Button = Button.new()
	zoom_out_btn.text = "-"
	zoom_out_btn.custom_minimum_size = Vector2(32, 32)
	zoom_out_btn.add_theme_font_size_override("font_size", 18)
	zoom_out_btn.add_theme_stylebox_override("normal", btn_style)
	zoom_out_btn.focus_mode = Control.FOCUS_NONE
	zoom_out_btn.pressed.connect(_on_zoom_out)
	_zoom_container.add_child(zoom_out_btn)

	_zoom_label = Label.new()
	_zoom_label.custom_minimum_size = Vector2(40, 32)
	_zoom_label.add_theme_font_size_override("font_size", 12)
	_zoom_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_zoom_label.text = "3x"
	_zoom_container.add_child(_zoom_label)

	var zoom_in_btn: Button = Button.new()
	zoom_in_btn.text = "+"
	zoom_in_btn.custom_minimum_size = Vector2(32, 32)
	zoom_in_btn.add_theme_font_size_override("font_size", 18)
	zoom_in_btn.add_theme_stylebox_override("normal", btn_style)
	zoom_in_btn.focus_mode = Control.FOCUS_NONE
	zoom_in_btn.pressed.connect(_on_zoom_in)
	_zoom_container.add_child(zoom_in_btn)

	# Spacer
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(12, 0)
	_zoom_container.add_child(spacer)

	# Trails toggle
	_trails_btn = Button.new()
	_trails_btn.text = "Trails ON"
	_trails_btn.custom_minimum_size = Vector2(72, 32)
	_trails_btn.add_theme_font_size_override("font_size", 11)
	_trails_btn.add_theme_stylebox_override("normal", btn_style)
	_trails_btn.focus_mode = Control.FOCUS_NONE
	_trails_btn.pressed.connect(_on_trails_toggle)
	_zoom_container.add_child(_trails_btn)

	# Ball rotation toggle (next to Trails)
	_rotate_btn = Button.new()
	_rotate_btn.text = "Rotate ON"
	_rotate_btn.custom_minimum_size = Vector2(80, 32)
	_rotate_btn.add_theme_font_size_override("font_size", 11)
	_rotate_btn.add_theme_stylebox_override("normal", btn_style)
	_rotate_btn.focus_mode = Control.FOCUS_NONE
	_rotate_btn.pressed.connect(_on_rotate_toggle)
	_zoom_container.add_child(_rotate_btn)

	# BLOCK GRAVITY toggle — offline sandbox only (never the shared world).
	# ON: everything falls, curves crumble. Exiting the world restores it.
	if not GameState.battle_mode and not NetPlay.online:
		_gravity_btn = Button.new()
		_gravity_btn.text = "Gravity OFF"
		_gravity_btn.custom_minimum_size = Vector2(88, 32)
		_gravity_btn.add_theme_font_size_override("font_size", 11)
		_gravity_btn.add_theme_stylebox_override("normal", btn_style)
		_gravity_btn.focus_mode = Control.FOCUS_NONE
		_gravity_btn.pressed.connect(_on_gravity_toggle)
		_zoom_container.add_child(_gravity_btn)

func _get_camera() -> Camera2D:
	return get_viewport().get_camera_2d()

func _on_zoom_in() -> void:
	var cam: Camera2D = _get_camera()
	if cam:
		cam.zoom = clampf(cam.zoom.x + 0.5, 0.5, 10.0) * Vector2.ONE
		_zoom_label.text = "%gx" % cam.zoom.x

func _build_chat() -> void:
	_chat_container = VBoxContainer.new()
	_chat_container.add_theme_constant_override("separation", 4)
	add_child(_chat_container)

	# Chat log (shows recent messages)
	_chat_log = RichTextLabel.new()
	_chat_log.custom_minimum_size = Vector2(320, 150)
	_chat_log.size = Vector2(320, 150)
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_log.add_theme_font_size_override("normal_font_size", 12)
	# Invisible chat backdrop — messages float over the world (shadows keep
	# them readable without the dark box)
	var log_style: StyleBoxFlat = StyleBoxFlat.new()
	log_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	log_style.content_margin_left = 6.0
	log_style.content_margin_right = 6.0
	log_style.content_margin_top = 4.0
	log_style.content_margin_bottom = 4.0
	_chat_log.add_theme_stylebox_override("normal", log_style)
	_chat_log.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_chat_log.add_theme_constant_override("shadow_offset_x", 1)
	_chat_log.add_theme_constant_override("shadow_offset_y", 1)
	_chat_container.add_child(_chat_log)

	# Chat input (hidden until Enter pressed)
	_chat_input = LineEdit.new()
	_chat_input.custom_minimum_size = Vector2(320, 28)
	_chat_input.placeholder_text = "Type a message..."
	_chat_input.add_theme_font_size_override("font_size", 12)
	_chat_input.visible = false
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_container.add_child(_chat_input)

	NetworkManager.chat_received.connect(_on_chat_received)

func _on_chat_received(sender_name: String, message: String) -> void:
	_chat_messages.append({"name": sender_name, "text": message})
	if _chat_messages.size() > MAX_CHAT_MESSAGES:
		_chat_messages.pop_front()
	_update_chat_log()

func _update_chat_log() -> void:
	_chat_log.clear()
	for msg in _chat_messages:
		_chat_log.append_text("[color=#6cb4ee]%s:[/color] %s\n" % [msg.name, msg.text])

func _on_chat_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		_close_chat()
		return
	NetworkManager.send_chat(text.strip_edges())
	_chat_input.text = ""
	_close_chat()

func _open_chat() -> void:
	_chat_visible = true
	_chat_input.visible = true
	_chat_input.grab_focus()

func _close_chat() -> void:
	_chat_visible = false
	_chat_input.visible = false
	_chat_input.release_focus()
	_chat_input.text = ""

func _on_trails_toggle() -> void:
	GameState.trails_enabled = not GameState.trails_enabled
	_trails_btn.text = "Trails ON" if GameState.trails_enabled else "Trails OFF"

func _on_rotate_toggle() -> void:
	GameState.rotation_enabled = not GameState.rotation_enabled
	_rotate_btn.text = "Rotate ON" if GameState.rotation_enabled else "Rotate OFF"

func _on_gravity_toggle() -> void:
	if _gravity_node != null and is_instance_valid(_gravity_node):
		_gravity_node.queue_free()
		_gravity_node = null
		_gravity_btn.text = "Gravity OFF"
		return
	# First activation this visit: snapshot the world so leaving restores it
	if GameState.gravity_snapshot.is_empty():
		GameState.gravity_snapshot = WorldManager.serialize_world()
	var grav: GravityMode = GravityMode.new()
	grav.attached = true
	grav.name = "BlockGravity"
	get_parent().add_child(grav)
	_gravity_node = grav
	_gravity_btn.text = "Gravity ON"

func _on_zoom_out() -> void:
	var cam: Camera2D = _get_camera()
	if cam:
		cam.zoom = clampf(cam.zoom.x - 0.5, 0.5, 10.0) * Vector2.ONE
		_zoom_label.text = "%gx" % cam.zoom.x

func _process(_delta: float) -> void:
	if not palette_panel:
		return

	# Position cam pad on left, vertically centered (hidden in 1v1 battles —
	# the camera stays locked on the fight)
	if _cam_pad:
		_cam_pad.visible = not GameState.battle_mode
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		_cam_pad.position = Vector2(12, vp_size.y / 2 - CAM_PAD_SIZE / 2)

	# Position zoom buttons bottom-left
	if _zoom_container:
		var vp_size2: Vector2 = get_viewport().get_visible_rect().size
		_zoom_container.position = Vector2(12, vp_size2.y - 44)

	# Position chat bottom-right
	if _chat_container:
		var vp_size3: Vector2 = get_viewport().get_visible_rect().size
		_chat_container.position = Vector2(vp_size3.x - 332, vp_size3.y - 200)

	# Animate palette slide
	var target_slide: float = 1.0 if _palette_collapsed else 0.0
	_palette_slide = lerpf(_palette_slide, target_slide, _delta * 10.0)
	if absf(_palette_slide - target_slide) < 0.01:
		_palette_slide = target_slide

	# Position palette at top-right (slides off-screen when collapsed)
	var vp4: Vector2 = get_viewport().get_visible_rect().size
	var panel_w: float = PALETTE_COLS * CELL_SIZE + PANEL_MARGIN * 2 + 16
	var panel_h: float = TAB_HEIGHT + PALETTE_ROWS * CELL_SIZE + 50 + PANEL_MARGIN * 2
	var slide_offset: float = (panel_w + 16) * _palette_slide
	if palette_panel.visible:
		palette_panel.position = Vector2(vp4.x - panel_w - 8 + slide_offset, 8)
		palette_panel.size = Vector2(panel_w, panel_h)
	if _palette_toggle_btn and _palette_toggle_btn.visible:
		_palette_toggle_btn.position = Vector2(vp4.x - panel_w - 8 + slide_offset - 28, 8)
