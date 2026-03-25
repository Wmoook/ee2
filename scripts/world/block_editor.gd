extends Node2D

var _hover: Vector2i = Vector2i(-1, -1)
var _drag_start: Vector2i = Vector2i(-1, -1)
var _shift_dragging: bool = false
var _last_place: Vector2i = Vector2i(-999, -999)

# Line drawing mode
var _line_mode: bool = false
var _line_start: Vector2 = Vector2(-1, -1)
var _line_drawing: bool = false

# Curve tool
var _curve_mode: bool = false
var _curve_points: Array = []  # Up to 3 world-space points
var _curve_preview: Array = []  # Preview block positions + rotations

# Selection mode
var _selection: Rect2i = Rect2i()
var _has_selection: bool = false
var _sel_start: Vector2i = Vector2i()
var _sel_dragging: bool = false

# Rotation wheel
var _rot_dragging: bool = false
var _rot_angle: float = 0.0
var _move_dragging: bool = false
var _move_start: Vector2i = Vector2i()
var _move_blocks: Array = []
var _rot_last_snap: int = 0  # Last snapped rotation count
const ROT_WHEEL_RADIUS: float = 40.0

# Aligned placement mode
var _align_mode: bool = true
var _align_angle: float = 0.0
var _align_origin: Vector2 = Vector2.ZERO
var _align_block_id: int = 0
# Aligned selection (in rotated local grid coords)
var _align_sel_start: Vector2 = Vector2.ZERO
var _align_sel_end: Vector2 = Vector2.ZERO
var _align_sel_dragging: bool = false
var _align_has_sel: bool = false
var _align_drag_angle: float = 0.0
var _align_wheel_pos: Vector2 = Vector2.ZERO
var _align_sel_indices: Array = []
var _align_move_start: Vector2 = Vector2.ZERO
var _last_align_place: Vector2 = Vector2(-99999, -99999)
# Ctrl+drag line tool
var _ctrl_line_start: Vector2 = Vector2.ZERO
var _ctrl_line_active: bool = false
# Gravity zone tool
var _grav_zone_mode: bool = false
var _grav_zone_dragging: bool = false
var _grav_zone_phase: int = 0  # 0=not placing, 1=sizing center (shift), 2=sizing radius
var _grav_zone_center: Vector2 = Vector2.ZERO
var _grav_zone_center_r: float = 8.0
var _grav_zone_btn: Button

var _spin_btn: Button
var _spin_slider: HSlider
var _spin_label: Label
var _spin_panel: VBoxContainer
var _align_btn: Button
var _reset_btn: Button
var _angle_spin: SpinBox
var _ui_layer: CanvasLayer
var _spin_speed_val: float = 45.0

# Group system
var _group_btn: Button
var _group_panel: VBoxContainer
var _group_name_edit: LineEdit
var _selected_group_id: int = -1
# Group filter stored on WorldManager.active_group_filter

# Undo system
var _undo_stack: Array = []
const MAX_UNDO: int = 50

func _save_undo() -> void:
	var state: Dictionary = {}
	# Snapshot free blocks
	var fb_copy: Array = []
	for fb in WorldManager.free_blocks:
		fb_copy.append(fb.duplicate())
	state["free_blocks"] = fb_copy
	# Snapshot grid tiles (only non-zero)
	var tiles: Array = []
	for y in range(WorldManager.world_height):
		for x in range(WorldManager.world_width):
			var bid: int = WorldManager.get_tile(x, y)
			var rot: int = WorldManager.get_rotation(x, y)
			if bid != 0 or rot != 0:
				tiles.append({"x": x, "y": y, "id": bid, "rot": rot})
	state["tiles"] = tiles
	# Snapshot polylines
	var poly_copy: Array = []
	for pl in WorldManager.polylines:
		poly_copy.append(pl.duplicate(true))
	state["polylines"] = poly_copy
	state["gravity_zones"] = WorldManager.gravity_zones.duplicate_zones()
	state["align_angle"] = _align_angle
	state["align_origin"] = _align_origin
	state["sel_indices"] = _align_sel_indices.duplicate()
	state["has_sel"] = _align_has_sel
	state["wheel_pos"] = _align_wheel_pos
	_undo_stack.append(state)
	if _undo_stack.size() > MAX_UNDO:
		_undo_stack.pop_front()

func _do_undo() -> void:
	if _undo_stack.is_empty():
		return
	var state: Dictionary = _undo_stack.pop_back()
	# Restore free blocks
	WorldManager.free_blocks.clear()
	for fb in state["free_blocks"]:
		WorldManager.free_blocks.append(fb.duplicate())
	# Clear all grid tiles first
	for y in range(WorldManager.world_height):
		for x in range(1, WorldManager.world_width - 1):
			if y > 0 and y < WorldManager.world_height - 1:
				WorldManager.net_set_tile(x, y, 0)
				WorldManager.set_rotation(x, y, 0)
	# Restore saved tiles
	for t in state["tiles"]:
		WorldManager.net_set_tile(t.x, t.y, t.id)
		WorldManager.set_rotation(t.x, t.y, t.rot)
	# Restore polylines
	if state.has("polylines"):
		WorldManager.polylines.clear()
		for pl in state["polylines"]:
			WorldManager.polylines.append(pl.duplicate(true))
	# Restore gravity zones
	if state.has("gravity_zones"):
		WorldManager.gravity_zones.restore_zones(state["gravity_zones"])
	# Restore align state
	if state.has("align_angle"):
		_align_angle = state["align_angle"]
		_angle_spin.set_value_no_signal(_align_angle)
	if state.has("align_origin"):
		_align_origin = state["align_origin"]
	# Restore selection
	_free_originals.clear()
	_rot_dragging = false
	_move_dragging = false
	if state.has("sel_indices") and state.get("has_sel", false):
		_align_sel_indices = state["sel_indices"].duplicate()
		_align_has_sel = true
		_has_selection = true
		_align_wheel_pos = state.get("wheel_pos", Vector2.ZERO)
	else:
		_deselect()
	queue_redraw()

func _ready() -> void:
	z_index = 5
	GameState.edit_mode_changed.connect(func(_e: bool): queue_redraw())
	# UI layer for screen-space buttons
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 11
	add_child(_ui_layer)
	# Spin panel on right side
	_spin_panel = VBoxContainer.new()
	_spin_panel.visible = false
	_ui_layer.add_child(_spin_panel)

	_spin_label = Label.new()
	_spin_label.text = "Speed: 45 deg/s"
	_spin_label.add_theme_font_size_override("font_size", 11)
	_spin_label.add_theme_color_override("font_color", Color.WHITE)
	_spin_panel.add_child(_spin_label)

	_spin_slider = HSlider.new()
	_spin_slider.min_value = -360
	_spin_slider.max_value = 360
	_spin_slider.step = 5
	_spin_slider.value = 45
	_spin_slider.custom_minimum_size = Vector2(140, 20)
	_spin_slider.value_changed.connect(_on_spin_speed_changed)
	_spin_panel.add_child(_spin_slider)

	_spin_btn = Button.new()
	_spin_btn.text = "Spin Object"
	_spin_btn.custom_minimum_size = Vector2(140, 28)
	_spin_btn.add_theme_font_size_override("font_size", 11)
	_spin_btn.pressed.connect(_on_spin_pressed)
	_spin_panel.add_child(_spin_btn)

	_align_btn = Button.new()
	_align_btn.text = "Align Grid (ON)"
	_align_btn.toggle_mode = true
	_align_btn.button_pressed = true
	_align_btn.custom_minimum_size = Vector2(140, 28)
	_align_btn.add_theme_font_size_override("font_size", 11)
	_align_btn.pressed.connect(_on_align_pressed)
	_spin_panel.add_child(_align_btn)

	# Grid angle spinbox
	var angle_row: HBoxContainer = HBoxContainer.new()
	_spin_panel.add_child(angle_row)
	var angle_lbl: Label = Label.new()
	angle_lbl.text = "Grid °"
	angle_lbl.add_theme_font_size_override("font_size", 11)
	angle_lbl.add_theme_color_override("font_color", Color.WHITE)
	angle_row.add_child(angle_lbl)
	_angle_spin = SpinBox.new()
	_angle_spin.min_value = -360
	_angle_spin.max_value = 360
	_angle_spin.step = 5
	_angle_spin.value = 0
	_angle_spin.suffix = "°"
	_angle_spin.custom_minimum_size = Vector2(90, 24)
	_angle_spin.add_theme_font_size_override("font_size", 11)
	_angle_spin.value_changed.connect(func(val: float):
		_align_angle = val
		queue_redraw()
	)
	angle_row.add_child(_angle_spin)

	# Group row: number + add button
	var group_row: HBoxContainer = HBoxContainer.new()
	_spin_panel.add_child(group_row)
	var _group_id_spin: SpinBox = SpinBox.new()
	_group_id_spin.name = "GroupIdSpin"
	_group_id_spin.min_value = 1
	_group_id_spin.max_value = 99
	_group_id_spin.step = 1
	_group_id_spin.value = 1
	_group_id_spin.custom_minimum_size = Vector2(55, 24)
	_group_id_spin.add_theme_font_size_override("font_size", 10)
	group_row.add_child(_group_id_spin)
	_group_btn = Button.new()
	_group_btn.text = "Add to Group"
	_group_btn.custom_minimum_size = Vector2(85, 24)
	_group_btn.add_theme_font_size_override("font_size", 10)
	_group_btn.pressed.connect(_on_group_pressed)
	group_row.add_child(_group_btn)

	# Group properties panel (placeholder - properties added later)
	_group_panel = VBoxContainer.new()
	_group_panel.visible = false
	_spin_panel.add_child(_group_panel)

	# Reset grid button removed - use Ctrl+R instead

	# Clear world button
	var _clear_btn: Button = Button.new()
	_clear_btn.name = "ClearWorldBtn"
	_clear_btn.text = "Clear World"
	_clear_btn.size = Vector2(90, 25)
	_clear_btn.add_theme_font_size_override("font_size", 10)
	_clear_btn.pressed.connect(func():
		_save_undo()
		WorldManager.free_blocks.clear()
		WorldManager.block_groups.clear()
		WorldManager.polylines.clear()
		WorldManager.lines.clear()
		WorldManager.gravity_zones.clear()
		for y in range(1, WorldManager.world_height - 1):
			for x in range(1, WorldManager.world_width - 1):
				WorldManager.net_set_tile(x, y, 0)
				WorldManager.net_set_bg_tile(x, y, 0)
				WorldManager.set_rotation(x, y, 0)
		_free_originals.clear()
		_deselect()
		queue_redraw())
	_ui_layer.add_child(_clear_btn)

	# Save world button
	var _save_btn: Button = Button.new()
	_save_btn.name = "SaveWorldBtn"
	_save_btn.text = "Save World"
	_save_btn.size = Vector2(90, 25)
	_save_btn.add_theme_font_size_override("font_size", 10)
	_save_btn.pressed.connect(func():
		var err = WorldManager.save_to_file("user://world_save.json")
		push_warning("SAVE result=%d" % err)
	)
	_ui_layer.add_child(_save_btn)

	# Help button
	var _help_btn: Button = Button.new()
	_help_btn.name = "HelpBtn"
	_help_btn.text = "?"
	_help_btn.size = Vector2(25, 25)
	_help_btn.add_theme_font_size_override("font_size", 12)
	_help_btn.pressed.connect(func():
		var hlp: Label = _ui_layer.get_node_or_null("HelpLabel")
		if hlp:
			hlp.visible = not hlp.visible
	)
	_ui_layer.add_child(_help_btn)

	# Gravity Zone button
	_grav_zone_btn = Button.new()
	_grav_zone_btn.name = "GravZoneBtn"
	_grav_zone_btn.text = "Gravity Zone"
	_grav_zone_btn.size = Vector2(100, 25)
	_grav_zone_btn.add_theme_font_size_override("font_size", 10)
	_grav_zone_btn.pressed.connect(func():
		_grav_zone_mode = not _grav_zone_mode
		_curve_mode = false
		_line_mode = false
		_deselect()
		queue_redraw()
	)
	_ui_layer.add_child(_grav_zone_btn)

	# Help label (hidden by default)
	var _help_label: Label = Label.new()
	_help_label.name = "HelpLabel"
	_help_label.visible = false
	_help_label.text = "SHORTCUTS:\n\nE - Toggle Edit Mode\nShift+Click - Select block\nShift+Drag - Box select\nClick+Drag - Move selected\nCtrl+Drag - Free move\nCtrl+Click+Drag - Line tool\nArrow Keys - Nudge (16px)\nShift+Arrows - Fine nudge (1.6px)\nDelete/Backspace - Delete selected\nEscape - Deselect\nCtrl+Z - Undo\nCtrl+R - Reset grid to 0°\nCtrl+Scroll - Zoom\nR - Rotate 90°\nB - Toggle hitboxes\nG - God mode\nN - Toggle name\nScroll - Cycle blocks\n1-9 - Quick select"
	_help_label.add_theme_font_size_override("font_size", 11)
	_help_label.add_theme_color_override("font_color", Color.WHITE)
	_help_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_help_label.add_theme_constant_override("shadow_offset_x", 1)
	_help_label.add_theme_constant_override("shadow_offset_y", 1)
	_ui_layer.add_child(_help_label)

	# Group filter dropdown (bottom-right)
	var _gf_container: HBoxContainer = HBoxContainer.new()
	_gf_container.name = "GroupFilter"
	_ui_layer.add_child(_gf_container)
	var gf_label: Label = Label.new()
	gf_label.text = "Show Group:"
	gf_label.add_theme_font_size_override("font_size", 11)
	gf_label.add_theme_color_override("font_color", Color.WHITE)
	_gf_container.add_child(gf_label)
	var gf_option: OptionButton = OptionButton.new()
	gf_option.name = "GroupFilterOption"
	gf_option.add_item("All", 0)
	gf_option.custom_minimum_size = Vector2(100, 24)
	gf_option.add_theme_font_size_override("font_size", 11)
	gf_option.item_selected.connect(_on_group_filter_changed)
	_gf_container.add_child(gf_option)
	# Position will be set in _process

func _has_ui_focus() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return focused != null and (focused is LineEdit or focused is SpinBox or focused is TextEdit)

func _unhandled_key_input(_event: InputEvent) -> void:
	pass  # C key handled in _process via polling

func _input(event: InputEvent) -> void:
	if not GameState.is_edit_mode:
		return
	# Release UI focus when clicking on game area
	if event is InputEventMouseButton and event.pressed and not _is_mouse_over_ui():
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused:
			focused.release_focus()
	# Don't handle game input when typing in UI
	if _has_ui_focus() and event is InputEventKey:
		return
	if event.is_action_pressed("block_next"):
		GameState.cycle_block(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("block_prev"):
		GameState.cycle_block(false)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			_line_mode = not _line_mode
			_line_drawing = false
			_curve_mode = false
			_deselect()
			queue_redraw()
		# C key for curve mode handled in _process
		# R = rotate 90° CW (group if selection, single block otherwise)
		if event.keycode == KEY_R or event.physical_keycode == KEY_R:
			if _has_selection:
				_rotate_group_90()
			else:
				# Single block under cursor: rotate in place by 90°
				var t: Vector2i = _get_tile()
				if WorldManager.get_tile(t.x, t.y) != 0:
					var cur: int = WorldManager.get_rotation(t.x, t.y)
					WorldManager.set_rotation(t.x, t.y, (cur + 90) % 360)
		# F = flip selected blocks horizontally
		if event.keycode == KEY_F or event.physical_keycode == KEY_F:
			push_warning("F_KEY align_sel=%s has_sel=%s indices=%d" % [str(_align_has_sel), str(_has_selection), _align_sel_indices.size()])
		if (event.keycode == KEY_F or event.physical_keycode == KEY_F) and (_align_has_sel or _has_selection):
			if _align_has_sel:
				for si in _align_sel_indices:
					if si < WorldManager.free_blocks.size():
						var fb: Dictionary = WorldManager.free_blocks[si]
						fb["flip_h"] = not fb.get("flip_h", false)
						push_warning("FLIP idx=%d id=%d flip_h=%s" % [si, fb.id, str(fb.flip_h)])
			elif _has_selection:
				# Grid block at _sel_start: convert to free block with flip
				_save_undo()
				var t: Vector2i = _sel_start
				var bid: int = WorldManager.get_tile(t.x, t.y)
				if bid != 0:
					var rot_deg: int = WorldManager.get_rotation(t.x, t.y)
					WorldManager.set_tile(t.x, t.y, 0)
					var fb: Dictionary = {"pos": Vector2(t.x * 16, t.y * 16), "id": bid, "rotation": float(rot_deg), "flip_h": true}
					WorldManager.free_blocks.append(fb)
					_align_sel_indices.append(WorldManager.free_blocks.size() - 1)
					_align_has_sel = true
			get_viewport().set_input_as_handled()
			queue_redraw()
		# Arrow keys = nudge selected blocks
		# Ctrl = 1px exact, Shift = 1.6px fine, Normal = 16px grid
		if _align_has_sel and _align_sel_indices.size() > 0:
			var nudge: Vector2 = Vector2.ZERO
			var step: float
			if Input.is_key_pressed(KEY_CTRL):
				step = 1.0
			elif Input.is_key_pressed(KEY_SHIFT):
				step = 1.6
			else:
				step = 16.0
			if event.keycode == KEY_LEFT: nudge.x = -step
			elif event.keycode == KEY_RIGHT: nudge.x = step
			elif event.keycode == KEY_UP: nudge.y = -step
			elif event.keycode == KEY_DOWN: nudge.y = step
			if nudge != Vector2.ZERO:
				if Input.is_key_pressed(KEY_CTRL):
					# Ctrl+Arrow = warp block TEXTURE size by 0.1px (hitbox unchanged)
					var warp_dir: Vector2 = nudge.sign()
					for si in _align_sel_indices:
						if si < WorldManager.free_blocks.size():
							var fb: Dictionary = WorldManager.free_blocks[si]
							var warp: Vector2 = GameState.get_custom_block_warp(fb.id)
							warp += warp_dir * 0.05
							GameState.set_custom_block_warp(fb.id, warp)
							push_warning("BLOCK_WARP id=%d warp=(%.2f,%.2f)" % [fb.id, warp.x, warp.y])
					# DON'T move grid — only warp texture
					get_viewport().set_input_as_handled()
					queue_redraw()
				else:
					_save_undo()
					for si in _align_sel_indices:
						if si < WorldManager.free_blocks.size():
							WorldManager.free_blocks[si].pos += nudge
					_align_wheel_pos += nudge
					_align_origin += nudge
					get_viewport().set_input_as_handled()
				queue_redraw()
		# Delete/Backspace = clear selected blocks
		if (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE) and (_has_selection or _align_has_sel):
			if _align_has_sel:
				_save_undo()
				# Remove polylines near selected blocks
				for del_si in _align_sel_indices:
					if del_si < WorldManager.free_blocks.size():
						var del_fb: Dictionary = WorldManager.free_blocks[del_si]
						WorldManager.remove_polyline_near(del_fb.pos + Vector2(8, 8), 20.0)
				_delete_aligned_selection()
			else:
				_clear_selection()
		# Escape = deselect
		if event.keycode == KEY_ESCAPE:
			_deselect()
			queue_redraw()

	# Rotation wheel input (checked FIRST, before UI/line mode)
	if (_has_selection or _align_has_sel) and not _line_mode:
		var wheel_center: Vector2
		if _align_has_sel:
			wheel_center = _align_wheel_pos
		else:
			wheel_center = _get_selection_center_world()
		var mouse_world: Vector2 = get_global_mouse_position()
		var dist_to_wheel: float = mouse_world.distance_to(wheel_center)

		if _rot_dragging:
			if event is InputEventMouseMotion:
				var raw_angle: float = (mouse_world - wheel_center).angle()
				var deg: float = rad_to_deg(raw_angle - _rot_angle)
				# Snap to 45° (Ctrl = free)
				var snap_deg: float = deg
				if not Input.is_key_pressed(KEY_CTRL):
					snap_deg = round(deg / 45.0) * 45.0
				# Rotate all free blocks around the group center
				_rotate_free_blocks(snap_deg)
				_align_drag_angle = snap_deg
				queue_redraw()
			if event.is_action_released("place_block"):
				_rot_dragging = false
				if _align_has_sel and _align_drag_angle != 0:
					_align_drag_angle = 0
					# Set grid directly from actual block state - no math drift
					if _align_sel_indices.size() > 0 and _align_sel_indices[0] < WorldManager.free_blocks.size():
						var ref_fb: Dictionary = WorldManager.free_blocks[_align_sel_indices[0]]
						_align_angle = ref_fb.rotation
						_angle_spin.set_value_no_signal(_align_angle)
						_align_origin = ref_fb.pos
			return

		# Only trigger rotation when clicking ON the wheel ring (±10px of circle)
		if event.is_action_pressed("place_block") and dist_to_wheel > ROT_WHEEL_RADIUS - 10 and dist_to_wheel < ROT_WHEEL_RADIUS + 10:
			_save_undo()
			_rot_dragging = true
			_rot_angle = (mouse_world - wheel_center).angle()
			if _align_has_sel:
				_lift_aligned_to_free(wheel_center)
			else:
				_lift_to_free()
			get_viewport().set_input_as_handled()
			return

		# Click inside selection (not on wheel ring) = start dragging to move
		var tile: Vector2i = _get_tile()
		var in_sel: bool = tile.x >= _selection.position.x and tile.x < _selection.position.x + _selection.size.x and tile.y >= _selection.position.y and tile.y < _selection.position.y + _selection.size.y
		# Also check if clicking on a selected free block
		var in_fb_sel: bool = false
		if _align_has_sel:
			var mg2: Vector2 = get_global_mouse_position()
			for si2 in _align_sel_indices:
				if si2 < WorldManager.free_blocks.size():
					var sfb2: Dictionary = WorldManager.free_blocks[si2]
					if mg2.distance_to(sfb2.pos + Vector2(8, 8)) < 16.0:
						in_fb_sel = true
						break

		if _move_dragging:
			if event is InputEventMouseMotion:
				if _align_has_sel:
					if Input.is_key_pressed(KEY_CTRL):
						# Free placement (pixel-perfect)
						var cur_world: Vector2 = get_global_mouse_position()
						var offset: Vector2 = cur_world - _align_move_start
						if offset.length() > 0.5:
							for si3 in _align_sel_indices:
								if si3 < WorldManager.free_blocks.size():
									WorldManager.free_blocks[si3].pos += offset
							_align_wheel_pos += offset
							_align_origin += offset
							_align_move_start = cur_world
					else:
						# Aligned grid snap
						var cur_snap: Vector2 = _get_aligned_snap(get_global_mouse_position())
						var offset: Vector2 = cur_snap - _align_move_start
						if offset.length() > 0.5:
							for si3 in _align_sel_indices:
								if si3 < WorldManager.free_blocks.size():
									WorldManager.free_blocks[si3].pos += offset
							_align_wheel_pos += offset
							_align_origin += offset
							_align_move_start = cur_snap
				else:
					var cur: Vector2i = _get_tile()
					var dx: int = cur.x - _move_start.x
					var dy: int = cur.y - _move_start.y
					if dx != 0 or dy != 0:
						_apply_move(dx, dy)
						_move_start = cur
				queue_redraw()
			if event.is_action_released("place_block"):
				_move_dragging = false
			return

		if event.is_action_pressed("place_block") and (in_sel or in_fb_sel):
			_save_undo()
			_move_dragging = true
			if _align_has_sel and in_fb_sel:
				if Input.is_key_pressed(KEY_CTRL):
					_align_move_start = get_global_mouse_position()
				else:
					_align_move_start = _get_aligned_snap(get_global_mouse_position())
			else:
				_move_start = tile
				_move_blocks.clear()
				for my in range(_selection.position.y, _selection.position.y + _selection.size.y):
					for mx in range(_selection.position.x, _selection.position.x + _selection.size.x):
						var bid: int = WorldManager.get_tile(mx, my)
						if bid != 0:
							_move_blocks.append({"rx": mx - _selection.position.x, "ry": my - _selection.position.y, "id": bid, "rot": WorldManager.get_rotation(mx, my)})
			get_viewport().set_input_as_handled()
			return

	# Ctrl+Z = undo, Ctrl+R = reset grid
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Z and Input.is_key_pressed(KEY_CTRL):
			_do_undo()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_R and Input.is_key_pressed(KEY_CTRL):
			if _align_has_sel and _align_sel_indices.size() > 0:
				# Reset rotation to 0° without moving blocks
				_save_undo()
				_align_angle = 0.0
				_angle_spin.set_value_no_signal(0.0)
				_align_origin = Vector2.ZERO
			else:
				_align_angle = 0.0
				_angle_spin.set_value_no_signal(0.0)
				_align_origin = Vector2.ZERO
				_deselect()
			queue_redraw()
			get_viewport().set_input_as_handled()
			return

	if _is_mouse_over_ui():
		return

	# Gravity zone mode: Shift+drag = center size, then drag = outer radius
	if _grav_zone_mode:
		if event.is_action_pressed("place_block"):
			_grav_zone_center = get_global_mouse_position()
			_grav_zone_dragging = true
			if Input.is_key_pressed(KEY_SHIFT):
				_grav_zone_phase = 1
			else:
				_grav_zone_phase = 2
				_grav_zone_center_r = 8.0
			queue_redraw()
			return
		# Phase transition also checked in motion handler above
		if event.is_action_released("place_block") and _grav_zone_dragging:
			var r: float = _grav_zone_center.distance_to(get_global_mouse_position())
			if _grav_zone_phase == 2 and r > _grav_zone_center_r + 5:
				_save_undo()
				WorldManager.gravity_zones.add_zone(_grav_zone_center, r, 2.0, _grav_zone_center_r)
				_grav_zone_dragging = false
				_grav_zone_phase = 0
			elif _grav_zone_phase == 2 and r <= _grav_zone_center_r + 5:
				# Too small radius, cancel
				_grav_zone_dragging = false
				_grav_zone_phase = 0
			# Phase 1 release: just stay in phase 2 (shift released handles transition)
			queue_redraw()
			return
		if event.is_action_pressed("remove_block"):
			if _grav_zone_dragging:
				_grav_zone_dragging = false
				_grav_zone_phase = 0
			else:
				_save_undo()
				WorldManager.gravity_zones.remove_zone_near(get_global_mouse_position())
			queue_redraw()
			return
		if (event is InputEventMouseMotion or event is InputEventKey) and _grav_zone_dragging:
			# Phase 1: sizing center (shift held)
			if _grav_zone_phase == 1:
				_grav_zone_center_r = clampf(_grav_zone_center.distance_to(get_global_mouse_position()), 4.0, 200.0)  # Max 25 blocks diameter (200px radius)
				# Auto-switch to radius phase when hitting max center size
				if _grav_zone_center_r >= 200.0:
					_grav_zone_phase = 2
				if not Input.is_key_pressed(KEY_SHIFT):
					_grav_zone_phase = 2
			queue_redraw()
			return

	# Curve mode (before align/selection so it gets clicks)
	if _curve_mode:
		if event.is_action_pressed("place_block"):
			_curve_points.append(get_global_mouse_position())
			_curve_preview = _compute_spline_blocks(_curve_points, get_global_mouse_position())
			queue_redraw()
			return
		if event.is_action_pressed("remove_block"):
			if _curve_points.size() > 0:
				_curve_points.pop_back()
			_curve_preview = _compute_spline_blocks(_curve_points, get_global_mouse_position())
			queue_redraw()
			return
		if event is InputEventMouseMotion:
			_curve_preview = _compute_spline_blocks(_curve_points, get_global_mouse_position())
			queue_redraw()
		return

	# Aligned mode: shift = rotated select, normal = place
	if _align_mode and Input.is_key_pressed(KEY_SHIFT):
		if event.is_action_pressed("place_block"):
			# Shift+click near gravity zone center = delete it
			var _gz_mouse: Vector2 = get_global_mouse_position()
			for _gzi in range(WorldManager.gravity_zones.zones.size()):
				if _gz_mouse.distance_to(WorldManager.gravity_zones.zones[_gzi].center) < 16.0:
					_save_undo()
					WorldManager.gravity_zones.zones.remove_at(_gzi)
					WorldManager.gravity_zones.zones_changed.emit()
					queue_redraw()
					return
			# Check for block under cursor — show selection immediately
			var _pmg: Vector2 = get_global_mouse_position()
			var _pfb_idx: int = -1
			for _pfi in range(WorldManager.free_blocks.size()):
				var _pfb: Dictionary = WorldManager.free_blocks[_pfi]
				if not _is_block_in_active_group(_pfb):
					continue
				if _pmg.distance_to(_pfb.pos + Vector2(8, 8)) < 14.0:
					_pfb_idx = _pfi
					break
			if _pfb_idx < 0:
				# Check grid tiles
				var _pgt: Vector2i = _get_tile()
				var _pgbid: int = WorldManager.get_tile(_pgt.x, _pgt.y)
				if _pgbid != 0 and _pgt.x > 0 and _pgt.y > 0 and _pgt.x < WorldManager.world_width - 1 and _pgt.y < WorldManager.world_height - 1:
					var _pgrot: float = float(WorldManager.get_rotation(_pgt.x, _pgt.y))
					var _pgpos: Vector2 = Vector2(_pgt.x * 16.0, _pgt.y * 16.0)
					WorldManager.free_blocks.append({"pos": _pgpos, "id": _pgbid, "rotation": _pgrot})
					WorldManager.net_set_tile(_pgt.x, _pgt.y, 0)
					WorldManager.set_rotation(_pgt.x, _pgt.y, 0)
					_pfb_idx = WorldManager.free_blocks.size() - 1
			if _pfb_idx >= 0:
				# Immediately show selection
				_deselect()
				var _psfb: Dictionary = WorldManager.free_blocks[_pfb_idx]
				_align_sel_indices = [_pfb_idx]
				_align_has_sel = true
				_has_selection = true
				_align_wheel_pos = _psfb.pos + Vector2(8, 8)
				_align_angle = _psfb.rotation
				_angle_spin.set_value_no_signal(_align_angle)
				_align_origin = _psfb.pos
				_align_block_id = _psfb.id
				queue_redraw()
			# Always start drag tracking (extends to box select if dragged)
			_align_sel_start = _get_aligned_local(get_global_mouse_position())
			_align_sel_end = _align_sel_start
			_align_sel_dragging = true
			# Reset drag state (keep selection if block was found)
			if _pfb_idx < 0:
				_align_has_sel = false
				_align_sel_indices.clear()
				_align_drag_angle = 0
				_align_wheel_pos = Vector2.ZERO
				_has_selection = false
				_free_originals.clear()
				_rot_dragging = false
				_move_dragging = false
		if event is InputEventMouseMotion and _align_sel_dragging:
			_align_sel_end = _get_aligned_local(get_global_mouse_position())
			queue_redraw()
		if event.is_action_released("place_block") and _align_sel_dragging:
			_align_sel_end = _get_aligned_local(get_global_mouse_position())
			_align_sel_dragging = false
			# If tiny drag (click) — keep selection from press handler
			var _drag_dist: float = (_align_sel_end - _align_sel_start).length()
			if _drag_dist < 0.5:
				# Already handled on press — just finalize
				if not _align_has_sel:
					_deselect()
				queue_redraw()
				return
			# Box select: clear single-block selection and find blocks in area
			_deselect()
			_align_sel_indices.clear()
			# Use world-space: get actual start/end world positions from the drag
			var _ws: Vector2 = _get_aligned_snap(get_global_mouse_position())
			# Compute world-space bounding box from drag corners
			var _ar2: float = deg_to_rad(_align_angle)
			var _s_world: Vector2 = _align_origin + (_align_sel_start * 16.0).rotated(_ar2)
			var _e_world: Vector2 = _align_origin + (_align_sel_end * 16.0).rotated(_ar2)
			var _wmin: Vector2 = Vector2(minf(_s_world.x, _e_world.x) - 16, minf(_s_world.y, _e_world.y) - 16)
			var _wmax: Vector2 = Vector2(maxf(_s_world.x, _e_world.x) + 16, maxf(_s_world.y, _e_world.y) + 16)
			# Selection bounds in rotated local space
			var _sel_mn: Vector2 = Vector2(minf(_align_sel_start.x, _align_sel_end.x) - 0.1, minf(_align_sel_start.y, _align_sel_end.y) - 0.1)
			var _sel_mx: Vector2 = Vector2(maxf(_align_sel_start.x, _align_sel_end.x) + 1.1, maxf(_align_sel_start.y, _align_sel_end.y) + 1.1)
			# Lift grid blocks that fall within the rotated selection area
			var _lift_inv: float = deg_to_rad(-_align_angle)
			var _tx0: int = maxi(1, int(floor(_wmin.x / 16.0)))
			var _ty0: int = maxi(1, int(floor(_wmin.y / 16.0)))
			var _tx1: int = mini(WorldManager.world_width - 1, int(ceil(_wmax.x / 16.0)))
			var _ty1: int = mini(WorldManager.world_height - 1, int(ceil(_wmax.y / 16.0)))
			for _ty in range(_ty0, _ty1):
				for _tx in range(_tx0, _tx1):
					var _bid: int = WorldManager.get_tile(_tx, _ty)
					if _bid != 0:
						var _bpos: Vector2 = Vector2(_tx * 16.0, _ty * 16.0)
						var _bcenter: Vector2 = _bpos + Vector2(8, 8)
						# Check in rotated local space
						var _bloc: Vector2 = (_bcenter - _align_origin).rotated(_lift_inv) / 16.0
						if _bloc.x >= _sel_mn.x and _bloc.x <= _sel_mx.x and _bloc.y >= _sel_mn.y and _bloc.y <= _sel_mx.y:
							var _brot: float = float(WorldManager.get_rotation(_tx, _ty))
							WorldManager.free_blocks.append({"pos": _bpos, "id": _bid, "rotation": _brot})
							WorldManager.net_set_tile(_tx, _ty, 0)
							WorldManager.set_rotation(_tx, _ty, 0)
			var _inv_ar: float = deg_to_rad(-_align_angle)
			for _fi in range(WorldManager.free_blocks.size()):
				var _fb: Dictionary = WorldManager.free_blocks[_fi]
				if not _is_block_in_active_group(_fb):
					continue
				var _fc: Vector2 = _fb.pos + Vector2(8, 8)
				# Transform block center to selection's local space
				var _local_fc: Vector2 = (_fc - _align_origin).rotated(_inv_ar) / 16.0
				if _local_fc.x >= _sel_mn.x and _local_fc.x <= _sel_mx.x and _local_fc.y >= _sel_mn.y and _local_fc.y <= _sel_mx.y:
					_align_sel_indices.append(_fi)
			# Store wheel center from actual selected blocks
			var _avg_pos: Vector2 = Vector2.ZERO
			for _wi in _align_sel_indices:
				if _wi < WorldManager.free_blocks.size():
					_avg_pos += WorldManager.free_blocks[_wi].pos + Vector2(8, 8)
			if _align_sel_indices.size() > 0:
				_avg_pos /= float(_align_sel_indices.size())
			_align_wheel_pos = _avg_pos
			if _align_sel_indices.size() > 0:
				_align_has_sel = true
				_has_selection = true
			queue_redraw()
		if event is InputEventKey and event.pressed and not event.echo:
			if (event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE) and _align_has_sel:
				_delete_aligned_selection()
		return

	if _align_mode:
		# Move-drag: click inside aligned selection to move blocks
		if _align_has_sel and not _align_sel_dragging:
			var mg: Vector2 = get_global_mouse_position()
			# Check if mouse is near any selected block (not grid coords)
			var in_asel: bool = false
			for si in _align_sel_indices:
				if si < WorldManager.free_blocks.size():
					var sfb: Dictionary = WorldManager.free_blocks[si]
					if mg.distance_to(sfb.pos + Vector2(8, 8)) < 16.0:
						in_asel = true
						break
			if _move_dragging:
				if event is InputEventMouseMotion:
					var cur_snap: Vector2 = _get_aligned_snap(get_global_mouse_position())
					var offset: Vector2 = cur_snap - _align_move_start
					if offset.length() > 0.5:
						for si in _align_sel_indices:
							if si < WorldManager.free_blocks.size():
								WorldManager.free_blocks[si].pos += offset
						_align_origin += offset
						_align_wheel_pos += offset
						_align_move_start = cur_snap
					queue_redraw()
				if event.is_action_released("place_block"):
					_move_dragging = false
				return
			if event.is_action_pressed("place_block") and in_asel:
				_save_undo()
				_move_dragging = true
				_align_move_start = _get_aligned_snap(mg)
				get_viewport().set_input_as_handled()
				return
		# Ctrl+drag line tool
		if Input.is_key_pressed(KEY_CTRL):
			if event.is_action_pressed("place_block"):
				_ctrl_line_start = _get_aligned_snap(get_global_mouse_position())
				_ctrl_line_active = true
				queue_redraw()
				return
			if event is InputEventMouseMotion and _ctrl_line_active:
				queue_redraw()
				return
			if event.is_action_released("place_block") and _ctrl_line_active:
				_ctrl_line_active = false
				var end_snap: Vector2 = _get_aligned_snap(get_global_mouse_position())
				var line_positions: Array = _get_aligned_line(_ctrl_line_start, end_snap)
				_save_undo()
				for lpos in line_positions:
					var exists: bool = false
					for fb in WorldManager.free_blocks:
						if fb.pos.distance_to(lpos) < 2.0:
							exists = true
							break
					if not exists:
						WorldManager.free_blocks.append({"pos": lpos, "id": GameState.selected_block_id, "rotation": _align_angle})
				queue_redraw()
				return

		# Clear stale selection when placing (not holding shift)
		if event.is_action_pressed("place_block") and not Input.is_key_pressed(KEY_SHIFT):
			if _align_has_sel:
				_deselect()
		var _place_aligned: bool = false
		if event.is_action_pressed("place_block"):
			_place_aligned = true
			_last_align_place = Vector2(-99999, -99999)
			_save_undo()  # Save once at drag start
		if event is InputEventMouseMotion and Input.is_action_pressed("place_block"):
			_place_aligned = true
		if _place_aligned:
			var snap_pos: Vector2 = _get_aligned_snap(get_global_mouse_position())
			# Fill line from last placed to current (prevents skipping at speed)
			var positions: Array = [snap_pos]
			if _last_align_place.x > -99000:
				var dist: float = snap_pos.distance_to(_last_align_place)
				if dist > 17.0:
					var steps: int = int(ceil(dist / 16.0))
					positions.clear()
					for si in range(steps + 1):
						var frac: float = float(si) / float(steps)
						var interp: Vector2 = _last_align_place.lerp(snap_pos, frac)
						var isnap: Vector2 = _get_aligned_snap(interp)
						if positions.is_empty() or positions[-1].distance_to(isnap) > 2.0:
							positions.append(isnap)
			var is_bg: bool = Input.is_key_pressed(KEY_TAB)
			for ppos in positions:
				var same_block: bool = false
				for fb in WorldManager.free_blocks:
					if fb.pos.distance_to(ppos) < 2.0 and fb.id == GameState.selected_block_id and fb.get("bg", false) == is_bg:
						same_block = true
						break
				if not same_block:
					var new_fb: Dictionary = {"pos": ppos, "id": GameState.selected_block_id, "rotation": _align_angle}
					if is_bg:
						new_fb["bg"] = true
					WorldManager.free_blocks.append(new_fb)
			_last_align_place = snap_pos
			queue_redraw()
		if event.is_action_pressed("remove_block"):
			_save_undo()  # Save once at start of erase drag
		if event.is_action_pressed("remove_block") or (event is InputEventMouseMotion and Input.is_action_pressed("remove_block")):
			var mouse: Vector2 = get_global_mouse_position()
			var best_i: int = -1
			var best_d: float = 12.0
			for i in range(WorldManager.free_blocks.size()):
				var fb: Dictionary = WorldManager.free_blocks[i]
				var d: float = mouse.distance_to(fb.pos + Vector2(8, 8))
				if d < best_d:
					best_d = d
					best_i = i
			if best_i >= 0:
				WorldManager.free_blocks.remove_at(best_i)
				queue_redraw()
			# Also try to remove polylines near the click
			WorldManager.remove_polyline_near(mouse, 16.0)
		if event is InputEventMouseMotion:
			queue_redraw()
		return

	# Line mode
	if _line_mode:
		if event.is_action_pressed("place_block"):
			_line_start = get_global_mouse_position()
			_line_drawing = true
		if event.is_action_released("place_block") and _line_drawing:
			var end_pos: Vector2 = get_global_mouse_position()
			if _line_start.distance_to(end_pos) > 8:
				WorldManager.add_line(_line_start, end_pos, Color(0.6, 0.6, 0.7, 1.0), 3.0)
			_line_drawing = false
		if event.is_action_pressed("remove_block"):
			WorldManager.remove_line_near(get_global_mouse_position(), 12.0)
		if event is InputEventMouseMotion:
			queue_redraw()
		return


	var shift: bool = Input.is_key_pressed(KEY_SHIFT)

	if event.is_action_pressed("place_block"):
		var t: Vector2i = _get_tile()
		if shift:
			# Check if clicking on a free block FIRST — switch selection directly
			var mg: Vector2 = get_global_mouse_position()
			var _clicked_fb: int = -1
			for fi in range(WorldManager.free_blocks.size()):
				var fb: Dictionary = WorldManager.free_blocks[fi]
				if mg.distance_to(fb.pos + Vector2(8, 8)) < 14.0:
					_clicked_fb = fi
					break
			if _clicked_fb >= 0:
				_deselect()
				# Auto-select this free block and activate align mode
				_align_sel_indices = [_clicked_fb]
				_align_has_sel = true
				_has_selection = true
				_align_mode = true
				var cfb: Dictionary = WorldManager.free_blocks[_clicked_fb]
				_align_wheel_pos = cfb.pos + Vector2(8, 8)
				_align_angle = cfb.rotation
				_angle_spin.set_value_no_signal(_align_angle)
				_align_origin = cfb.pos
				_align_block_id = cfb.id
				if _align_btn:
					_align_btn.button_pressed = true
				queue_redraw()
				return
			# Check if clicking on a grid tile — lift to free block and select
			var gt: Vector2i = _get_tile()
			var gbid: int = WorldManager.get_tile(gt.x, gt.y)
			if gbid != 0 and gt.x > 0 and gt.y > 0 and gt.x < WorldManager.world_width - 1 and gt.y < WorldManager.world_height - 1:
				_deselect()
				var grot: float = float(WorldManager.get_rotation(gt.x, gt.y))
				var gpos: Vector2 = Vector2(gt.x * 16.0, gt.y * 16.0)
				WorldManager.free_blocks.append({"pos": gpos, "id": gbid, "rotation": grot})
				WorldManager.net_set_tile(gt.x, gt.y, 0)
				WorldManager.set_rotation(gt.x, gt.y, 0)
				var new_idx: int = WorldManager.free_blocks.size() - 1
				_align_sel_indices = [new_idx]
				_align_has_sel = true
				_has_selection = true
				_align_mode = true
				_align_wheel_pos = gpos + Vector2(8, 8)
				_align_angle = grot
				_angle_spin.set_value_no_signal(_align_angle)
				_align_origin = gpos
				_align_block_id = gbid
				if _align_btn:
					_align_btn.button_pressed = true
				queue_redraw()
				return
			# Nothing clicked — deselect if selected, or start box select
			if _has_selection or _align_has_sel:
				_deselect()
				_rot_dragging = false
				queue_redraw()
				return
			_sel_start = t
			_sel_dragging = true
		elif Input.is_key_pressed(KEY_CTRL):
			# Ctrl+drag = line fill
			_drag_start = t
			_shift_dragging = true
		else:
			_place_at(t)
			_last_place = t

	if event.is_action_released("place_block"):
		if _sel_dragging:
			# Finalize box selection
			var t: Vector2i = _get_tile()
			var x0: int = mini(_sel_start.x, t.x)
			var y0: int = mini(_sel_start.y, t.y)
			var x1: int = maxi(_sel_start.x, t.x)
			var y1: int = maxi(_sel_start.y, t.y)
			_selection = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
			_has_selection = true
			_sel_dragging = false
			# Also select free blocks within the selection area
			_align_sel_indices.clear()
			var _wmin: Vector2 = Vector2(x0 * 16.0, y0 * 16.0)
			var _wmax: Vector2 = Vector2((x1 + 1) * 16.0, (y1 + 1) * 16.0)
			for _fi in range(WorldManager.free_blocks.size()):
				var _fb: Dictionary = WorldManager.free_blocks[_fi]
				var _fc: Vector2 = _fb.pos + Vector2(8, 8)
				if _fc.x >= _wmin.x and _fc.x <= _wmax.x and _fc.y >= _wmin.y and _fc.y <= _wmax.y:
					_align_sel_indices.append(_fi)
			if _align_sel_indices.size() > 0:
				_align_has_sel = true
		if _shift_dragging and _drag_start.x >= 0:
			var t: Vector2i = _get_tile()
			_fill_line(_drag_start, t, GameState.selected_block_id)
			_shift_dragging = false
			_drag_start = Vector2i(-1, -1)
		_last_place = Vector2i(-999, -999)

	if event.is_action_pressed("remove_block"):
		var t: Vector2i = _get_tile()
		if Input.is_key_pressed(KEY_CTRL):
			_drag_start = t
			_shift_dragging = true
		else:
			_erase_at(t)

	if event.is_action_released("remove_block"):
		if _shift_dragging and _drag_start.x >= 0:
			var t: Vector2i = _get_tile()
			_fill_line(_drag_start, t, 0)
			_shift_dragging = false
			_drag_start = Vector2i(-1, -1)

	if event is InputEventMouseMotion:
		_hover = _get_tile()
		queue_redraw()
		if not shift and not _shift_dragging:
			if Input.is_action_pressed("place_block"):
				var t: Vector2i = _get_tile()
				if t != _last_place:
					_place_at(t)
					_last_place = t
			elif Input.is_action_pressed("remove_block"):
				_erase_at(_get_tile())

func _is_mouse_over_ui() -> bool:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var panel_w: float = 16 * 36 + 32
	var panel_h: float = 300.0
	if mouse.x > vp_size.x - panel_w - 16 and mouse.y < panel_h + 16:
		return true
	# Camera pad on left
	if mouse.x < 140 and mouse.y > vp_size.y / 2 - 70 and mouse.y < vp_size.y / 2 + 70:
		return true
	# Spin panel on right (extended for group panel)
	if _spin_panel and _spin_panel.visible:
		var panel_rect: Rect2 = Rect2(_spin_panel.global_position, _spin_panel.size)
		if panel_rect.has_point(mouse):
			return true
	# Group filter bottom-right
	var gf: Control = _ui_layer.get_node_or_null("GroupFilter")
	if gf and gf.visible:
		var gf_rect: Rect2 = Rect2(gf.global_position, gf.size)
		if gf_rect.has_point(mouse):
			return true
	# Clear/Save buttons
	for btn_name in ["ClearWorldBtn", "SaveWorldBtn", "HelpBtn", "GravZoneBtn"]:
		var btn: Button = _ui_layer.get_node_or_null(btn_name) as Button
		if btn and btn.visible:
			var br: Rect2 = Rect2(btn.global_position, btn.size)
			if br.has_point(mouse):
				return true
	return false

func _on_group_pressed() -> void:
	if not _align_has_sel or _align_sel_indices.is_empty():
		return
	_save_undo()
	# Get group number from spinbox
	var id_spin: SpinBox = _spin_panel.get_node_or_null("HBoxContainer/GroupIdSpin")
	if not id_spin:
		for c in _spin_panel.get_children():
			var s: SpinBox = c.get_node_or_null("GroupIdSpin") as SpinBox
			if s:
				id_spin = s
				break
	var gid: int = int(id_spin.value) if id_spin else 1
	# Create group if it doesn't exist
	var g: Dictionary = WorldManager.get_group(gid)
	if g.is_empty():
		WorldManager._next_group_id = maxi(WorldManager._next_group_id, gid + 1)
		WorldManager.block_groups.append({
			"id": gid, "name": "Group %d" % gid,
			"move_dir": Vector2(1, 0), "move_speed": 32.0, "move_dist": 64.0,
			"move_type": "ping_pong", "_phase": 0.0, "_dir_sign": 1.0, "_origin": Vector2.ZERO
		})
		g = WorldManager.get_group(gid)
	# Set origin from first block
	if _align_sel_indices[0] < WorldManager.free_blocks.size():
		g["_origin"] = WorldManager.free_blocks[_align_sel_indices[0]].pos
	# Assign selected blocks to group
	for si in _align_sel_indices:
		if si < WorldManager.free_blocks.size():
			WorldManager.free_blocks[si]["group"] = gid
	_selected_group_id = gid
	_group_panel.visible = true
	_group_btn.text = "Group: %d" % gid
	_update_group_filter()
	queue_redraw()

func _show_group_props(gid: int) -> void:
	var g: Dictionary = WorldManager.get_group(gid)
	if g.is_empty():
		_group_panel.visible = false
		return
	_selected_group_id = gid
	_group_panel.visible = true
	_group_btn.text = "Group: %d" % gid

func _update_group_filter() -> void:
	var gf: OptionButton = _ui_layer.get_node_or_null("GroupFilter/GroupFilterOption")
	if not gf: return
	var prev: int = WorldManager.active_group_filter
	gf.clear()
	gf.add_item("All", 0)
	for g in WorldManager.block_groups:
		gf.add_item(g.name, g.id)
	# Restore selection
	for i in range(gf.item_count):
		if gf.get_item_id(i) == prev:
			gf.selected = i
			return
	gf.selected = 0
	WorldManager.active_group_filter = 0

func _on_group_filter_changed(idx: int) -> void:
	var gf: OptionButton = _ui_layer.get_node_or_null("GroupFilter/GroupFilterOption")
	if gf:
		WorldManager.active_group_filter = gf.get_item_id(idx)
	queue_redraw()

func _is_block_in_active_group(fb: Dictionary) -> bool:
	if WorldManager.active_group_filter == 0: return true
	return fb.get("group", -1) == WorldManager.active_group_filter

func _on_align_pressed() -> void:
	# Reset align-specific state (preserve _has_selection for origin finding)
	_align_has_sel = false
	_align_sel_indices.clear()
	_align_drag_angle = 0
	_align_wheel_pos = Vector2.ZERO
	_align_sel_dragging = false
	_free_originals.clear()
	_rot_dragging = false
	_move_dragging = false
	# Align mode is always on — just deselect
	_deselect()
	queue_redraw()
	# Find rotation from free blocks in selection or any free blocks
	var rot: float = 0.0
	var origin: Vector2 = Vector2.ZERO
	var found: bool = false
	if _has_selection:
		var sel_rect: Rect2 = Rect2(
			_selection.position.x * 16.0, _selection.position.y * 16.0,
			_selection.size.x * 16.0, _selection.size.y * 16.0)
		for fb in WorldManager.free_blocks:
			if sel_rect.has_point(fb.pos + Vector2(8, 8)):
				rot = fb.rotation
				origin = fb.pos
				found = true
				break
	if not found:
		for fb in WorldManager.free_blocks:
			if GameState.is_solid(fb.id) and absf(fb.rotation) > 0.1:
				rot = fb.rotation
				origin = fb.pos
				found = true
				break
	if found:
		_align_angle = rot
		_angle_spin.set_value_no_signal(_align_angle)
		_align_origin = origin
		_align_mode = true
		_align_btn.text = "Exit Align"
		_deselect()
		queue_redraw()

func _on_spin_speed_changed(val: float) -> void:
	_spin_speed_val = val
	_spin_label.text = "Speed: %d deg/s" % int(val)
	# Update ALL currently spinning blocks (they may have moved outside selection)
	for fb in WorldManager.free_blocks:
		if fb.has("base_offset"):  # Has been set up for spinning
			fb.spin = val

func _on_spin_pressed() -> void:
	if not _has_selection:
		return
	_lift_to_free()
	var sel_rect: Rect2 = Rect2(
		_selection.position.x * 16.0, _selection.position.y * 16.0,
		_selection.size.x * 16.0, _selection.size.y * 16.0)
	var center: Vector2 = sel_rect.position + sel_rect.size / 2.0
	var any_spinning: bool = false
	for fb in WorldManager.free_blocks:
		var fc: Vector2 = fb.pos + Vector2(8, 8)
		if sel_rect.has_point(fc):
			if fb.has("spin") and fb.spin != 0:
				any_spinning = true
				break
	for fb in WorldManager.free_blocks:
		var fc: Vector2 = fb.pos + Vector2(8, 8)
		if sel_rect.has_point(fc):
			if any_spinning:
				fb["spin"] = 0.0
				fb.erase("pivot")
				fb.erase("base_offset")
				fb.erase("base_rot")
				fb.erase("spin_angle")
			else:
				fb["spin"] = _spin_speed_val
				fb["pivot"] = center
				fb["base_offset"] = fb.pos + Vector2(8, 8) - center
				fb["base_rot"] = fb.rotation
				fb["spin_angle"] = 0.0
	_spin_btn.text = "Stop Spin" if not any_spinning else "Spin Object"

var _c_was_pressed: bool = false
func _process(_delta: float) -> void:
	# C key for curve mode (polled to avoid input consumption issues)
	if GameState.is_edit_mode:
		var c_now: bool = Input.is_physical_key_pressed(KEY_C)
		if c_now and not _c_was_pressed and not Input.is_key_pressed(KEY_CTRL):
			if _curve_mode and _curve_points.size() >= 2:
				# Confirm: build polyline (polygon strip renders the curve)
				_save_undo()
				# Build polyline from the spline curve directly (high resolution)
				if _curve_points.size() >= 2:
					var spline_pts: PackedVector2Array = PackedVector2Array()
					# Recompute spline at high resolution for smooth polyline
					var cpts: Array = _curve_points.duplicate()
					var vcp: Array = [cpts[0] - (cpts[1] - cpts[0])]
					vcp.append_array(cpts)
					vcp.append(cpts[-1] + (cpts[-1] - cpts[-2]))
					for cseg in range(1, vcp.size() - 2):
						var cp0: Vector2 = vcp[cseg - 1]
						var cp1: Vector2 = vcp[cseg]
						var cp2: Vector2 = vcp[cseg + 1]
						var cp3: Vector2 = vcp[cseg + 2]
						var cseg_len: float = cp1.distance_to(cp2)
						var csteps: int = int(max(4, ceil(cseg_len / 1.0)))
						for ci in range(csteps):
							var ct: float = float(ci) / float(csteps)
							var ctt: float = ct * ct
							var cttt: float = ctt * ct
							var spos: Vector2 = 0.5 * ((2.0 * cp1) + (-cp0 + cp2) * ct + (2.0 * cp0 - 5.0 * cp1 + 4.0 * cp2 - cp3) * ctt + (-cp0 + 3.0 * cp1 - 3.0 * cp2 + cp3) * cttt)
							if spline_pts.size() == 0 or spline_pts[-1].distance_to(spos) > 1.0:
								spline_pts.append(spos)
					# Always add final control point
					if spline_pts.size() > 0 and spline_pts[-1].distance_to(cpts[-1]) > 0.5:
						spline_pts.append(cpts[-1])
					if spline_pts.size() >= 2:
						# Truncate spline to last full 16px tile boundary
						var _tlen: float = 0.0
						for _ti in range(1, spline_pts.size()):
							_tlen += spline_pts[_ti].distance_to(spline_pts[_ti - 1])
						var _tmax: float = floor(_tlen / 16.0) * 16.0
						var _orig_pts: int = spline_pts.size()
						push_warning("CURVE_TRUNC len=%.1f max=%.1f remainder=%.1f pts=%d" % [_tlen, _tmax, _tlen - _tmax, spline_pts.size()])
						if _tmax >= 16.0:
							var _taccum: float = 0.0
							for _ti in range(1, spline_pts.size()):
								var _tseg: float = spline_pts[_ti].distance_to(spline_pts[_ti - 1])
								if _taccum + _tseg >= _tmax:
									var _tt: float = (_tmax - _taccum) / maxf(_tseg, 0.001)
									var _tcut: Vector2 = spline_pts[_ti - 1].lerp(spline_pts[_ti], _tt)
									spline_pts.resize(_ti)
									spline_pts.append(_tcut)
									push_warning("CURVE_TRUNC CUT at idx=%d new_pts=%d cut_pos=(%.1f,%.1f)" % [_ti, spline_pts.size(), _tcut.x, _tcut.y])
									break
								_taccum += _tseg
						WorldManager.add_polyline(spline_pts, "both", GameState.selected_block_id)
						# End cap blocks: centered at endpoints, rotated to tangent
						# Start cap: direction from point 0 toward point 1
						var s_dir: Vector2 = (spline_pts[1] - spline_pts[0]).normalized()
						var s_pos: Vector2 = spline_pts[0] - s_dir * 7.7 - Vector2(8, 8)
						var s_rot: float = rad_to_deg(atan2(s_dir.y, s_dir.x))
						WorldManager.free_blocks.append({"pos": s_pos, "id": GameState.selected_block_id, "rotation": s_rot})
						# End cap: spline already truncated to 16px boundary
						# Use a point 10px+ back for stable direction
						var e_ref_idx: int = spline_pts.size() - 2
						for _ei in range(spline_pts.size() - 2, 0, -1):
							if spline_pts[-1].distance_to(spline_pts[_ei]) >= 10.0:
								e_ref_idx = _ei
								break
						var e_dir: Vector2 = (spline_pts[-1] - spline_pts[e_ref_idx]).normalized()
						var e_pos: Vector2 = spline_pts[-1] + e_dir * 7.7 - Vector2(8, 8)
						# Check what render_dists ended up as
						var _rd: Array = WorldManager.polylines[-1].get("render_dists", [])
						var _rd_total: float = _rd[-1] if _rd.size() > 0 else -1.0
						var _rd_max: float = round(_rd_total / 16.0) * 16.0
						push_warning("ENDCAP spline_end=(%.1f,%.1f) cap_pos=(%.1f,%.1f) render_dist_total=%.1f render_max=%.1f" % [spline_pts[-1].x, spline_pts[-1].y, e_pos.x, e_pos.y, _rd_total, _rd_max])
						var e_rot: float = rad_to_deg(atan2(e_dir.y, e_dir.x))
						# Compute mirror from the mesh's actual truncation distance
						# Use the SPLINE truncation distance (_tmax) which we computed
						# _tmax is floor(_tlen/16)*16 — always exact multiple of 16
						var tile_count_from_trunc: int = int(_tmax / 16.0)
						var end_fb: Dictionary = {"pos": e_pos, "id": GameState.selected_block_id, "rotation": e_rot}
						# End cap is the tile AFTER the last mesh tile
						if tile_count_from_trunc % 2 == 1:
							end_fb["flip_h"] = true
						push_warning("ENDCAP_MIRROR trunc_tiles=%d rd_tiles=%d flip=%s" % [tile_count_from_trunc, int(round(_rd_total / 16.0)), str(end_fb.get("flip_h", false))])
						WorldManager.free_blocks.append(end_fb)
				_curve_points.clear()
				_curve_preview.clear()
				_curve_mode = false
			elif _curve_mode:
				# Exit without placing
				_curve_mode = false
				_curve_points.clear()
				_curve_preview.clear()
			else:
				# Enter curve mode
				_curve_mode = true
				_line_mode = false
				_deselect()
			queue_redraw()
		_c_was_pressed = c_now
	# Spin panel positioning
	if _spin_panel:
		var vp_size: Vector2 = get_viewport().get_visible_rect().size
		_spin_panel.visible = (_has_selection or _align_mode) and GameState.is_edit_mode
		var panel_y: float = maxf(8, minf(vp_size.y / 2 - _spin_panel.size.y / 2, vp_size.y - _spin_panel.size.y - 40))
		_spin_panel.position = Vector2(vp_size.x - _spin_panel.size.x - 8, panel_y)
	# Reset button always visible in edit mode
	# Clear world + Save world buttons under editor palette
	var clear_btn: Button = _ui_layer.get_node_or_null("ClearWorldBtn") as Button
	var save_btn: Button = _ui_layer.get_node_or_null("SaveWorldBtn") as Button
	if clear_btn:
		var vps3: Vector2 = get_viewport().get_visible_rect().size
		clear_btn.visible = GameState.is_edit_mode
		clear_btn.size = Vector2(90, 25)
		clear_btn.position = Vector2(vps3.x - 200, 320)
	if save_btn:
		var vps4: Vector2 = get_viewport().get_visible_rect().size
		save_btn.visible = GameState.is_edit_mode
		save_btn.size = Vector2(90, 25)
		save_btn.position = Vector2(vps4.x - 100, 320)
	# Help button + label
	var help_btn: Button = _ui_layer.get_node_or_null("HelpBtn") as Button
	var help_label: Label = _ui_layer.get_node_or_null("HelpLabel") as Label
	if help_btn:
		var vps5: Vector2 = get_viewport().get_visible_rect().size
		help_btn.visible = GameState.is_edit_mode
		help_btn.size = Vector2(25, 25)
		help_btn.position = Vector2(vps5.x - 230, 320)
	if help_label:
		help_label.position = Vector2(20, 80)
	# Gravity Zone button position
	if _grav_zone_btn:
		_grav_zone_btn.visible = GameState.is_edit_mode
		var vps_gz: Vector2 = get_viewport().get_visible_rect().size
		_grav_zone_btn.position = Vector2(vps_gz.x - 330, 320)
		if _grav_zone_mode:
			_grav_zone_btn.modulate = Color(0.8, 0.3, 1.0)
		else:
			_grav_zone_btn.modulate = Color.WHITE
		# Poll shift state for gravity zone phase transition
		if _grav_zone_dragging and _grav_zone_phase == 1 and not Input.is_key_pressed(KEY_SHIFT):
			_grav_zone_phase = 2
			queue_redraw()
	# Group filter position (bottom-right)
	var gf_node: Control = _ui_layer.get_node_or_null("GroupFilter")
	if gf_node:
		var vps: Vector2 = get_viewport().get_visible_rect().size
		gf_node.visible = GameState.is_edit_mode
		gf_node.position = Vector2(vps.x - 220, vps.y - 35)
	# Group button visibility
	if _group_btn:
		_group_btn.visible = _align_has_sel
	# Rotate spinning free blocks (rigid body from base positions)
	if WorldManager.free_blocks.size() > 0:
		for fb in WorldManager.free_blocks:
			if fb.has("base_offset") and fb.has("pivot"):
				fb.spin_angle += fb.spin * _delta
				var rad: float = deg_to_rad(fb.spin_angle)
				var pivot: Vector2 = fb.pivot
				var new_pos: Vector2 = pivot + fb.base_offset.rotated(rad) - Vector2(8, 8)
				fb.pos = new_pos
				fb.rotation = fb.base_rot + fb.spin_angle
	if GameState.is_edit_mode:
		queue_redraw()

func _draw() -> void:
	if not GameState.is_edit_mode:
		return

	# Use canvas transform for correct viewport bounds
	var ct: Transform2D = get_viewport().get_canvas_transform()
	var vp_size: Vector2 = get_viewport_rect().size
	var inv: Transform2D = ct.affine_inverse()
	var tl: Vector2 = inv * Vector2.ZERO
	var br: Vector2 = inv * vp_size
	var sx: int = maxi(0, int(floor(tl.x / 16.0)) - 1)
	var sy: int = maxi(0, int(floor(tl.y / 16.0)) - 1)
	var ex: int = mini(WorldManager.world_width, int(ceil(br.x / 16.0)) + 1)
	var ey: int = mini(WorldManager.world_height, int(ceil(br.y / 16.0)) + 1)

	var gc: Color = Color(1, 1, 1, 0.04)
	for gx in range(sx, ex + 1):
		draw_line(Vector2(gx * 16, sy * 16), Vector2(gx * 16, ey * 16), gc, 0.5)
	for gy in range(sy, ey + 1):
		draw_line(Vector2(sx * 16, gy * 16), Vector2(ex * 16, gy * 16), gc, 0.5)

	# Aligned placement mode: show rotated grid + cursor (cursor hidden during selection)
	if _align_mode:
		var rad: float = deg_to_rad(_align_angle)
		# Ghost cursor (only when not selecting)
		if not _align_has_sel:
			var mouse: Vector2 = get_global_mouse_position()
			var snap: Vector2 = _get_aligned_snap(mouse)
			var center: Vector2 = snap + Vector2(8, 8)
			draw_set_transform(center, rad, Vector2.ONE)
			draw_rect(Rect2(-8, -8, 16, 16), Color(0.3, 1.0, 0.3, 0.4), true)
			draw_rect(Rect2(-8, -8, 16, 16), Color(0.3, 1.0, 0.3, 0.8), false, 1.5)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		# Draw rotated grid lines centered on cursor (aligned to origin grid)
		var grid_col: Color = Color(0.3, 1.0, 0.3, 0.08)
		var cursor_snap: Vector2 = _get_aligned_snap(get_global_mouse_position())
		var grid_offset: Vector2 = Vector2(8, 8) - Vector2(8, 8).rotated(rad)
		var go: Vector2 = cursor_snap + grid_offset
		for i in range(-30, 31):
			draw_line(go + Vector2(i * 16, -500).rotated(rad), go + Vector2(i * 16, 500).rotated(rad), grid_col, 0.5)
			draw_line(go + Vector2(-500, i * 16).rotated(rad), go + Vector2(500, i * 16).rotated(rad), grid_col, 0.5)

	# Curve mode preview
	if _curve_mode:
		# Draw placed points
		for cp in _curve_points:
			draw_circle(cp, 4.0, Color(1.0, 0.5, 0.0, 0.9))
		# Draw preview blocks
		for bp in _curve_preview:
			var bc: Vector2 = bp.pos + Vector2(8, 8)
			draw_set_transform(bc, deg_to_rad(bp.rot), Vector2.ONE)
			draw_rect(Rect2(-8, -8, 16, 16), Color(1.0, 0.6, 0.2, 0.35), true)
			draw_rect(Rect2(-8, -8, 16, 16), Color(1.0, 0.6, 0.2, 0.8), false, 1.0)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		# Draw curve line through preview blocks
		if _curve_preview.size() >= 2:
			for ci in range(1, _curve_preview.size()):
				var pa: Vector2 = _curve_preview[ci - 1].pos + Vector2(8, 8)
				var pb: Vector2 = _curve_preview[ci].pos + Vector2(8, 8)
				draw_line(pa, pb, Color(1.0, 0.6, 0.2, 0.4), 1.5)
		# Draw mouse preview line to next point
		if _curve_points.size() >= 1:
			draw_line(_curve_points[-1], get_global_mouse_position(), Color(1.0, 0.6, 0.2, 0.3), 1.0)
		# Mode indicator
		# Mode indicator: draw in screen space via inverse canvas transform
		var inv_ct: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
		var screen_pos: Vector2 = inv_ct * Vector2(60, 20)
		draw_circle(screen_pos, 8.0, Color.ORANGE)
		draw_circle(screen_pos, 6.0, Color(1.0, 0.6, 0.0))

	# Ctrl+drag line preview
	if _ctrl_line_active and _align_mode:
		var line_rad: float = deg_to_rad(_align_angle)
		var end_snap: Vector2 = _get_aligned_snap(get_global_mouse_position())
		var preview_positions: Array = _get_aligned_line(_ctrl_line_start, end_snap)
		for pp in preview_positions:
			var pc: Vector2 = pp + Vector2(8, 8)
			draw_set_transform(pc, line_rad, Vector2.ONE)
			draw_rect(Rect2(-8, -8, 16, 16), Color(0.3, 1.0, 0.3, 0.35), true)
			draw_rect(Rect2(-8, -8, 16, 16), Color(0.3, 1.0, 0.3, 0.7), false, 1.0)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Aligned selection: draw from actual block positions in rotated local space
	if _align_mode and (_align_sel_dragging or _align_has_sel):
		var s: Vector2 = _align_sel_start
		var e: Vector2 = _align_sel_end if not _align_sel_dragging else _get_aligned_local(get_global_mouse_position())
		var mn: Vector2 = Vector2(minf(s.x, e.x), minf(s.y, e.y))
		var mx2: Vector2 = Vector2(maxf(s.x, e.x) + 1, maxf(s.y, e.y) + 1)
		# During drag: grid-based preview + highlight blocks in area
		if _align_sel_dragging and (_align_sel_end - _align_sel_start).length() > 0.3:
			var dar: float = deg_to_rad(_align_angle)
			var dvgo: Vector2 = _align_origin + Vector2(8, 8) + Vector2(-8, -8).rotated(dar)
			var dc0: Vector2 = dvgo + (mn * 16.0).rotated(dar)
			var dc1: Vector2 = dvgo + (Vector2(mx2.x, mn.y) * 16.0).rotated(dar)
			var dc2: Vector2 = dvgo + (mx2 * 16.0).rotated(dar)
			var dc3: Vector2 = dvgo + (Vector2(mn.x, mx2.y) * 16.0).rotated(dar)
			var dsc: Color = Color(0.3, 0.6, 1.0, 0.5)
			draw_line(dc0, dc1, dsc, 1.5)
			draw_line(dc1, dc2, dsc, 1.5)
			# Highlight blocks inside drag area
			var _d_sel_mn: Vector2 = Vector2(mn.x, mn.y)
			var _d_sel_mx: Vector2 = Vector2(mx2.x, mx2.y)
			var _d_inv: float = deg_to_rad(-_align_angle)
			for _dfi in range(WorldManager.free_blocks.size()):
				var _dfb: Dictionary = WorldManager.free_blocks[_dfi]
				var _dfc: Vector2 = _dfb.pos + Vector2(8, 8)
				var _dloc: Vector2 = (_dfc - _align_origin).rotated(_d_inv) / 16.0
				if _dloc.x >= _d_sel_mn.x and _dloc.x <= _d_sel_mx.x and _dloc.y >= _d_sel_mn.y and _dloc.y <= _d_sel_mx.y:
					draw_set_transform(_dfc, deg_to_rad(_dfb.rotation), Vector2.ONE)
					draw_rect(Rect2(-8, -8, 16, 16), Color(0.3, 0.6, 1.0, 0.3), true)
					draw_rect(Rect2(-8, -8, 16, 16), Color(0.3, 0.6, 1.0, 0.8), false, 1.5)
					draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			draw_line(dc2, dc3, dsc, 1.5)
			draw_line(dc3, dc0, dsc, 1.5)

		# Selection box: highlight each selected block individually
		for idx in _align_sel_indices:
			if idx < WorldManager.free_blocks.size():
				var fb: Dictionary = WorldManager.free_blocks[idx]
				var fc: Vector2 = fb.pos + Vector2(8, 8)
				draw_set_transform(fc, deg_to_rad(fb.rotation), Vector2.ONE)
				draw_rect(Rect2(-8, -8, 16, 16), Color(0.3, 0.6, 1.0, 0.15), true)
				draw_rect(Rect2(-8, -8, 16, 16), Color(0.3, 0.6, 1.0, 0.7), false, 1.5)
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

	# Hover highlight
	if not _align_mode and _hover.x >= 0 and _hover.y >= 0:
		var hr: Rect2 = Rect2(Vector2(_hover.x * 16, _hover.y * 16), Vector2(16, 16))
		draw_rect(hr, Color(1, 1, 1, 0.25), false, 1.5)

	# Shift-drag preview line
	if _shift_dragging and _drag_start.x >= 0:
		var end: Vector2i = _hover
		var points: Array = _get_line_points(_drag_start, end)
		for p in points:
			var pr: Rect2 = Rect2(Vector2(p.x * 16, p.y * 16), Vector2(16, 16))
			draw_rect(pr, Color(1, 1, 0.5, 0.25), true)
			draw_rect(pr, Color(1, 1, 0.5, 0.5), false, 1.0)

	# Draw all placed lines
	for line in WorldManager.lines:
		draw_line(line.start, line.end, line.color, line.width, true)

	# Line mode preview
	if _line_mode and _line_drawing:
		var mouse: Vector2 = get_global_mouse_position()
		draw_line(_line_start, mouse, Color(1, 1, 0.5, 0.6), 3.0, true)

	# Box selection preview while dragging
	if _sel_dragging:
		var end: Vector2i = _hover
		var x0: int = mini(_sel_start.x, end.x)
		var y0: int = mini(_sel_start.y, end.y)
		var x1: int = maxi(_sel_start.x, end.x)
		var y1: int = maxi(_sel_start.y, end.y)
		var sr: Rect2 = Rect2(Vector2(x0 * 16, y0 * 16), Vector2((x1 - x0 + 1) * 16, (y1 - y0 + 1) * 16))
		draw_rect(sr, Color(0.3, 0.6, 1.0, 0.15), true)
		draw_rect(sr, Color(0.3, 0.6, 1.0, 0.7), false, 2.0)

	# Rotation wheel for aligned selection
	if _align_mode and _align_has_sel and _align_sel_indices.size() > 0:
		var awc: Vector2 = _align_wheel_pos
		var wc2: Color = Color(0.4, 0.7, 1.0, 0.5) if not _rot_dragging else Color(0.5, 0.9, 1.0, 0.8)
		draw_arc(awc, ROT_WHEEL_RADIUS, 0, TAU, 32, wc2, 2.0)
		for tick2 in range(4):
			var a2: float = tick2 * PI / 2.0
			draw_line(awc + Vector2(cos(a2), sin(a2)) * (ROT_WHEEL_RADIUS - 6), awc + Vector2(cos(a2), sin(a2)) * (ROT_WHEEL_RADIUS + 6), wc2, 2.0)
		for tick2 in range(4):
			var a2: float = tick2 * PI / 2.0 + PI / 4.0
			draw_line(awc + Vector2(cos(a2), sin(a2)) * (ROT_WHEEL_RADIUS - 3), awc + Vector2(cos(a2), sin(a2)) * (ROT_WHEEL_RADIUS + 3), Color(wc2, 0.3), 1.0)
		# Handle shows current rotation angle
		var ha2: float = deg_to_rad(_align_angle)
		if _rot_dragging:
			ha2 = (get_global_mouse_position() - awc).angle()
		draw_circle(awc + Vector2(cos(ha2), sin(ha2)) * ROT_WHEEL_RADIUS, 5.0, Color(0.5, 0.8, 1.0, 0.9))

	# Existing selection highlight + rotation wheel (not in align mode)
	if _has_selection and not _align_mode:
		var sr: Rect2 = Rect2(
			Vector2(_selection.position.x * 16, _selection.position.y * 16),
			Vector2(_selection.size.x * 16, _selection.size.y * 16))
		draw_rect(sr, Color(0.2, 0.5, 1.0, 0.1), true)
		draw_rect(sr, Color(0.2, 0.5, 1.0, 0.6), false, 1.5)

		# Rotation wheel
		var wc: Vector2 = _get_selection_center_world()
		var wheel_col: Color = Color(0.4, 0.7, 1.0, 0.5) if not _rot_dragging else Color(0.5, 0.9, 1.0, 0.8)
		draw_arc(wc, ROT_WHEEL_RADIUS, 0, TAU, 32, wheel_col, 2.0)
		# 4 tick marks at 0°, 90°, 180°, 270°
		for tick in range(4):
			var a: float = tick * PI / 2.0
			var inner: Vector2 = wc + Vector2(cos(a), sin(a)) * (ROT_WHEEL_RADIUS - 6)
			var outer: Vector2 = wc + Vector2(cos(a), sin(a)) * (ROT_WHEEL_RADIUS + 6)
			draw_line(inner, outer, wheel_col, 2.0)
		# 4 more at 45° intervals (thinner)
		for tick in range(4):
			var a: float = tick * PI / 2.0 + PI / 4.0
			var inner: Vector2 = wc + Vector2(cos(a), sin(a)) * (ROT_WHEEL_RADIUS - 3)
			var outer: Vector2 = wc + Vector2(cos(a), sin(a)) * (ROT_WHEEL_RADIUS + 3)
			draw_line(inner, outer, Color(wheel_col, 0.3), 1.0)
		# Handle dot - show current drag angle or mouse direction
		var handle_angle: float = 0.0
		if _rot_dragging:
			var mw: Vector2 = get_global_mouse_position()
			handle_angle = (mw - wc).angle()
		var handle_pos: Vector2 = wc + Vector2(cos(handle_angle), sin(handle_angle)) * ROT_WHEEL_RADIUS
		draw_circle(handle_pos, 5.0, Color(0.5, 0.8, 1.0, 0.9))

	# Gravity zones
	for gz in WorldManager.gravity_zones.zones:
		draw_arc(gz.center, gz.radius, 0, TAU, 64, Color(0.8, 0.2, 1.0, 0.5), 2.0)
		draw_circle(gz.center, 4.0, Color(0.8, 0.2, 1.0, 0.8))
	# Gravity zone drag preview
	if _grav_zone_mode and _grav_zone_dragging:
		var mouse_r: float = _grav_zone_center.distance_to(get_global_mouse_position())
		if _grav_zone_phase == 1:
			# Sizing center — show center circle
			draw_arc(_grav_zone_center, mouse_r, 0, TAU, 48, Color(1.0, 0.3, 0.0, 0.6), 2.0)
			draw_circle(_grav_zone_center, 3.0, Color(1.0, 0.3, 0.0, 0.8))
		elif _grav_zone_phase == 2:
			# Sizing radius — show center + outer ring
			draw_arc(_grav_zone_center, _grav_zone_center_r, 0, TAU, 48, Color(1.0, 0.3, 0.0, 0.5), 1.5)
			draw_arc(_grav_zone_center, mouse_r, 0, TAU, 64, Color(0.8, 0.2, 1.0, 0.4), 1.5)
			draw_circle(_grav_zone_center, 3.0, Color(0.8, 0.2, 1.0, 0.7))
	# Mode indicator
	if _grav_zone_mode:
		var ct2: Transform2D = get_viewport().get_canvas_transform()
		var screen_pos: Vector2 = ct2.affine_inverse() * Vector2(20, 60)
		draw_circle(screen_pos, 6.0, Color(0.8, 0.2, 1.0, 0.8))

func _get_selection_center_world() -> Vector2:
	var cx: float = (_selection.position.x + _selection.size.x / 2.0) * 16.0
	var cy: float = (_selection.position.y + _selection.size.y / 2.0) * 16.0
	return Vector2(cx, cy)

func _get_tile() -> Vector2i:
	var m: Vector2 = get_global_mouse_position()
	return Vector2i(int(floor(m.x / 16.0)), int(floor(m.y / 16.0)))

func _place_at(t: Vector2i) -> void:
	if t.x <= 0 or t.x >= WorldManager.world_width - 1: return
	if t.y <= 0 or t.y >= WorldManager.world_height - 1: return
	var layer: String = GameState.get_block_layer(GameState.selected_block_id)
	if layer == "background":
		WorldManager.net_set_bg_tile(t.x, t.y, GameState.selected_block_id)
	else:
		WorldManager.set_tile(t.x, t.y, GameState.selected_block_id)

func _erase_at(t: Vector2i) -> void:
	if t.x <= 0 or t.x >= WorldManager.world_width - 1: return
	if t.y <= 0 or t.y >= WorldManager.world_height - 1: return
	WorldManager.net_set_tile(t.x, t.y, 0)
	WorldManager.net_set_bg_tile(t.x, t.y, 0)

func _fill_line(from: Vector2i, to: Vector2i, block_id: int) -> void:
	_save_undo()
	var points: Array = _get_line_points(from, to)
	for p in points:
		if p.x <= 0 or p.x >= WorldManager.world_width - 1: continue
		if p.y <= 0 or p.y >= WorldManager.world_height - 1: continue
		if block_id == 0:
			WorldManager.net_set_tile(p.x, p.y, 0)
			WorldManager.net_set_bg_tile(p.x, p.y, 0)
		else:
			WorldManager.set_tile(p.x, p.y, block_id)

func _get_line_points(from: Vector2i, to: Vector2i) -> Array:
	# Bresenham's line algorithm
	var points: Array = []
	var dx: int = absi(to.x - from.x)
	var dy: int = absi(to.y - from.y)
	var sx: int = 1 if from.x < to.x else -1
	var sy: int = 1 if from.y < to.y else -1
	var err: int = dx - dy
	var cx: int = from.x
	var cy: int = from.y
	while true:
		points.append(Vector2i(cx, cy))
		if cx == to.x and cy == to.y:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy
	return points

func _rotate_selection() -> void:
	if not _has_selection:
		return
	for ty in range(_selection.position.y, _selection.position.y + _selection.size.y):
		for tx in range(_selection.position.x, _selection.position.x + _selection.size.x):
			var bid: int = WorldManager.get_tile(tx, ty)
			if bid == 0:
				continue
			if GameState.is_slope(bid):
				if bid >= 2040:
					var rel: int = bid - 2040
					var block_group: int = (rel / 8) * 8
					var sub: int = rel % 8
					var orient: int = sub / 2
					var half_side: int = sub % 2
					orient = (orient + 1) % 4
					WorldManager.net_set_tile(tx, ty, 2040 + block_group + orient * 2 + half_side)
				else:
					var rel: int = bid - 2000
					var block_group: int = (rel / 4) * 4
					var orient: int = rel % 4
					orient = (orient + 1) % 4
					WorldManager.net_set_tile(tx, ty, 2000 + block_group + orient)
			else:
				# Regular blocks: replace with current selected block
				WorldManager.net_set_tile(tx, ty, GameState.selected_block_id)
	queue_redraw()

func _rotate_group_90() -> void:
	# Rotate the entire selection 90° clockwise: blocks physically move positions
	if not _has_selection:
		return
	var sx: int = _selection.position.x
	var sy: int = _selection.position.y
	var w: int = _selection.size.x
	var h: int = _selection.size.y
	var cx: float = sx + w / 2.0
	var cy: float = sy + h / 2.0

	# Read all blocks in selection
	var blocks: Array = []
	for ty in range(sy, sy + h):
		for tx in range(sx, sx + w):
			var bid: int = WorldManager.get_tile(tx, ty)
			var rot: int = WorldManager.get_rotation(tx, ty)
			if bid != 0:
				blocks.append({"x": tx, "y": ty, "id": bid, "rot": rot})

	# Clear old positions
	for b in blocks:
		WorldManager.net_set_tile(b.x, b.y, 0)
		WorldManager.set_rotation(b.x, b.y, 0)

	# Place at new rotated positions (90° CW around center)
	for b in blocks:
		var rel_x: float = float(b.x) - cx + 0.5
		var rel_y: float = float(b.y) - cy + 0.5
		# 90° CW: new_x = rel_y, new_y = -rel_x
		var new_x: int = int(floor(cx + rel_y - 0.5))
		var new_y: int = int(floor(cy - rel_x - 0.5))
		if new_x >= 1 and new_x < WorldManager.world_width - 1 and new_y >= 1 and new_y < WorldManager.world_height - 1:
			WorldManager.net_set_tile(new_x, new_y, b.id)
			WorldManager.set_rotation(new_x, new_y, (b.rot + 90) % 360)

	# Update selection rect to match new dimensions (w/h swap)
	var new_sx: int = int(floor(cx - h / 2.0))
	var new_sy: int = int(floor(cy - w / 2.0))
	_selection = Rect2i(new_sx, new_sy, h, w)
	queue_redraw()

func _apply_move(dx: int, dy: int) -> void:
	if not _has_selection or _move_blocks.is_empty():
		return
	# Clear old positions
	for my in range(_selection.position.y, _selection.position.y + _selection.size.y):
		for mx in range(_selection.position.x, _selection.position.x + _selection.size.x):
			WorldManager.net_set_tile(mx, my, 0)
			WorldManager.set_rotation(mx, my, 0)
	# Move selection rect
	_selection.position.x += dx
	_selection.position.y += dy
	# Place blocks at new positions
	for b in _move_blocks:
		var nx: int = _selection.position.x + b.rx
		var ny: int = _selection.position.y + b.ry
		if nx >= 1 and nx < WorldManager.world_width - 1 and ny >= 1 and ny < WorldManager.world_height - 1:
			WorldManager.net_set_tile(nx, ny, b.id)
			WorldManager.set_rotation(nx, ny, b.rot)

func _get_align_sel_center(include_drag: bool = false) -> Vector2:
	# Visual center of the aligned selection box
	# include_drag=false for pivot point (stays fixed), true for visual drawing
	var extra: float = _align_drag_angle if include_drag else 0.0
	var ar: float = deg_to_rad(_align_angle + extra)
	var vgo: Vector2 = _align_origin + Vector2(8, 8) + Vector2(-8, -8).rotated(ar)
	var mn: Vector2 = Vector2(minf(_align_sel_start.x, _align_sel_end.x), minf(_align_sel_start.y, _align_sel_end.y))
	var mx: Vector2 = Vector2(maxf(_align_sel_start.x, _align_sel_end.x) + 1, maxf(_align_sel_start.y, _align_sel_end.y) + 1)
	var c0: Vector2 = vgo + (mn * 16.0).rotated(ar)
	var c2: Vector2 = vgo + (mx * 16.0).rotated(ar)
	return (c0 + c2) / 2.0

func _get_aligned_local(world_pos: Vector2) -> Vector2:
	var rad: float = deg_to_rad(-_align_angle)
	var rel: Vector2 = world_pos - _align_origin
	var local: Vector2 = rel.rotated(rad)
	return Vector2(floor(local.x / 16.0), floor(local.y / 16.0))

func _compute_spline_blocks(points: Array, mouse_pos: Vector2) -> Array:
	## Compute blocks along a smooth spline through all points + mouse preview
	var pts: Array = points.duplicate()
	if pts.size() == 0:
		return []
	# Only append mouse if it's different from last point (avoid duplicate on confirm)
	if pts.size() == 0 or pts[-1].distance_to(mouse_pos) > 8.0:
		pts.append(mouse_pos)
	if pts.size() == 1:
		return [{"pos": pts[0] - Vector2(8, 8), "rot": 0.0, "curve": true}]
	if pts.size() == 2:
		return _compute_bezier_blocks(pts[0], (pts[0] + pts[1]) / 2.0, pts[1])
	# For 3+ points: chain quadratic beziers through midpoints
	var result: Array = []
	for seg in range(pts.size() - 1):
		var sp0: Vector2 = pts[seg]
		var sp2: Vector2 = pts[seg + 1]
		var sp1: Vector2  # Control point = average of neighboring midpoints
		if seg == 0:
			sp1 = sp0 + (sp2 - sp0) * 0.5
		elif seg == pts.size() - 2:
			sp1 = sp0 + (sp2 - sp0) * 0.5
		else:
			sp1 = (sp0 + sp2) / 2.0
		# For smooth curves: use the actual points as control points
		# and midpoints between consecutive points as segment endpoints
		pass
	# Catmull-Rom spline with O(1) dedup via grid hash
	var _spline_dedup: Dictionary = {}
	var cp: Array = [pts[0] - (pts[1] - pts[0])]
	cp.append_array(pts)
	cp.append(pts[-1] + (pts[-1] - pts[-2]))
	for seg in range(1, cp.size() - 2):
		var p0: Vector2 = cp[seg - 1]
		var p1: Vector2 = cp[seg]
		var p2: Vector2 = cp[seg + 1]
		var p3: Vector2 = cp[seg + 2]
		var seg_len: float = p1.distance_to(p2)
		var steps: int = int(max(2, ceil(seg_len / 2.0)))
		for i in range(steps):
			var t: float = float(i) / float(steps)
			# Catmull-Rom interpolation
			var tt: float = t * t
			var ttt: float = tt * t
			var pos: Vector2 = 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * tt + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * ttt)
			# Tangent
			var tan: Vector2 = 0.5 * ((-p0 + p2) + (4.0 * p0 - 10.0 * p1 + 8.0 * p2 - 2.0 * p3) * t + (-3.0 * p0 + 9.0 * p1 - 9.0 * p2 + 3.0 * p3) * tt)
			var angle: float = rad_to_deg(atan2(tan.y, tan.x))
			var block_pos: Vector2 = pos - Vector2(8, 8)
			var gk: int = int(floor(block_pos.x / 16.0)) * 10000 + int(floor(block_pos.y / 16.0))
			if not _spline_dedup.has(gk):
				_spline_dedup[gk] = true
				result.append({"pos": block_pos, "rot": angle, "curve": true})
	# Add final point
	if result.size() > 0:
		var last_pt: Vector2 = pts[-1] - Vector2(8, 8)
		var lk: int = int(floor(last_pt.x / 16.0)) * 10000 + int(floor(last_pt.y / 16.0))
		if not _spline_dedup.has(lk):
			var final_tan: Vector2 = pts[-1] - pts[-2]
			result.append({"pos": last_pt, "rot": rad_to_deg(atan2(final_tan.y, final_tan.x)), "curve": true})
	return result

func _compute_bezier_blocks(p0: Vector2, p1: Vector2, p2: Vector2) -> Array:
	## Compute block positions + rotations along a quadratic bezier curve
	var result: Array = []
	var total_len: float = 0.0
	var prev: Vector2 = p0
	# Estimate curve length
	for i in range(1, 51):
		var t: float = float(i) / 50.0
		var pt: Vector2 = p0 * (1.0 - t) * (1.0 - t) + p1 * 2.0 * (1.0 - t) * t + p2 * t * t
		total_len += prev.distance_to(pt)
		prev = pt
	# Place blocks every 14px (slight overlap to fill gaps)
	var spacing: float = 14.0
	var block_count: int = int(max(1, round(total_len / spacing)))
	for i in range(block_count + 1):
		var t: float = float(i) / float(block_count)
		# Bezier position
		var pos: Vector2 = p0 * (1.0 - t) * (1.0 - t) + p1 * 2.0 * (1.0 - t) * t + p2 * t * t
		# Bezier tangent (derivative)
		var tangent: Vector2 = (p1 - p0) * 2.0 * (1.0 - t) + (p2 - p1) * 2.0 * t
		var angle: float = rad_to_deg(atan2(tangent.y, tangent.x))
		# Block top-left from center
		var block_pos: Vector2 = pos - Vector2(8, 8)
		# Check for duplicates at same position
		var skip: bool = false
		for existing in result:
			if existing.pos.distance_to(block_pos) < 8.0:
				skip = true
				break
		if not skip:
			result.append({"pos": block_pos, "rot": angle, "curve": true})
	return result

func _aligned_local_to_world(local_grid: Vector2) -> Vector2:
	# Convert rotated grid coords back to world position
	var world_local: Vector2 = local_grid * 16.0
	return _align_origin + world_local.rotated(deg_to_rad(_align_angle))

func _delete_aligned_selection() -> void:
	var min_x: float = minf(_align_sel_start.x, _align_sel_end.x)
	var min_y: float = minf(_align_sel_start.y, _align_sel_end.y)
	var max_x: float = maxf(_align_sel_start.x, _align_sel_end.x)
	var max_y: float = maxf(_align_sel_start.y, _align_sel_end.y)
	var rad: float = deg_to_rad(-_align_angle)
	var i: int = WorldManager.free_blocks.size() - 1
	while i >= 0:
		var fb: Dictionary = WorldManager.free_blocks[i]
		var fc: Vector2 = fb.pos + Vector2(8, 8)
		var rel: Vector2 = fc - _align_origin
		var local: Vector2 = rel.rotated(rad) / 16.0
		if local.x >= min_x - 0.5 and local.x <= max_x + 0.5 and local.y >= min_y - 0.5 and local.y <= max_y + 0.5:
			# Also remove polylines near deleted blocks
			WorldManager.remove_polyline_near(fc, 20.0)
			WorldManager.free_blocks.remove_at(i)
		i -= 1
	_align_has_sel = false
	queue_redraw()

func _get_aligned_snap(world_pos: Vector2) -> Vector2:
	var rad: float = deg_to_rad(-_align_angle)
	var rel: Vector2 = world_pos - _align_origin
	var local: Vector2 = rel.rotated(rad)
	local.x = floor(local.x / 16.0) * 16.0
	local.y = floor(local.y / 16.0) * 16.0
	return _align_origin + local.rotated(-rad)

func _get_aligned_line(start: Vector2, end: Vector2) -> Array:
	## Returns array of snap positions along a line from start to end in aligned grid
	var inv_r: float = deg_to_rad(-_align_angle)
	var fwd_r: float = deg_to_rad(_align_angle)
	var local_s: Vector2 = (start - _align_origin).rotated(inv_r) / 16.0
	var local_e: Vector2 = (end - _align_origin).rotated(inv_r) / 16.0
	# Bresenham in local grid space
	var x0: int = int(floor(local_s.x))
	var y0: int = int(floor(local_s.y))
	var x1: int = int(floor(local_e.x))
	var y1: int = int(floor(local_e.y))
	var result: Array = []
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var cx: int = x0
	var cy: int = y0
	for _guard in range(1000):
		var world_pos: Vector2 = _align_origin + Vector2(cx * 16.0, cy * 16.0).rotated(fwd_r)
		result.append(world_pos)
		if cx == x1 and cy == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			cx += sx
		if e2 <= dx:
			err += dx
			cy += sy
	return result

var _free_originals: Array = []
var _free_center: Vector2 = Vector2.ZERO

func _lift_aligned_to_free(center_pt: Vector2) -> void:
	if _free_originals.size() > 0:
		return
	_free_center = center_pt
	# Use existing selection indices — no re-finding needed
	var to_remove: Array = []
	for si in _align_sel_indices:
		if si < WorldManager.free_blocks.size():
			var fb: Dictionary = WorldManager.free_blocks[si]
			_free_originals.append({"pos": fb.pos, "id": fb.id, "rot": fb.rotation})
			to_remove.append(si)
	to_remove.sort()
	for i in range(to_remove.size() - 1, -1, -1):
		WorldManager.free_blocks.remove_at(to_remove[i])
	for orig in _free_originals:
		WorldManager.free_blocks.append({"pos": orig.pos, "id": orig.id, "rotation": orig.rot})
	# Update indices to match new positions
	_align_sel_indices.clear()
	var base: int = WorldManager.free_blocks.size() - _free_originals.size()
	for j in range(_free_originals.size()):
		_align_sel_indices.append(base + j)

func _lift_to_free() -> void:
	# If already lifted, don't re-lift (blocks already off grid)
	if _free_originals.size() > 0:
		return
	var cx: float = (_selection.position.x + _selection.size.x / 2.0) * 16.0
	var cy: float = (_selection.position.y + _selection.size.y / 2.0) * 16.0
	_free_center = Vector2(cx, cy)
	# Lift grid tiles
	for ty in range(_selection.position.y, _selection.position.y + _selection.size.y):
		for tx in range(_selection.position.x, _selection.position.x + _selection.size.x):
			var bid: int = WorldManager.get_tile(tx, ty)
			if bid != 0:
				var pos: Vector2 = Vector2(tx * 16.0, ty * 16.0)
				_free_originals.append({"pos": pos, "id": bid, "rot": 0.0})
				WorldManager.free_blocks.append({"pos": pos, "id": bid, "rotation": 0.0})
				WorldManager.net_set_tile(tx, ty, 0)
				WorldManager.set_rotation(tx, ty, 0)
	# Also grab existing free blocks within selection area
	var sel_rect: Rect2 = Rect2(cx - (_selection.size.x / 2.0) * 16.0, cy - (_selection.size.y / 2.0) * 16.0,
		_selection.size.x * 16.0, _selection.size.y * 16.0)
	var to_remove: Array = []
	for i in range(WorldManager.free_blocks.size()):
		var fb: Dictionary = WorldManager.free_blocks[i]
		if sel_rect.has_point(fb.pos + Vector2(8, 8)):
			# Check it wasn't just added above (grid tiles)
			var is_new: bool = false
			for orig in _free_originals:
				if orig.pos.distance_to(fb.pos) < 1.0 and orig.id == fb.id and orig.rot == 0.0:
					is_new = true
					break
			if not is_new:
				_free_originals.append({"pos": fb.pos, "id": fb.id, "rot": fb.rotation})
				to_remove.append(i)
	# Remove grabbed free blocks (they'll be re-added by _rotate_free_blocks)
	for i in range(to_remove.size() - 1, -1, -1):
		WorldManager.free_blocks.remove_at(to_remove[i])
	# Re-add them at current positions (rotation 0 relative to group)
	for orig in _free_originals:
		if orig.rot != 0.0:
			WorldManager.free_blocks.append({"pos": orig.pos, "id": orig.id, "rotation": orig.rot})

func _rotate_free_blocks(angle_deg: float) -> void:
	var rad: float = deg_to_rad(angle_deg)
	# Remove only the blocks from this selection (keep previously placed free blocks)
	# Current selection blocks are at the END of the array (_free_originals.size() count)
	WorldManager.free_blocks.resize(WorldManager.free_blocks.size() - _free_originals.size())

	# Collect ALL corners of ALL blocks in world space
	var all_corners: Array = []
	for orig in _free_originals:
		var rel: Vector2 = orig.pos + Vector2(8, 8) - _free_center
		var rotated_pos: Vector2 = rel.rotated(rad)
		var new_pos: Vector2 = _free_center + rotated_pos - Vector2(8, 8)
		WorldManager.free_blocks.append({"pos": new_pos, "id": orig.id, "rotation": orig.rot + angle_deg})
		# 4 corners of this block
		var c: Vector2 = new_pos + Vector2(8, 8)
		all_corners.append(c + Vector2(-8, -8).rotated(rad))
		all_corners.append(c + Vector2(8, -8).rotated(rad))
		all_corners.append(c + Vector2(8, 8).rotated(rad))
		all_corners.append(c + Vector2(-8, 8).rotated(rad))

	# Bounding rect in local space
	var min_lx: float = INF
	var min_ly: float = INF
	var max_lx: float = -INF
	var max_ly: float = -INF
	for orig in _free_originals:
		var rel: Vector2 = orig.pos - _free_center + Vector2(8, 8)
		min_lx = minf(min_lx, rel.x - 8)
		min_ly = minf(min_ly, rel.y - 8)
		max_lx = maxf(max_lx, rel.x + 8)
		max_ly = maxf(max_ly, rel.y + 8)

	# 4 corners rotated to world
	var tl: Vector2 = _free_center + Vector2(min_lx, min_ly).rotated(rad)
	var tr: Vector2 = _free_center + Vector2(max_lx, min_ly).rotated(rad)
	var bl: Vector2 = _free_center + Vector2(min_lx, max_ly).rotated(rad)
	var br: Vector2 = _free_center + Vector2(max_lx, max_ly).rotated(rad)

	# No L-lines needed - collision is solid rectangle in _collides_px
	WorldManager.free_blocks_changed.emit()

func _convex_hull(points: Array) -> Array:
	# Gift wrapping (Jarvis march) for convex hull - returns CCW ordered points
	if points.size() < 3:
		return points
	# Find leftmost point
	var start: int = 0
	for i in range(1, points.size()):
		if points[i].x < points[start].x or (points[i].x == points[start].x and points[i].y < points[start].y):
			start = i
	var hull: Array = []
	var current: int = start
	var count: int = 0
	while count < 100:  # Safety limit
		hull.append(points[current])
		var next: int = 0
		for i in range(points.size()):
			if i == current:
				continue
			if next == current:
				next = i
				continue
			var cross: float = (points[i] - points[current]).cross(points[next] - points[current])
			if cross > 0:
				next = i
			elif cross == 0:
				# Collinear: pick the farther point
				if points[current].distance_squared_to(points[i]) > points[current].distance_squared_to(points[next]):
					next = i
		current = next
		count += 1
		if current == start:
			break
	return hull

func _get_rotated_corners(pos: Vector2, rad: float) -> Array:
	var center: Vector2 = pos + Vector2(8, 8)
	var offsets: Array = [Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]
	var corners: Array = []
	for off in offsets:
		corners.append(center + off.rotated(rad))
	return corners  # [top-left, top-right, bottom-right, bottom-left]

func _remove_free_block_lines() -> void:
	var i: int = WorldManager.lines.size() - 1
	while i >= 0:
		if WorldManager.lines[i].has("_free"):
			WorldManager.lines.remove_at(i)
		i -= 1

func _clear_selection() -> void:
	if not _has_selection:
		return
	# Clear grid tiles in selection
	for ty in range(_selection.position.y, _selection.position.y + _selection.size.y):
		for tx in range(_selection.position.x, _selection.position.x + _selection.size.x):
			WorldManager.net_set_tile(tx, ty, 0)
			WorldManager.net_set_bg_tile(tx, ty, 0)
	# Also remove free blocks within selection area
	var sel_rect: Rect2 = Rect2(
		_selection.position.x * 16.0, _selection.position.y * 16.0,
		_selection.size.x * 16.0, _selection.size.y * 16.0)
	var i: int = WorldManager.free_blocks.size() - 1
	while i >= 0:
		var fb: Dictionary = WorldManager.free_blocks[i]
		var fc: Vector2 = fb.pos + Vector2(8, 8)
		if sel_rect.has_point(fc):
			WorldManager.free_blocks.remove_at(i)
		i -= 1
	_deselect()
	queue_redraw()

func _snap_aligned_to_grid() -> void:
	# Convert axis-aligned free blocks (0°/90°/180°/270°) back to grid tiles
	var to_remove: Array = []
	for i in range(WorldManager.free_blocks.size()):
		var fb: Dictionary = WorldManager.free_blocks[i]
		if not GameState.is_solid(fb.id):
			continue
		var rot_mod: float = fmod(absf(fb.rotation), 90.0)
		if rot_mod > 1.0 and rot_mod < 89.0:
			continue  # Not axis-aligned, keep as free block
		# Snap position to grid
		var tx: int = int(round(fb.pos.x / 16.0))
		var ty: int = int(round(fb.pos.y / 16.0))
		if tx >= 0 and tx < WorldManager.world_width and ty >= 0 and ty < WorldManager.world_height:
			var grid_rot: int = int(round(fb.rotation / 90.0) * 90) % 360
			if grid_rot < 0: grid_rot += 360
			WorldManager.net_set_tile(tx, ty, fb.id)
			WorldManager.set_rotation(tx, ty, grid_rot)
			to_remove.append(i)
	for i in range(to_remove.size() - 1, -1, -1):
		WorldManager.free_blocks.remove_at(to_remove[i])

func _deselect() -> void:
	_has_selection = false
	_align_has_sel = false
	_align_sel_indices.clear()
	_free_originals.clear()
	_selected_group_id = -1
	if _group_panel:
		_group_panel.visible = false
	if _group_btn:
		_group_btn.text = "Add to Group"
